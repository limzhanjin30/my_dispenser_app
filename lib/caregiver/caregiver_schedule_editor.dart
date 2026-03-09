import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:intl/intl.dart'; 
import '../custom_bottom_nav.dart';

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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pillCountController = TextEditingController();
  final TextEditingController _dayIntervalController = TextEditingController(text: "2");

  String _selectedMealCondition = "After Meal";
  String _selectedFrequency = "Everyday";
  DateTime _pickerTime = DateTime.now();
  
  // DATE VARIABLES
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7)); // Default: 1 week duration

  List<String> _currentMedTimes = [];
  int _selectedIndex = 0; 
  String? _currentTargetEmail;
  bool _isLoading = false;

  List<Map<String, dynamic>> _localSlots = [];

  @override
  void initState() {
    super.initState();
    _currentTargetEmail = widget.initialTargetEmail;
    if (_currentTargetEmail != null) {
      _loadPatientSchedule(_currentTargetEmail!);
    }
  }

  Stream<QuerySnapshot> _getLinkedPatientsStream() {
    return FirebaseFirestore.instance
        .collection('connections')
        .where('caregiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
        .snapshots();
  }

  Future<void> _loadPatientSchedule(String pEmail) async {
    setState(() => _isLoading = true);
    String cleanEmail = pEmail.trim().toLowerCase();

    try {
      var doc = await FirebaseFirestore.instance.collection('schedules').doc(cleanEmail).get();

      if (doc.exists && doc.data()!.containsKey('slots')) {
        setState(() {
          _localSlots = List<Map<String, dynamic>>.from(doc.data()!['slots']);
        });
      } else {
        setState(() {
          _localSlots = List.generate(5, (index) => {
            "slot": (index + 1).toString(),
            "name": "Empty Slot ${index + 1}",
            "pills": "0",
            "times": [],
            "mealCondition": "After Meal",
            "frequency": "Everyday",
            "startDate": DateFormat('yyyy-MM-dd').format(DateTime.now()),
            "endDate": DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 7))), // NEW
            "isDone": false,
          });
        });
      }
      _loadSlotIntoForm(0); 
    } catch (e) {
      debugPrint("Error loading schedule: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadSlotIntoForm(int index) {
    if (_localSlots.isEmpty) return;
    var med = _localSlots[index];

    setState(() {
      _selectedIndex = index;
      _nameController.text = med['name'].contains("Empty Slot") ? "" : med['name'];
      _pillCountController.text = med['pills'] ?? "0";
      _selectedMealCondition = med['mealCondition'] ?? "After Meal";
      _selectedFrequency = med['frequency'] ?? "Everyday";
      _currentMedTimes = List<String>.from(med['times'] ?? []);
      
      _startDate = med['startDate'] != null ? DateTime.parse(med['startDate']) : DateTime.now();
      _endDate = med['endDate'] != null ? DateTime.parse(med['endDate']) : DateTime.now().add(const Duration(days: 7));
    });
  }

  void _clearCurrentSlot() {
    setState(() {
      _nameController.clear();
      _pillCountController.text = "0";
      _selectedMealCondition = "After Meal";
      _selectedFrequency = "Everyday";
      _currentMedTimes = [];
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 7));
    });
  }

  Future<void> _saveChanges() async {
    if (_currentTargetEmail == null) return;
    
    // VALIDATION: Ensure End Date is after Start Date
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: End Date cannot be before Start Date"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    String cleanEmail = _currentTargetEmail!.trim().toLowerCase();

    String finalFrequency = _selectedFrequency == "Every X Days"
        ? "Every ${_dayIntervalController.text} Days"
        : _selectedFrequency;

    _localSlots[_selectedIndex] = {
      "slot": (_selectedIndex + 1).toString(),
      "name": _nameController.text.isEmpty ? "Empty Slot ${_selectedIndex + 1}" : _nameController.text,
      "pills": _pillCountController.text,
      "times": _currentMedTimes,
      "mealCondition": _selectedMealCondition,
      "frequency": finalFrequency,
      "startDate": DateFormat('yyyy-MM-dd').format(_startDate),
      "endDate": DateFormat('yyyy-MM-dd').format(_endDate), // SAVE END DATE
      "isDone": false,
    };

    try {
      await FirebaseFirestore.instance.collection('schedules').doc(cleanEmail).set({
        "lastUpdated": FieldValue.serverTimestamp(),
        "updatedBy": widget.userEmail,
        "slots": _localSlots,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cloud Sync Complete. Hardware Updated."), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      debugPrint("Save error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // DATE PICKERS
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)), 
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          // Auto-adjust end date if it becomes invalid
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _addTimeSlot() {
    String period = _pickerTime.hour >= 12 ? "PM" : "AM";
    int hour = _pickerTime.hour > 12 ? _pickerTime.hour - 12 : (_pickerTime.hour == 0 ? 12 : _pickerTime.hour);
    String formatted = "$hour:${_pickerTime.minute.toString().padLeft(2, '0')} $period";

    if (!_currentMedTimes.contains(formatted)) {
      setState(() {
        _currentMedTimes.add(formatted);
        _currentMedTimes.sort();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text("Dispenser Configurator", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, centerTitle: true, elevation: 0.5,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getLinkedPatientsStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState();

          var patients = snapshot.data!.docs;
          
          if (_currentTargetEmail == null && patients.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_currentTargetEmail == null) {
                String firstEmail = patients.first.get('patientEmail');
                setState(() => _currentTargetEmail = firstEmail);
                _loadPatientSchedule(firstEmail);
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          return _isLoading 
            ? const Center(child: CircularProgressIndicator()) 
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("1. Select Patient", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                    const SizedBox(height: 10),
                    _buildPatientDropdown(patients),

                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("2. Physical Slot (1-5)", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                        TextButton.icon(onPressed: _clearCurrentSlot, icon: const Icon(Icons.refresh, size: 16, color: Colors.red), label: const Text("Clear Slot", style: TextStyle(color: Colors.red, fontSize: 12))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildSlotTabs(),

                    const SizedBox(height: 25),
                    _buildInputField("Medicine Name", _nameController, Icons.medication),
                    const SizedBox(height: 15),
                    _buildInputField("Pills per dispensing", _pillCountController, Icons.pin, isNum: true),

                    // --- DURATION SECTION ---
                    const SizedBox(height: 25),
                    const Text("Prescription Duration:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildDateTile("Start Date", _startDate, () => _selectDate(context, true))),
                        const SizedBox(width: 10),
                        Expanded(child: _buildDateTile("Repeat Until", _endDate, () => _selectDate(context, false))),
                      ],
                    ),

                    const SizedBox(height: 25),
                    const Text("Meal Instruction", style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(children: [_mealRadio("Before Meal"), _mealRadio("After Meal")]),

                    const SizedBox(height: 25),
                    const Text("Repeat Frequency", style: TextStyle(fontWeight: FontWeight.bold)),
                    _buildFrequencyDropdown(),
                    if (_selectedFrequency == "Every X Days") 
                      Padding(padding: const EdgeInsets.only(top: 10), child: _buildInputField("Interval (Days)", _dayIntervalController, Icons.calendar_today, isNum: true)),

                    const SizedBox(height: 25),
                    const Text("Dispense Timings", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildTimeChips(),
                    _buildTimePickerSection(),

                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity, height: 55,
                      child: ElevatedButton(
                        onPressed: _saveChanges,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: Text("Sync Slot ${_selectedIndex + 1} to Cloud", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
        },
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 1, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildDateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Row(children: [
              const Icon(Icons.calendar_today, size: 14, color: Color(0xFF1A3B70)),
              const SizedBox(width: 8),
              Text(DateFormat('MMM d, yyyy').format(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientDropdown(List<DocumentSnapshot> patients) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          // CRITICAL: Type must match the items
          value: _currentTargetEmail, 
          isExpanded: true,
          hint: const Text("Select a patient"),
          items: patients.map((p) {
            // Cast the value explicitly to String
            String email = p.get('patientEmail').toString(); 
            return DropdownMenuItem<String>(
              value: email, 
              child: Text(email, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (val) { 
            setState(() => _currentTargetEmail = val);
            if (val != null) _loadPatientSchedule(val);
          },
        ),
      ),
    );
  }

  Widget _buildSlotTabs() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(5, (index) {
        bool isSelected = _selectedIndex == index;
        return GestureDetector(
          onTap: () => _loadSlotIntoForm(index),
          child: Container(
            width: 60, height: 50,
            decoration: BoxDecoration(color: isSelected ? const Color(0xFF1A3B70) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1A3B70))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Slot", style: TextStyle(color: isSelected ? Colors.white70 : Colors.grey, fontSize: 10)),
              Text("${index + 1}", style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF1A3B70), fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
        );
      }),
    );
  }

  Widget _buildTimeChips() {
    return Wrap(spacing: 8, children: _currentMedTimes.map((time) => Chip(label: Text(time), deleteIcon: const Icon(Icons.cancel, size: 16), onDeleted: () => setState(() => _currentMedTimes.remove(time)), backgroundColor: Colors.blue.withOpacity(0.1))).toList());
  }

  Widget _buildTimePickerSection() {
    return Row(children: [
      Expanded(child: SizedBox(height: 100, child: CupertinoDatePicker(mode: CupertinoDatePickerMode.time, onDateTimeChanged: (t) => _pickerTime = t))),
      IconButton.filled(onPressed: _addTimeSlot, icon: const Icon(Icons.add_alarm)),
    ]);
  }

  Widget _buildFrequencyDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: DropdownButton<String>(
        value: _selectedFrequency.contains("Every") && !_selectedFrequency.startsWith("Everyday") ? "Every X Days" : _selectedFrequency,
        isExpanded: true, underline: const SizedBox(),
        items: ["Everyday", "No Repeat", "Every X Days"].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _selectedFrequency = v!),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon, {bool isNum = false}) {
    return TextField(controller: controller, keyboardType: isNum ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white));
  }

  Widget _mealRadio(String val) {
    return Expanded(child: RadioListTile(title: Text(val, style: const TextStyle(fontSize: 12)), value: val, groupValue: _selectedMealCondition, onChanged: (v) => setState(() => _selectedMealCondition = v!)));
  }

  Widget _buildEmptyState() {
    return const Center(child: Text("No linked patients found. Link a patient first."));
  }
}