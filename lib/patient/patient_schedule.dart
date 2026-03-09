import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'patient_dashboard.dart';
import 'patient_overall_schedule.dart'; // NEW PAGE IMPORT
import '../custom_bottom_nav.dart';

class PatientSchedule extends StatefulWidget {
  final String userEmail;
  const PatientSchedule({super.key, required this.userEmail});

  @override
  State<PatientSchedule> createState() => _PatientScheduleState();
}

class _PatientScheduleState extends State<PatientSchedule> {
  DateTime _selectedDate = DateTime.now(); // Default to today

  // --- LOGIC: SHOULD MEDICINE BE TAKEN ON THIS SPECIFIC DATE? ---
  bool _isMedActiveOnDate(Map<String, dynamic> med, DateTime date) {
    if (med['startDate'] == null || med['endDate'] == null) return false;

    DateTime start = DateTime.parse(med['startDate']);
    DateTime end = DateTime.parse(med['endDate']);
    
    // Normalize dates to midnight for accurate comparison
    DateTime checkDate = DateTime(date.year, date.month, date.day);
    DateTime startDate = DateTime(start.year, start.month, start.day);
    DateTime endDate = DateTime(end.year, end.month, end.day);

    // 1. Check if the date is within the range
    if (checkDate.isBefore(startDate) || checkDate.isAfter(endDate)) return false;

    // 2. Check Frequency
    String freq = med['frequency'] ?? "Everyday";
    if (freq == "Everyday") return true;
    if (freq == "No Repeat") return checkDate.isAtSameMomentAs(startDate);

    if (freq.contains("Every") && freq.contains("Days")) {
      // Extract number X from "Every X Days"
      int days = int.tryParse(freq.split(' ')[1]) ?? 1;
      int difference = checkDate.difference(startDate).inDays;
      return difference % days == 0;
    }

    return true;
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail))),
        ),
        title: const Text("Daily Schedule", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined, color: Color(0xFF1A3B70)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PatientOverallSchedule(userEmail: widget.userEmail))),
            tooltip: "View Overall Prescriptions",
          ),
        ],
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- DATE SELECTOR ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeDate(-1)),
                GestureDetector(
                  onTap: _pickDate,
                  child: Column(
                    children: [
                      Text(DateFormat('EEEE').format(_selectedDate), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      Text(DateFormat('MMM d, yyyy').format(_selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeDate(1)),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('schedules').doc(cleanEmail).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("No data found.");
                
                var data = snapshot.data!.data() as Map<String, dynamic>;
                List<dynamic> allSlots = data['slots'] ?? [];

                // Filter for current date + non-empty slots
                List<dynamic> activeMeds = allSlots.where((slot) {
                  bool notEmpty = slot['name'] != null && !slot['name'].toString().contains("Empty Slot");
                  return notEmpty && _isMedActiveOnDate(Map<String, dynamic>.from(slot), _selectedDate);
                }).toList();

                if (activeMeds.isEmpty) return _buildEmptyState("No medications for this date.");

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: activeMeds.length,
                  itemBuilder: (context, index) {
                    final med = activeMeds[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: ScheduleCard(
                        slotNumber: med['slot'],
                        times: List<String>.from(med['times'] ?? []),
                        medName: med['name'],
                        pillCount: med['pills'],
                        mealCondition: med['mealCondition'],
                        isDone: med['isDone'] ?? false,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 1, role: "Patient", userEmail: widget.userEmail),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.event_available, size: 60, color: Colors.grey),
      const SizedBox(height: 10),
      Text(msg, style: const TextStyle(color: Colors.grey)),
    ]));
  }
}

// --- SIMPLIFIED CARD FOR DAILY VIEW ---
class ScheduleCard extends StatelessWidget {
  final String slotNumber;
  final List<String> times;
  final String medName;
  final String pillCount;
  final String mealCondition;
  final bool isDone;

  const ScheduleCard({super.key, required this.slotNumber, required this.times, required this.medName, required this.pillCount, required this.mealCondition, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(medName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
              Icon(isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: isDone ? Colors.green : Colors.grey),
            ],
          ),
          const SizedBox(height: 5),
          Text("Take $pillCount Pill(s) • $mealCondition", style: const TextStyle(color: Colors.black54)),
          const Divider(),
          Wrap(
            spacing: 8,
            children: times.map((t) => Chip(
              label: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFFF5F9FF),
            )).toList(),
          )
        ],
      ),
    );
  }
}