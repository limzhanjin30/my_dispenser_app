import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:intl/intl.dart'; 
import '../custom_bottom_nav.dart';
import 'healthcare_dashboard.dart';

class HealthcarePrescription extends StatefulWidget {
  final String userEmail;
  final String? initialTargetEmail; // FIXED: Added this parameter

  const HealthcarePrescription({
    super.key, 
    required this.userEmail, 
    this.initialTargetEmail, // FIXED: Added to constructor
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
  String? _currentTargetMachineId; 
  bool _isLoading = false;
  List<Map<String, dynamic>> _machineSlots = []; 

  @override
  void initState() {
    super.initState();
    // FIXED: Handle initial patient selection from the Registry
    _currentTargetEmail = widget.initialTargetEmail;
    if (_currentTargetEmail != null) {
      _fetchPatientMachineInfo(_currentTargetEmail!);
    }
  }

  // --- DATABASE: CLINICAL CONNECTIONS ---
  Stream<QuerySnapshot> _getLinkedPatientsStream() {
    return FirebaseFirestore.instance
        .collection('connections')
        .where('healthcareEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
        .snapshots();
  }

  Future<void> _fetchPatientMachineInfo(String pEmail) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _currentTargetMachineId = null; 
    });
    
    try {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userDoc.docs.isNotEmpty) {
        String? machineId = userDoc.docs.first.get('linkedMachineId'); 
        if (machineId != null && machineId.isNotEmpty) {
          _currentTargetMachineId = machineId;
          _listenToMachineStatus();
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToMachineStatus() {
    if (_currentTargetMachineId == null) return;
    FirebaseFirestore.instance
        .collection('machines')
        .doc(_currentTargetMachineId)
        .snapshots()
        .listen((snap) {
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
    bool isOccupied = slot['status'] == "Occupied";

    // AUTO-CLEAR LOGIC
    if (isOccupied && slot['endDate'] != "") {
      DateTime now = DateTime.now();
      DateTime todayMidnight = DateTime(now.year, now.month, now.day);
      DateTime end = DateTime.parse(slot['endDate']);
      if ((todayMidnight.isAtSameMomentAs(end) || todayMidnight.isAfter(end)) && slot['isDone'] == true) {
        _clearSlot(index: index, silent: true); 
        return;
      }
    }

    setState(() {
      _selectedIndex = index;
      if (isMine || !isOccupied) {
        _medDetailsController.text = slot['medDetails'] ?? "";
        _selectedMealCondition = slot['mealCondition'] ?? "After Meal";
        _currentMedTimes = List<String>.from(slot['times'] ?? []);
        _startDate = (slot['startDate'] != null && slot['startDate'] != "") ? DateTime.parse(slot['startDate']) : DateTime.now();
        _endDate = (slot['endDate'] != null && slot['endDate'] != "") ? DateTime.parse(slot['endDate']) : DateTime.now().add(const Duration(days: 7));
      } else {
        _medDetailsController.text = "LOCKED: Occupied";
      }
    });
  }

  Future<void> _clearSlot({int? index, bool silent = false}) async {
    if (_currentTargetMachineId == null) return;
    int targetIdx = index ?? _selectedIndex;
    if (!silent) setState(() => _isLoading = true);

    _machineSlots[targetIdx] = {
      "slot": targetIdx + 1, "status": "Empty", "patientEmail": "", "medDetails": "",
      "times": [], "mealCondition": "After Meal", "frequency": "Everyday",
      "startDate": "", "endDate": "", "isLocked": false, "isDone": false,
      "adherenceStatus": "Upcoming", "lastTakenDate": "", "lastTakenTime": "",
    };

    await FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId).update({"slots": _machineSlots});
    if (!silent) setState(() => _isLoading = false);
  }

  Future<void> _saveChanges() async {
    if (_currentTargetMachineId == null || _currentTargetEmail == null) return;
    setState(() => _isLoading = true);
    _machineSlots[_selectedIndex] = {
      "slot": _selectedIndex + 1, "status": "Occupied", "patientEmail": _currentTargetEmail!.trim().toLowerCase(),
      "medDetails": _medDetailsController.text, "times": _currentMedTimes, "mealCondition": _selectedMealCondition,
      "frequency": "Everyday", "startDate": DateFormat('yyyy-MM-dd').format(_startDate), "endDate": DateFormat('yyyy-MM-dd').format(_endDate),
      "isLocked": true, "isDone": false, "adherenceStatus": "Upcoming", "lastTakenDate": "", "lastTakenTime": "",
    };
    await FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId).update({"slots": _machineSlots});
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text("Prescription Manager", style: TextStyle(color: Color(0xFF1A3B70), fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, centerTitle: true, elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getLinkedPatientsStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No patients found."));
          var pts = snapshot.data!.docs;

          return _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Target Clinical Patient", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
              const SizedBox(height: 10),
              _buildPatientDropdown(pts),
              const SizedBox(height: 25),
              if (_currentTargetEmail == null) const Center(child: Text("Select a patient to begin."))
              else if (_currentTargetMachineId == null) const Center(child: Text("No hardware hub found."))
              else ...[
                const Text("Select Physical Bin:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
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

  Widget _buildPatientDropdown(List<DocumentSnapshot> pts) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)), 
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _currentTargetEmail, isExpanded: true, hint: const Text("Select Patient", style: TextStyle(color: Colors.grey, fontSize: 14)), items: pts.map((p) => DropdownMenuItem<String>(value: p.get('patientEmail').toString(), child: Text(p.get('patientEmail')))).toList(), onChanged: (v) { if (v != null) { setState(() => _currentTargetEmail = v); _fetchPatientMachineInfo(v); } })),
  );

  Widget _buildSlotGrid() => GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: 10, itemBuilder: (c, i) { bool s = _selectedIndex == i; var sl = _machineSlots.length > i ? _machineSlots[i] : null; bool occ = sl?['status'] == "Occupied"; bool m = sl?['patientEmail'] == _currentTargetEmail; return GestureDetector(onTap: () => _loadSlotIntoForm(i), child: Container(decoration: BoxDecoration(color: s ? const Color(0xFF1A3B70) : (occ ? (m ? Colors.green.shade100 : Colors.red.shade100) : Colors.white), borderRadius: BorderRadius.circular(10), border: Border.all(color: s ? Colors.blue : Colors.grey.shade300)), child: Center(child: Text("${i + 1}", style: TextStyle(fontWeight: FontWeight.bold, color: s ? Colors.white : Colors.black))))); });

  Widget _buildConfigForm() {
    var slot = _machineSlots[_selectedIndex];
    bool isMine = slot['patientEmail'] == _currentTargetEmail?.trim().toLowerCase();
    bool isLockedOther = slot['status'] == "Occupied" && !isMine;
    return Column(children: [
      AbsorbPointer(absorbing: isLockedOther, child: Opacity(opacity: isLockedOther ? 0.4 : 1.0, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildInputField("Medication Name", _medDetailsController, Icons.medication),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _buildDateTile("Starts", _startDate, () => _selectDate(context, true))), 
          const SizedBox(width: 12), 
          Expanded(child: _buildDateTile("Ends", _endDate, () => _selectDate(context, false)))
        ]),
        const SizedBox(height: 30),
        _buildTimeChips(),
        _buildTimePickerSection(),
      ]))),
      const SizedBox(height: 40),
      Row(children: [
        if (slot['status'] == "Occupied" && isMine) Expanded(child: OutlinedButton(onPressed: () => _clearSlot(), child: const Text("Clear Slot"))),
        if (slot['status'] == "Occupied" && isMine) const SizedBox(width: 15),
        Expanded(flex: 2, child: ElevatedButton(onPressed: isLockedOther ? null : _saveChanges, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70)), child: Text(isLockedOther ? "OCCUPIED" : "Lock Bin ${_selectedIndex + 1}"))),
      ]),
    ]);
  }

  Widget _buildInputField(String l, TextEditingController c, IconData i) => TextField(controller: c, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))));
  Widget _buildDateTile(String l, DateTime d, VoidCallback t) => InkWell(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(DateFormat('MMM d').format(d), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])));
  Future<void> _selectDate(BuildContext ctx, bool isS) async { final DateTime? p = await showDatePicker(context: ctx, initialDate: isS ? _startDate : _endDate, firstDate: isS ? DateTime.now().subtract(const Duration(days: 365)) : _startDate, lastDate: DateTime(2030)); if (p != null) setState(() { if (isS) { _startDate = p; if (_endDate.isBefore(_startDate)) _endDate = _startDate; } else { _endDate = p; } }); }
  Widget _buildTimeChips() => Wrap(spacing: 8, children: _currentMedTimes.map((t) => Chip(label: Text(t), onDeleted: () => setState(() => _currentMedTimes.remove(t)))).toList());
  Widget _buildTimePickerSection() => Row(children: [Expanded(child: SizedBox(height: 100, child: CupertinoDatePicker(mode: CupertinoDatePickerMode.time, onDateTimeChanged: (t) => _pickerTime = t))), IconButton.filled(onPressed: () { String f = DateFormat("hh:mm a").format(_pickerTime); if (!_currentMedTimes.contains(f)) setState(() { _currentMedTimes.add(f); _currentMedTimes.sort(); }); }, icon: const Icon(Icons.add_alarm))]);
}