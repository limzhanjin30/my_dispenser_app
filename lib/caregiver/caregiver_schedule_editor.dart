import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../custom_bottom_nav.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPatientSchedules, and globalConnections

class CaregiverScheduleEditor extends StatefulWidget {
  final String userEmail;
  final String? initialTargetEmail;

  const CaregiverScheduleEditor({
    super.key,
    required this.userEmail,
    this.initialTargetEmail,
  });

  @override
  State<CaregiverScheduleEditor> createState() =>
      _CaregiverScheduleEditorState();
}

class _CaregiverScheduleEditorState extends State<CaregiverScheduleEditor> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _dayIntervalController = TextEditingController(
    text: "2",
  );

  String _selectedMealCondition = "After Meal";
  String _selectedFrequency = "Everyday";
  DateTime _pickerTime = DateTime.now();

  List<String> _currentMedTimes =
      []; // Tracks multiple timings for one med slot
  int _selectedIndex = 0;
  String? _currentTargetEmail;

  @override
  void initState() {
    super.initState();
    final linked = _getLinkedPatients();
    if (widget.initialTargetEmail != null) {
      _currentTargetEmail = widget.initialTargetEmail;
    } else if (linked.isNotEmpty) {
      _currentTargetEmail = linked.first['email'];
    }

    if (_currentTargetEmail != null) {
      _initializePatientData(_currentTargetEmail!);
    }
  }

  List<Map<String, String>> _getLinkedPatients() {
    final myPatientEmails = globalConnections
        .where(
          (conn) =>
              conn['caregiverEmail']?.trim().toLowerCase() ==
              widget.userEmail.trim().toLowerCase(),
        )
        .map((conn) => conn['patientEmail']?.trim().toLowerCase())
        .toList();

    return registeredUsers
        .where(
          (user) =>
              myPatientEmails.contains(user['email']?.trim().toLowerCase()),
        )
        .map(
          (user) => {
            "name": user['name'] ?? "Unknown",
            "email": user['email'] ?? "",
          },
        )
        .toList();
  }

  void _initializePatientData(String pEmail) {
    String cleanEmail = pEmail.trim().toLowerCase();
    if (!globalPatientSchedules.containsKey(cleanEmail)) {
      globalPatientSchedules[cleanEmail] = [
        {
          "id": "1",
          "name": "New Med",
          "amount": "0mg",
          "times": ["08:00 AM"],
          "mealCondition": "After Meal",
          "frequency": "Everyday",
          "isDone": false,
        },
      ];
    }
    _loadMedicationData(0);
  }

  void _loadMedicationData(int index) {
    if (_currentTargetEmail == null) return;
    var med =
        globalPatientSchedules[_currentTargetEmail!
            .trim()
            .toLowerCase()]![index];

    setState(() {
      _selectedIndex = index;
      _nameController.text = med['name'];
      _amountController.text = med['amount'];
      _selectedMealCondition = med['mealCondition'];
      _selectedFrequency = med['frequency'] ?? "Everyday";
      // Ensure we treat 'times' as a list
      _currentMedTimes = List<String>.from(med['times'] ?? []);
    });
  }

  // --- LOGIC: ADD/REMOVE TIME SLOTS ---
  void _addTimeSlot() {
    String period = _pickerTime.hour >= 12 ? "PM" : "AM";
    int hour = _pickerTime.hour > 12
        ? _pickerTime.hour - 12
        : (_pickerTime.hour == 0 ? 12 : _pickerTime.hour);
    String formatted =
        "$hour:${_pickerTime.minute.toString().padLeft(2, '0')} $period";

    if (!_currentMedTimes.contains(formatted)) {
      setState(() {
        _currentMedTimes.add(formatted);
        _currentMedTimes.sort(); // Keep schedule in chronological order
      });
    }
  }

  void _saveChanges() {
    if (_currentTargetEmail == null) return;
    String cleanEmail = _currentTargetEmail!.trim().toLowerCase();

    String finalFrequency = _selectedFrequency == "Every X Days"
        ? "Every ${_dayIntervalController.text} Days"
        : _selectedFrequency;

    setState(() {
      globalPatientSchedules[cleanEmail]![_selectedIndex] = {
        "id": (_selectedIndex + 1).toString(),
        "name": _nameController.text,
        "amount": _amountController.text,
        "times": _currentMedTimes, // SAVING AS LIST
        "mealCondition": _selectedMealCondition,
        "frequency": finalFrequency,
        "isDone": false,
      };
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Syncing multiple timings to dispenser..."),
        backgroundColor: Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linkedPatients = _getLinkedPatients();
    final medList = _currentTargetEmail != null
        ? (globalPatientSchedules[_currentTargetEmail!.trim().toLowerCase()] ??
              [])
        : [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text(
          "Multi-Schedule Editor",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0.5,
      ),
      body: linkedPatients.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPatientSelector(linkedPatients),
                  const SizedBox(height: 25),
                  _buildSlotTabs(medList),
                  const SizedBox(height: 25),

                  _buildInputField(
                    "Medicine Name",
                    _nameController,
                    Icons.medication,
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Dosage (e.g. 500mg)",
                    _amountController,
                    Icons.scale,
                  ),

                  const SizedBox(height: 25),
                  const Text(
                    "Meal Instruction",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      _mealRadio("Before Meal"),
                      _mealRadio("After Meal"),
                    ],
                  ),

                  const SizedBox(height: 25),
                  const Text(
                    "Repeat Frequency",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  _buildFrequencyDropdown(),
                  if (_selectedFrequency == "Every X Days")
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildInputField(
                        "Interval (Days)",
                        _dayIntervalController,
                        Icons.repeat,
                        isNum: true,
                      ),
                    ),

                  const SizedBox(height: 25),
                  const Text(
                    "Dispense Timings",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildTimeChips(),
                  _buildTimePickerSection(),

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _saveChanges,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A3B70),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Update Patient Dispenser",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1,
        role: "Caregiver",
        userEmail: widget.userEmail,
      ),
    );
  }

  // --- COMPONENT WIDGETS ---

  Widget _buildPatientSelector(List<Map<String, String>> patients) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _currentTargetEmail,
          isExpanded: true,
          items: patients
              .map(
                (p) => DropdownMenuItem(
                  value: p['email'],
                  child: Text("${p['name']} (${p['email']})"),
                ),
              )
              .toList(),
          onChanged: (val) {
            setState(() {
              _currentTargetEmail = val;
              _initializePatientData(val!);
            });
          },
        ),
      ),
    );
  }

  Widget _buildSlotTabs(List medList) {
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: medList.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => _loadMedicationData(index),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: _selectedIndex == index
                  ? const Color(0xFF1A3B70)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1A3B70)),
            ),
            child: Center(
              child: Text(
                medList[index]['name'],
                style: TextStyle(
                  color: _selectedIndex == index
                      ? Colors.white
                      : const Color(0xFF1A3B70),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChips() {
    return Wrap(
      spacing: 8,
      children: _currentMedTimes
          .map(
            (time) => Chip(
              label: Text(time),
              deleteIcon: const Icon(Icons.cancel, size: 16),
              onDeleted: () => setState(() => _currentMedTimes.remove(time)),
              backgroundColor: Colors.blue.withOpacity(0.1),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTimePickerSection() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 100,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              onDateTimeChanged: (t) => _pickerTime = t,
            ),
          ),
        ),
        IconButton.filled(
          onPressed: _addTimeSlot,
          icon: const Icon(Icons.add_alarm),
        ),
      ],
    );
  }

  Widget _buildFrequencyDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButton<String>(
        value:
            _selectedFrequency.contains("Every") &&
                !_selectedFrequency.startsWith("Everyday")
            ? "Every X Days"
            : _selectedFrequency,
        isExpanded: true,
        underline: const SizedBox(),
        items: [
          "Everyday",
          "No Repeat",
          "Every X Days",
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _selectedFrequency = v!),
      ),
    );
  }

  Widget _buildInputField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isNum = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _mealRadio(String val) {
    return Expanded(
      child: RadioListTile(
        title: Text(val, style: const TextStyle(fontSize: 12)),
        value: val,
        groupValue: _selectedMealCondition,
        onChanged: (v) => setState(() => _selectedMealCondition = v!),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text("No linked patients. Use 'Home' to link profiles."),
    );
  }
}
