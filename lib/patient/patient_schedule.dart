import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'patient_dashboard.dart';
import 'patient_overall_schedule.dart'; 
import '../custom_bottom_nav.dart';

class PatientSchedule extends StatefulWidget {
  final String userEmail;
  final DateTime? initialDate; 

  const PatientSchedule({super.key, required this.userEmail, this.initialDate});

  @override
  State<PatientSchedule> createState() => _PatientScheduleState();
}

class _PatientScheduleState extends State<PatientSchedule> {
  late DateTime _selectedDate;
  String? _linkedMachineId;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _fetchMachineId();
  }

  // --- DATABASE: LOOKUP ---
  Future<void> _fetchMachineId() async {
    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching machine ID: $e");
      setState(() => _isInitializing = false);
    }
  }

  // --- LOGIC: DATE VALIDATION ---
  bool _isMedActiveOnDate(Map<String, dynamic> med, DateTime date) {
    if (med['startDate'] == null || med['endDate'] == null || med['startDate'] == "") return false;

    DateTime start = DateTime.parse(med['startDate']);
    DateTime end = DateTime.parse(med['endDate']);
    
    DateTime checkDate = DateTime(date.year, date.month, date.day);
    DateTime startDate = DateTime(start.year, start.month, start.day);
    DateTime endDate = DateTime(end.year, end.month, end.day);

    // If the course is finished, we still show it on the schedule if the date is within range
    if (checkDate.isBefore(startDate) || checkDate.isAfter(endDate)) return false;

    String freq = med['frequency'] ?? "Everyday";
    if (freq == "Everyday") return true;
    
    // Interval logic if needed for Every X Days
    if (freq.contains("Every") && freq.contains("Days")) {
      try {
        int days = int.parse(freq.split(' ')[1]);
        int difference = checkDate.difference(startDate).inDays;
        return difference % days == 0;
      } catch (e) { return true; }
    }
    return true;
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail))),
        ),
        title: const Text("Daily Medication", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined, color: Color(0xFF1A3B70)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PatientOverallSchedule(userEmail: widget.userEmail))),
          ),
        ],
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: _isInitializing 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
          : Column(
        children: [
          // --- DATE SELECTOR ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeDate(-1)),
                Column(
                  children: [
                    Text(DateFormat('EEEE').format(_selectedDate).toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
                    Text(DateFormat('MMM d, yyyy').format(_selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeDate(1)),
              ],
            ),
          ),

          // --- REAL-TIME SCHEDULE LIST ---
          Expanded(
            child: _linkedMachineId == null 
              ? _buildEmptyState("Please link your machine in settings.")
              : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("No machine data found.");
                
                var data = snapshot.data!.data() as Map<String, dynamic>;
                List<dynamic> allSlots = data['slots'] ?? [];

                // FILTER: Include "Occupied" (Active) AND "Finished" (Completed)
                List<dynamic> myMedsToday = allSlots.where((slot) {
                  bool belongsToMe = slot['patientEmail'] == widget.userEmail.trim().toLowerCase();
                  String status = slot['status'] ?? "";
                  bool isValidStatus = (status == "Occupied" || status == "Finished");
                  return belongsToMe && isValidStatus && _isMedActiveOnDate(Map<String, dynamic>.from(slot), _selectedDate);
                }).toList();

                if (myMedsToday.isEmpty) return _buildEmptyState("No medication scheduled for this date.");

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: myMedsToday.length,
                  itemBuilder: (context, index) {
                    final med = myMedsToday[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: ScheduleCard(
                        slotNumber: med['slot'].toString(),
                        times: List<String>.from(med['times'] ?? []),
                        medDetails: med['medDetails'] ?? "Medication",
                        mealCondition: med['mealCondition'] ?? "Anytime",
                        isDone: med['isDone'] ?? false,
                        status: med['status'] ?? "Occupied", // Pass status to UI
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
    return Center(child: Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.event_note, size: 60, color: Colors.blue.withOpacity(0.1)),
        const SizedBox(height: 15),
        Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
    ));
  }
}

class ScheduleCard extends StatelessWidget {
  final String slotNumber;
  final List<String> times;
  final String medDetails;
  final String mealCondition;
  final bool isDone;
  final String status;

  const ScheduleCard({
    super.key, 
    required this.slotNumber, 
    required this.times, 
    required this.medDetails, 
    required this.mealCondition, 
    required this.isDone,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    bool isFinished = status == "Finished";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isFinished ? const Color(0xFFF0F7FF) : Colors.white, // Light blue tint for finished
        borderRadius: BorderRadius.circular(15), 
        border: isFinished ? Border.all(color: Colors.blue.shade100) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFinished ? Colors.blue.shade100 : const Color(0xFF1A3B70).withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Text(
                  isFinished ? "COURSE COMPLETED" : "BIN SLOT $slotNumber", 
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isFinished ? Colors.blue.shade800 : const Color(0xFF1A3B70))
                ),
              ),
              Icon(
                isDone || isFinished ? Icons.check_circle : Icons.radio_button_unchecked, 
                color: isDone || isFinished ? Colors.green : Colors.grey.shade300
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            medDetails, 
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: isFinished ? Colors.blueGrey : const Color(0xFF1A3B70),
              decoration: isFinished ? TextDecoration.none : null,
            )
          ),
          const SizedBox(height: 5),
          Text(mealCondition, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isFinished ? Colors.grey : Colors.orange[800])),
          const Divider(height: 30),
          const Text("SCHEDULED TIMES:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: times.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isFinished ? Colors.white : const Color(0xFFF5F9FF), 
                borderRadius: BorderRadius.circular(10), 
                border: Border.all(color: isFinished ? Colors.blue.shade50 : Colors.blue.withOpacity(0.2))
              ),
              child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isFinished ? Colors.blueGrey : const Color(0xFF1A3B70))),
            )).toList(),
          )
        ],
      ),
    );
  }
}