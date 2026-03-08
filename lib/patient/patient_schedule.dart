import 'package:flutter/material.dart';
import 'patient_dashboard.dart';
import '../custom_bottom_nav.dart';
import '../modals/user_modal.dart';

class PatientSchedule extends StatefulWidget {
  final String userEmail;
  const PatientSchedule({super.key, required this.userEmail});

  @override
  State<PatientSchedule> createState() => _PatientScheduleState();
}

class _PatientScheduleState extends State<PatientSchedule> {
  @override
  Widget build(BuildContext context) {
    // --- LOOKUP SPECIFIC SCHEDULE FOR THIS PATIENT ---
    final String myEmail = widget.userEmail.trim().toLowerCase();
    final List<Map<String, dynamic>> mySchedule =
        globalPatientSchedules[myEmail] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    PatientDashboard(userEmail: widget.userEmail),
              ),
            );
          },
        ),
        title: const Text(
          "My Medication Schedule",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // --- DATE SELECTOR ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {},
                ),
                const Text(
                  "Today, Feb 9, 2026",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // --- DYNAMIC PATIENT-SPECIFIC LIST ---
          Expanded(
            child: mySchedule.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: mySchedule.length,
                    itemBuilder: (context, index) {
                      final med = mySchedule[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 15),
                        child: ScheduleCard(
                          // FIXED: Passes the list of times and the frequency string
                          times: List<String>.from(med['times'] ?? ["--:--"]),
                          medName: med['name'] ?? "Unknown Med",
                          amount: med['amount'] ?? "N/A",
                          mealCondition: med['mealCondition'] ?? "Anytime",
                          frequency: med['frequency'] ?? "Everyday",
                          isDone: med['isDone'] ?? false,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1,
        role: "Patient",
        userEmail: widget.userEmail,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.medication_liquid_sharp,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 15),
          const Text(
            "No medication schedule assigned.",
            style: TextStyle(
              color: Colors.black54,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleCard extends StatelessWidget {
  final List<String> times; // Changed to List for multiple timings
  final String medName;
  final String amount;
  final String mealCondition;
  final String frequency;
  final bool isDone;

  const ScheduleCard({
    super.key,
    required this.times,
    required this.medName,
    required this.amount,
    required this.mealCondition,
    required this.frequency,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Frequency and Meal Condition Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  frequency, // "Everyday" or "Every X Days"
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: mealCondition.contains("After")
                      ? Colors.orange.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  mealCondition,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: mealCondition.contains("After")
                        ? Colors.orange[800]
                        : Colors.green[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Row 2: Medication Title and Dosage
          Text(
            medName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A3B70),
            ),
          ),
          Text(
            "Dosage: $amount",
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),

          const SizedBox(height: 15),
          const Divider(height: 1),
          const SizedBox(height: 15),

          // Row 3: Multiple Dispense Timings
          const Text(
            "Scheduled Alarms:",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: times
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDone
                          ? Colors.green[50]
                          : const Color(0xFFF5F9FF),
                      border: Border.all(
                        color: isDone
                            ? Colors.green.withOpacity(0.5)
                            : Colors.blue.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDone
                              ? Icons.check_circle
                              : Icons.access_time_filled,
                          size: 14,
                          color: isDone ? Colors.green : Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDone
                                ? Colors.green[700]
                                : const Color(0xFF1A3B70),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
