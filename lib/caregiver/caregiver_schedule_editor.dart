import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:intl/intl.dart'; 
import '../custom_bottom_nav.dart';
import 'caregiver_dashboard.dart';

class CaregiverScheduleEditor extends StatefulWidget {
  final String userEmail;
  final String? initialTargetEmail;

  const CaregiverScheduleEditor({
    super.key, 
    required this.userEmail, 
    this.initialTargetEmail,
  });

  @override
  State<CaregiverScheduleEditor> createState() => _CaregiverScheduleEditorState();
}

class _CaregiverScheduleEditorState extends State<CaregiverScheduleEditor> {
  final TextEditingController _medDetailsController = TextEditingController();
  String _selectedMealCondition = "After Meal";
  DateTime _pickerTime = DateTime.now();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  
  // 🎯 CHANGED: Replaced List<String> array with a clean single String representation
  String _currentMedTime = "12:00 PM"; 
  
  int _selectedIndex = 0; 
  String? _currentTargetEmail;
  String? _currentTargetName; 
  String? _currentTargetMachineId; 
  String? _machineOwnerEmail; 
  bool _isLoading = false;
  List<Map<String, dynamic>> _machineSlots = []; 
  
  StreamSubscription<DocumentSnapshot>? _machineSubscription;

  @override
  void initState() {
    super.initState();
    _currentTargetEmail = widget.initialTargetEmail;
    if (_currentTargetEmail != null) { 
      _fetchPatientMachineInfo(_currentTargetEmail!); 
    }
  }

  @override
  void dispose() {
    _machineSubscription?.cancel();
    _medDetailsController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _getLinkedPatientsStream() {
    return FirebaseFirestore.instance.collection('connections')
        .where('caregiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase()).snapshots();
  }

  Future<void> _fetchPatientMachineInfo(String pEmail) async {
    if (!mounted) return;
    setState(() { 
      _isLoading = true; 
      _currentTargetMachineId = null; 
      _machineOwnerEmail = null;
      _machineSlots = [];
      _selectedIndex = 0; 
    });

    await _machineSubscription?.cancel();

    try {
      var userDoc = await FirebaseFirestore.instance.collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase()).limit(1).get();
      if (userDoc.docs.isNotEmpty) {
        var userData = userDoc.docs.first.data();
        _currentTargetName = userData['name']; 
        String? machineId = userData['linkedMachineId']; 
        if (machineId != null && machineId.isNotEmpty) {
          _currentTargetMachineId = machineId;
          _listenToMachineStatus();
        } else { 
          if (mounted) setState(() => _isLoading = false); 
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  void _listenToMachineStatus() {
    if (_currentTargetMachineId == null) return;
    
    _machineSubscription = FirebaseFirestore.instance
        .collection('machines')
        .doc(_currentTargetMachineId!)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (snap.exists) {
        var machineData = snap.data()!;
        _machineOwnerEmail = machineData['linkedPatientEmail']?.toString().toLowerCase().trim();
        List<Map<String, dynamic>> retrievedSlots = List<Map<String, dynamic>>.from(machineData['slots'] ?? []);
        
        setState(() {
          if (retrievedSlots.length > 3) {
            _machineSlots = retrievedSlots.sublist(0, 3);
          } else {
            _machineSlots = retrievedSlots;
          }
          _isLoading = false; 
        });
        
        _loadSlotIntoForm(_selectedIndex);
      }
    });
  }

  void _loadSlotIntoForm(int index) {
    if (_machineSlots.isEmpty || index >= _machineSlots.length) return;
    var slot = _machineSlots[index];
    
    bool isMine = _machineOwnerEmail == _currentTargetEmail?.trim().toLowerCase();
    bool isOccupied = slot['status'] == "Occupied" || slot['status'] == "Completed";

    if (isOccupied && slot['endDate'] != null && slot['endDate'] != "") {
      try {
        DateTime parsedEndDate = DateTime.parse(slot['endDate']);
        DateTime allowedBoundary = DateTime(parsedEndDate.year, parsedEndDate.month, parsedEndDate.day);
        
        DateTime now = DateTime.now();
        DateTime todayMidnight = DateTime(now.year, now.month, now.day);
        
        if (todayMidnight.isAfter(allowedBoundary)) {
          _clearSlot(index: index);
          return;
        }
      } catch (e) {
        debugPrint("Auto-expiry computation anomaly: $e");
      }
    }

    setState(() {
      _selectedIndex = index;
      if (!isOccupied || isMine) {
        _medDetailsController.text = slot['medDetails'] ?? "";
        _selectedMealCondition = slot['mealCondition'] ?? "After Meal";
        
        // 🎯 CHANGED: Read timing as a direct string parameter securely
        String dbTime = slot['times'] ?? "";
        _currentMedTime = dbTime.trim().isNotEmpty ? dbTime : "12:00 PM";
        
        _startDate = (slot['startDate'] != null && slot['startDate'] != "") ? DateTime.parse(slot['startDate']) : DateTime.now();
        _endDate = (slot['endDate'] != null && slot['endDate'] != "") ? DateTime.parse(slot['endDate']) : DateTime.now().add(const Duration(days: 7));
      } else {
        _medDetailsController.text = "LOCKED: Occupied by another tracking deployment context.";
        _currentMedTime = "12:00 PM";
      }
    });
  }

  Future<void> _clearSlot({int? index}) async {
    if (_currentTargetMachineId == null || _currentTargetEmail == null) return;
    int targetIdx = index ?? _selectedIndex;
    if (mounted && index == null) setState(() => _isLoading = true);

    try {
      final String pEmail = _currentTargetEmail!.trim().toLowerCase();
      final int slotNum = targetIdx + 1;
      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      var logsToArchive = await FirebaseFirestore.instance.collection('adherence_logs')
          .where('patientEmail', isEqualTo: pEmail)
          .where('slot', isEqualTo: slotNum)
          .where('date', isGreaterThanOrEqualTo: todayStr)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      
      for (var doc in logsToArchive.docs) {
        batch.update(doc.reference, {
          "finalStatus": "Course Terminated",
          "status": "Archived",
          "isLocked": false,
          "archivedBy": widget.userEmail,
        });
      }

      if (_machineSlots.length > 3) _machineSlots = _machineSlots.sublist(0, 3);
      
      _machineSlots[targetIdx] = {
        "slot": slotNum, 
        "status": "Empty", 
        "medDetails": "",
        "times": "", // 🎯 CHANGED: Clears out tracking down to string format baseline
        "mealCondition": "After Meal", 
        "frequency": "Everyday",
        "startDate": "", 
        "endDate": "", 
        "isLocked": false, 
        "isDone": false,
        "adherenceStatus": "Archived", 
        "lastTakenDate": "", 
        "lastTakenTime": "",
        "remainingDays": 0,
        "singleDoseWeight": 0.0,
        "boxOpenTime": "",
        "boxCloseTime": "",
      };

      DocumentReference machineRef = FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId!);
      batch.update(machineRef, {"slots": _machineSlots});

      await batch.commit();

      if (mounted && index == null) _showMsg("Slot cleared. Schedule history logs archived.", Colors.blueGrey);
    } catch (e) {
      if (mounted && index == null) _showMsg("Reset Error: $e", Colors.red);
    } finally {
      if (mounted && index == null) setState(() => _isLoading = false);
    }
  }

  // --- DUAL WRITE SYNC PIPELINE ---
  Future<void> _saveChanges() async {
    if (_currentTargetMachineId == null || _currentTargetEmail == null) return;
    if (_medDetailsController.text.trim().isEmpty || _currentMedTime.isEmpty) {
      _showMsg("Medication and timing required.", Colors.orange); return;
    }

    bool isMine = _machineOwnerEmail == _currentTargetEmail?.trim().toLowerCase();
    if (_machineOwnerEmail != null && !isMine) {
      _showMsg("Operation Aborted: Target profile does not match hardware device owner.", Colors.red);
      return;
    }

    setState(() => _isLoading = true);
    final String pEmail = _currentTargetEmail!.trim().toLowerCase();
    final int slotNum = _selectedIndex + 1;
    final DateTime now = DateTime.now();
    final DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    final String todayStr = DateFormat('yyyy-MM-dd').format(todayMidnight);

    try {
      var logsToDelete = await FirebaseFirestore.instance.collection('adherence_logs')
          .where('patientEmail', isEqualTo: pEmail)
          .where('slot', isEqualTo: slotNum)
          .where('date', isGreaterThanOrEqualTo: todayStr)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in logsToDelete.docs) {
        batch.delete(doc.reference);
      }

      DateTime startPoint = _startDate.isBefore(todayMidnight) ? todayMidnight : _startDate;
      DateTime startMidnight = DateTime(startPoint.year, startPoint.month, startPoint.day);
      DateTime endMidnight = DateTime(_endDate.year, _endDate.month, _endDate.day);
      
      int totalDays = endMidnight.difference(startMidnight).inDays + 1;

      if (totalDays > 0) {
        for (int d = 0; d < totalDays; d++) {
          DateTime logDate = startMidnight.add(Duration(days: d));
          String logDateStr = DateFormat('yyyy-MM-dd').format(logDate);
          
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
            "mealCondition": _selectedMealCondition,
            "medDetails": _medDetailsController.text.trim(),
            "patientEmail": pEmail,
            "patientName": _currentTargetName ?? "Patient",
            "recordType": widget.userEmail == pEmail ? "Patient Setup" : "Caregiver Setup",
            "slot": slotNum,
            "status": "Occupied",
            
            // 🎯 CHANGED: Writing adherence log time parameter as pure String element context mapping
            "times": [_currentMedTime], 
            
            "timestamp": FieldValue.serverTimestamp(),
          });
        }
      }

      if (_machineSlots.length > 3) _machineSlots = _machineSlots.sublist(0, 3);
      
      var existingSlot = _machineSlots[_selectedIndex];
      String oldMedName = (existingSlot['medDetails'] ?? "").toString().trim().toLowerCase();
      String newMedName = _medDetailsController.text.trim().toLowerCase();
      
      bool isNewMedication = oldMedName != newMedName;

      _machineSlots[_selectedIndex] = {
        "slot": slotNum, 
        "status": "Occupied", 
        "medDetails": _medDetailsController.text.trim(), 
        
        // 🎯 CHANGED: Saving 'times' inside machines collection as raw String directly
        "times": _currentMedTime, 
        
        "mealCondition": _selectedMealCondition, 
        "frequency": "Everyday",
        "startDate": DateFormat('yyyy-MM-dd').format(_startDate),
        "endDate": DateFormat('yyyy-MM-dd').format(_endDate),
        "isLocked": isNewMedication ? true : (existingSlot['isLocked'] ?? true), 
        "isDone": isNewMedication ? false : (existingSlot['isDone'] ?? false),
        "adherenceStatus": isNewMedication ? "Upcoming" : (existingSlot['adherenceStatus'] ?? "Upcoming"), 
        "lastTakenDate": isNewMedication ? "" : (existingSlot['lastTakenDate'] ?? ""), 
        "lastTakenTime": isNewMedication ? "" : (existingSlot['lastTakenTime'] ?? ""),
        
        "remainingDays": isNewMedication ? 0 : (existingSlot['remainingDays'] ?? 0),
        "singleDoseWeight": isNewMedication ? 0.0 : (existingSlot['singleDoseWeight'] ?? 0.0),
        "boxOpenTime": isNewMedication ? "" : (existingSlot['boxOpenTime'] ?? ""),
        "boxCloseTime": isNewMedication ? "" : (existingSlot['boxCloseTime'] ?? ""),
      };

      DocumentReference machineRef = FirebaseFirestore.instance.collection('machines').doc(_currentTargetMachineId!);
      batch.update(machineRef, {"slots": _machineSlots});

      await batch.commit();
      _showMsg("Update successful. Synced cleanly with analytics parameters.", Colors.teal);
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
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CaregiverDashboard(userEmail: widget.userEmail)))
        ),
        title: const Text("Schedule Editor", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)), 
        backgroundColor: Colors.white, centerTitle: true, elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getLinkedPatientsStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No linked patients."));
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
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 1, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  Widget _buildConfigForm() {
    var slot = _machineSlots.isEmpty || _selectedIndex >= _machineSlots.length ? null : _machineSlots[_selectedIndex];
    bool isMine = _machineOwnerEmail == _currentTargetEmail?.trim().toLowerCase();
    bool isLockedOther = slot != null && (slot['status'] == "Occupied" || slot['status'] == "Completed") && !isMine;
    
    bool isSlotEmpty = slot == null || slot['status'] == "Empty";

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AbsorbPointer(
        absorbing: isLockedOther,
        child: Opacity(
          opacity: isLockedOther ? 0.5 : 1.0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildInputField("Medication Name", _medDetailsController, Icons.medication),
            const SizedBox(height: 20),
            
            const Text("Dietary Intake Requirements", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1A3B70))),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedMealCondition,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.restaurant),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              items: ["Before Meal", "After Meal", "With Meal", "Anytime"]
                  .map((condition) => DropdownMenuItem(value: condition, child: Text(condition)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedMealCondition = val);
              },
            ),
            const SizedBox(height: 20),
            
            Row(children: [
              Expanded(child: _buildDateTile("Starts", _startDate, () => _selectDate(context, true))), 
              const SizedBox(width: 12), 
              Expanded(child: _buildDateTile("Ends", _endDate, () => _selectDate(context, false)))
            ]),
            const SizedBox(height: 30),
            
            // 🎯 CHANGED: Clean display highlighting the current target time assignment
            const Text("Scheduled Dose Delivery Time", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1A3B70))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Row(
                children: [
                  const Icon(Icons.alarm, color: Color(0xFF1A3B70), size: 20),
                  const SizedBox(width: 12),
                  Text(_currentMedTime, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildTimePickerSection(),
          ]),
        ),
      ),
      const SizedBox(height: 40),
      Row(children: [
        if (isMine && !isSlotEmpty) 
          Expanded(child: OutlinedButton(onPressed: () => _clearSlot(), style: OutlinedButton.styleFrom(foregroundColor: Colors.red), child: const Text("Reset Slot"))),
        if (isMine && !isSlotEmpty) const SizedBox(width: 15),
        Expanded(
          flex: 2, 
          child: ElevatedButton(
            onPressed: isLockedOther ? null : _saveChanges, 
            style: ElevatedButton.styleFrom(backgroundColor: isLockedOther ? Colors.grey : const Color(0xFF1A3B70)), 
            child: Text(
              isLockedOther 
                  ? "BIN UNAVAILABLE" 
                  : (isSlotEmpty ? "Sync Slot" : "Update Slot"), 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
            )
          ),
        ),
      ]),
    ]);
  }

  Widget _buildPatientDropdown(List<DocumentSnapshot> pts) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15), 
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)), 
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _currentTargetEmail, 
        isExpanded: true, 
        hint: const Text("Select Patient"), 
        items: pts.map((p) => DropdownMenuItem<String>(value: p.get('patientEmail').toString(), child: Text(p.get('patientEmail')))).toList(), 
        onChanged: (v) { 
          if (v != null) { 
            setState(() => _currentTargetEmail = v); 
            _fetchPatientMachineInfo(v); 
          } 
        }
      )
    ),
  );

  Widget _buildSlotGrid() => GridView.builder(
    shrinkWrap: true, 
    physics: const NeverScrollableScrollPhysics(), 
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3, 
      crossAxisSpacing: 15, 
      mainAxisSpacing: 15,
      childAspectRatio: 1.3,
    ), 
    itemCount: 3, 
    itemBuilder: (c, i) { 
      bool isSelected = _selectedIndex == i; 
      var sl = _machineSlots.length > i ? _machineSlots[i] : null; 
      bool isOccupied = sl?['status'] == "Occupied" || sl?['status'] == "Completed";
      bool isMine = _machineOwnerEmail == _currentTargetEmail?.trim().toLowerCase();
      
      Color color = isMine ? Colors.green.shade100 : (isOccupied ? Colors.red.shade100 : Colors.white);
      if (isSelected) color = const Color(0xFF1A3B70);
      
      return GestureDetector(
        onTap: () => _loadSlotIntoForm(i), 
        child: Container(
          decoration: BoxDecoration(
            color: color, 
            border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: isSelected ? 2.5 : 1), 
            borderRadius: BorderRadius.circular(12),
          ), 
          child: Center(
            child: Text(
              "Bin ${i + 1}", 
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSelected ? Colors.white : Colors.black87),
            ),
          ),
        ),
      ); 
    },
  );

  Widget _buildInputField(String l, TextEditingController c, IconData i) => TextField(controller: c, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white));
  Widget _buildDateTile(String l, DateTime d, VoidCallback t) => InkWell(onTap: t, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(DateFormat('MMM d').format(d), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])));
  Future<void> _selectDate(BuildContext ctx, bool isS) async { final DateTime? p = await showDatePicker(context: ctx, initialDate: isS ? _startDate : _endDate, firstDate: isS ? DateTime.now().subtract(const Duration(days: 1)) : _startDate, lastDate: DateTime(2030)); if (p != null) setState(() { if (isS) { _startDate = p; if (_endDate.isBefore(_startDate)) _endDate = _startDate; } else { _endDate = p; } }); }
  
  // 🎯 CHANGED: Simplified picker configuration to directly assign value to _currentMedTime string
  Widget _buildTimePickerSection() => SizedBox(
    height: 110,
    child: CupertinoDatePicker(
      mode: CupertinoDatePickerMode.time,
      initialDateTime: DateFormat("hh:mm a").parse(_currentMedTime),
      onDateTimeChanged: (t) {
        setState(() {
          _pickerTime = t;
          _currentMedTime = DateFormat("hh:mm a").format(t);
        });
      },
    ),
  );
  
  Widget _buildMachineHeader() => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.settings_remote, size: 18), const SizedBox(width: 10), Text("Device ID: ${_currentTargetMachineId}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]));
}