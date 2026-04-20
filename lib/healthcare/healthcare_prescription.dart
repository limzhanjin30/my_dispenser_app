import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:intl/intl.dart'; 
import '../custom_bottom_nav.dart';
import 'healthcare_dashboard.dart';

class HealthcarePrescription extends StatefulWidget {
  final String userEmail;
  final String? initialTargetEmail;

  const HealthcarePrescription({
    super.key, 
    required this.userEmail, 
    this.initialTargetEmail,
  });

  @override
  State<HealthcarePrescription> createState() => _HealthcarePrescriptionState();
}

class _HealthcarePrescriptionState extends State<HealthcarePrescription> {
  final TextEditingController _medDetailsController = TextEditingController();
  String _selectedMealCondition = "After Meal";
  DateTime _pickerTime = DateTime.now();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  List<String> _currentMedTimes = [];
  int _selectedIndex = 0; 
  String? _currentTargetEmail;
  String? _currentTargetName; 
  String? _currentTargetMachineId; 
  bool _isLoading = false;
  List<Map<String, dynamic>> _machineSlots = []; 

  @override
  void initState() {
    super.initState();
    _currentTargetEmail = widget.initialTargetEmail;
    if (_currentTargetEmail != null) { _fetchPatientMachineInfo(_currentTargetEmail!); }
  }

  // --- DATABASE FETCH: CLINICAL CONNECTIONS ---
  Stream<QuerySnapshot> _getLinkedPatientsStream() {
    return FirebaseFirestore.instance.collection('connections')
        .where('healthcareEmail', isEqualTo: widget.userEmail.trim().toLowerCase()).snapshots();
  }

  Future<void> _fetchPatientMachineInfo(String pEmail) async {
    if (!mounted) return;
    setState(() { _isLoading = true; _currentTargetMachineId = null; });
    try {
      var userDoc = await FirebaseFirestore.instance.collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase()).limit(1).get();
      if (userDoc.docs.isNotEmpty) {
        var userData = userDoc.docs.first.data();
        _currentTargetName = userData['name'] ?? "Patient";
        String? machineId = userData['linkedMachineId']; 
        if (machineId != null && machineId.isNotEmpty) {
          _currentTargetMachineId = machineId;
          _listenToMachineStatus();
        } else { if (mounted) setState(() => _isLoading = false); }
      }
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _listenToMachineStatus() {
    if (_currentTargetMachineId == null) return;
    FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId).snapshots().listen((snap) {
      if (!mounted) return;
      if (snap.exists) {
        setState(() {
          _machineSlots = List<Map<String, dynamic>>.from(snap.data()!['slots']);
          _isLoading = false; 
        });
        _loadSlotIntoForm(_selectedIndex);
      }
    });
  }

  void _loadSlotIntoForm(int index) {
    if (_machineSlots.isEmpty || index >= _machineSlots.length) return;
    var slot = _machineSlots[index];
    bool isMine = slot['patientEmail'] == _currentTargetEmail?.trim().toLowerCase();
    bool isOccupied = slot['status'] == "Occupied" || slot['status'] == "Completed";

    setState(() {
      _selectedIndex = index;
      if (!isOccupied || isMine) {
        _medDetailsController.text = slot['medDetails'] ?? "";
        _selectedMealCondition = slot['mealCondition'] ?? "After Meal";
        _currentMedTimes = List<String>.from(slot['times'] ?? []);
        _startDate = (slot['startDate'] != null && slot['startDate'] != "") ? DateTime.parse(slot['startDate']) : DateTime.now();
        _endDate = (slot['endDate'] != null && slot['endDate'] != "") ? DateTime.parse(slot['endDate']) : DateTime.now().add(const Duration(days: 7));
      } else {
        _medDetailsController.text = "LOCKED: Occupied by another patient";
        _currentMedTimes = [];
      }
    });
  }

  // --- LOGIC: FINISH COURSE (Batch terminates all future logs) ---
  Future<void> _clearSlot({int? index}) async {
    if (_currentTargetMachineId == null || _currentTargetEmail == null) return;
    int targetIdx = index ?? _selectedIndex;
    setState(() => _isLoading = true);

    try {
      final String pEmail = _currentTargetEmail!.trim().toLowerCase();
      final int slotNum = targetIdx + 1;

      // Find any logs for this bin that are still 'Occupied'
      var existingLogs = await FirebaseFirestore.instance.collection('adherence_logs')
          .where('patientEmail', isEqualTo: pEmail)
          .where('slot', isEqualTo: slotNum)
          .where('status', isEqualTo: "Occupied")
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in existingLogs.docs) {
        batch.update(doc.reference, {
          "finalStatus": "Course Terminated",
          "status": "Archived",
          "isLocked": false,
          "archivedBy": widget.userEmail,
        });
      }
      await batch.commit();

      _machineSlots[targetIdx] = {
        "slot": slotNum, "status": "Empty", "patientEmail": "", "patientName": "",
        "medDetails": "", "times": [], "mealCondition": "After Meal", "frequency": "Everyday",
        "startDate": "", "endDate": "", "isLocked": false, "isDone": false,
        "adherenceStatus": "Upcoming", "lastTakenDate": "", "lastTakenTime": "",
      };

      await FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId).update({"slots": _machineSlots});
      _showMsg("Slot cleared. Prescription records terminated.", Colors.blueGrey);
    } catch (e) {
      _showMsg("Reset Error: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: SAVE/SYNC (Creates/Updates individual dose logs with patientName) ---
  Future<void> _saveChanges() async {
    if (_currentTargetMachineId == null || _currentTargetEmail == null) return;
    if (_medDetailsController.text.trim().isEmpty || _currentMedTimes.isEmpty) {
      _showMsg("Prescription name and timing required.", Colors.orange); return;
    }

    setState(() => _isLoading = true);
    final String pEmail = _currentTargetEmail!.trim().toLowerCase();
    final int slotNum = _selectedIndex + 1;

    try {
      var existingLogs = await FirebaseFirestore.instance.collection('adherence_logs')
          .where('patientEmail', isEqualTo: pEmail)
          .where('slot', isEqualTo: slotNum)
          .where('status', isEqualTo: "Occupied")
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();

      if (existingLogs.docs.isNotEmpty) {
        // --- ACTION: UPDATE EXISTING (Regardless of creator) ---
        for (var doc in existingLogs.docs) {
          batch.update(doc.reference, {
            "medDetails": _medDetailsController.text.trim(),
            "mealCondition": _selectedMealCondition,
            "patientName": _currentTargetName ?? "Patient",
            "recordType": "Healthcare Update",
            "timestamp": FieldValue.serverTimestamp(),
          });
        }
      } else {
        // --- ACTION: CREATE ONE LOG PER DAY AND PER TIME SLOT ---
        int totalDays = _endDate.difference(_startDate).inDays + 1;
        for (int d = 0; d < totalDays; d++) {
          DateTime logDate = _startDate.add(Duration(days: d));
          String logDateStr = DateFormat('yyyy-MM-dd').format(logDate);
          
          for (String timeSlot in _currentMedTimes) {
            DocumentReference newLogRef = FirebaseFirestore.instance.collection('adherence_logs').doc();
            batch.set(newLogRef, {
              "adherenceStatus": "Upcoming",
              "archivedBy": widget.userEmail,
              "date": logDateStr,
              "finalStatus": "Course Active",
              "frequency": "Everyday",
              "isDone": false,
              "isLocked": true,
              "lastTakenTime": "",
              "medDetails": _medDetailsController.text.trim(),
              "mealCondition": _selectedMealCondition,
              "patientEmail": pEmail,
              "patientName": _currentTargetName ?? "Patient",
              "recordType": "Healthcare Setup",
              "slot": slotNum,
              "status": "Occupied",
              "times": [timeSlot], 
              "timestamp": FieldValue.serverTimestamp(),
            });
          }
        }
      }
      
      await batch.commit();

      // Update machine hardware state
      _machineSlots[_selectedIndex] = {
        "slot": slotNum, "status": "Occupied", "patientEmail": pEmail,
        "patientName": _currentTargetName ?? "Patient",
        "medDetails": _medDetailsController.text.trim(), "times": _currentMedTimes,
        "mealCondition": _selectedMealCondition, "frequency": "Everyday",
        "startDate": DateFormat('yyyy-MM-dd').format(_startDate),
        "endDate": DateFormat('yyyy-MM-dd').format(_endDate),
        "isLocked": true, "isDone": false,
        "adherenceStatus": "Upcoming", "lastTakenDate": "", "lastTakenTime": "",
      };

      await FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId).update({"slots": _machineSlots});
      _showMsg("Success. Clinical prescription synced.", Colors.teal);
    } catch (e) {
      _showMsg("Sync Error: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMsg(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HealthcareDashboard(userEmail: widget.userEmail)))
        ),
        title: const Text("Clinical Prescriber", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)), 
        backgroundColor: Colors.white, centerTitle: true, elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getLinkedPatientsStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No linked patients in clinical registry."));
          var pts = snapshot.data!.docs;
          return _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildPatientDropdown(pts),
              const SizedBox(height: 25),
              if (_currentTargetEmail != null && _currentTargetMachineId != null) ...[
                _buildMachineHeader(),
                const SizedBox(height: 30),
                const Text("Select Hardware Bin:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                const SizedBox(height: 12),
                _buildSlotGrid(), 
                const SizedBox(height: 35),
                _buildConfigForm(),
              ],
            ]),
          );
        },
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 1, role: "Healthcare\nProvider", userEmail: widget.userEmail),
    );
  }

  Widget _buildConfigForm() {
    var slot = _machineSlots[_selectedIndex];
    bool isMine = slot['patientEmail'] == _currentTargetEmail?.trim().toLowerCase();
    bool isLockedOther = (slot['status'] == "Occupied" || slot['status'] == "Completed") && !isMine;
    
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AbsorbPointer(
        absorbing: isLockedOther,
        child: Opacity(
          opacity: isLockedOther ? 0.5 : 1.0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildInputField("Medication & Instructions", _medDetailsController, Icons.medical_services_outlined),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _buildDateTile("Starts", _startDate, () => _selectDate(context, true))), 
              const SizedBox(width: 12), 
              Expanded(child: _buildDateTile("Ends", _endDate, () => _selectDate(context, false)))
            ]),
            const SizedBox(height: 30),
            const Text("Alarm Schedule", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1A3B70))),
            const SizedBox(height: 8),
            _buildTimeChips(), 
            _buildTimePickerSection(),
          ]),
        ),
      ),
      const SizedBox(height: 40),
      Row(children: [
        if (isMine && slot['status'] != "Empty") 
          Expanded(child: OutlinedButton(onPressed: () => _clearSlot(), style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: const Text("Finish Course"))),
        if (isMine && slot['status'] != "Empty") const SizedBox(width: 15),
        Expanded(
          flex: 2, 
          child: ElevatedButton(
            onPressed: isLockedOther ? null : _saveChanges, 
            style: ElevatedButton.styleFrom(backgroundColor: isLockedOther ? Colors.grey : const Color(0xFF1A3B70)), 
            child: Text(isLockedOther ? "BIN UNAVAILABLE" : (isMine ? "Update Prescription" : "Lock Bin ${_selectedIndex + 1}"), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ),
      ]),
    ]);
  }

  Widget _buildPatientDropdown(List<DocumentSnapshot> pts) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)), 
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _currentTargetEmail, isExpanded: true, hint: const Text("Select Patient"), items: pts.map((p) => DropdownMenuItem<String>(value: p.get('patientEmail').toString(), child: Text(p.get('patientEmail')))).toList(), onChanged: (v) { if (v != null) { setState(() => _currentTargetEmail = v); _fetchPatientMachineInfo(v); } })),
  );

  Widget _buildSlotGrid() => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: 10, itemBuilder: (c, i) { 
    bool isSelected = _selectedIndex == i; 
    var sl = _machineSlots.length > i ? _machineSlots[i] : null; 
    bool isOccupied = sl?['status'] == "Occupied" || sl?['status'] == "Completed";
    bool isMine = sl?['patientEmail'] == _currentTargetEmail?.trim().toLowerCase();
    Color color = isMine ? Colors.green.shade100 : (isOccupied ? Colors.red.shade100 : Colors.white);
    if (isSelected) color = const Color(0xFF1A3B70);
    return GestureDetector(onTap: () => _loadSlotIntoForm(i), child: Container(decoration: BoxDecoration(color: color, border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300), borderRadius: BorderRadius.circular(10)), child: Center(child: Text("${i + 1}", style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black))))); 
  });

  Widget _buildInputField(String l, TextEditingController c, IconData i) => TextField(controller: c, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white));
  Widget _buildDateTile(String l, DateTime d, VoidCallback t) => InkWell(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(DateFormat('MMM d').format(d), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])));
  Future<void> _selectDate(BuildContext ctx, bool isS) async { final DateTime? p = await showDatePicker(context: ctx, initialDate: isS ? _startDate : _endDate, firstDate: isS ? DateTime.now().subtract(const Duration(days: 1)) : _startDate, lastDate: DateTime(2030)); if (p != null) setState(() { if (isS) { _startDate = p; if (_endDate.isBefore(_startDate)) _endDate = _startDate; } else { _endDate = p; } }); }
  Widget _buildTimeChips() => Align(alignment: Alignment.centerLeft, child: Wrap(alignment: WrapAlignment.start, spacing: 8, children: _currentMedTimes.map((t) => Chip(label: Text(t, style: const TextStyle(fontSize: 12)), onDeleted: () => setState(() => _currentMedTimes.remove(t)))).toList()));
  Widget _buildTimePickerSection() => Row(children: [Expanded(child: SizedBox(height: 100, child: CupertinoDatePicker(mode: CupertinoDatePickerMode.time, onDateTimeChanged: (t) => _pickerTime = t))), IconButton.filled(onPressed: () { String f = DateFormat("hh:mm a").format(_pickerTime); if (!_currentMedTimes.contains(f)) setState(() { _currentMedTimes.add(f); _currentMedTimes.sort(); }); }, icon: const Icon(Icons.add_alarm))]);
  Widget _buildMachineHeader() => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.settings_remote, size: 18), const SizedBox(width: 10), Text("Device ID: ${_currentTargetMachineId}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]));
}