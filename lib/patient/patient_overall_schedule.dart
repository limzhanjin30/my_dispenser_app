import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PatientOverallSchedule extends StatelessWidget {
  final String userEmail;
  const PatientOverallSchedule({super.key, required this.userEmail});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text("Full Prescription List", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('schedules').doc(userEmail.trim().toLowerCase()).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text("No prescriptions found."));

          var data = snapshot.data!.data() as Map<String, dynamic>;
          List<dynamic> allSlots = data['slots'] ?? [];
          
          List<dynamic> activeMeds = allSlots.where((slot) => 
            slot['name'] != null && !slot['name'].toString().contains("Empty Slot")).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: activeMeds.length,
            itemBuilder: (context, index) {
              final med = activeMeds[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(med['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text("Slot ${med['slot']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                          )
                        ],
                      ),
                      const SizedBox(height: 10),
                      _infoRow(Icons.repeat, "Frequency: ${med['frequency']}"),
                      _infoRow(Icons.date_range, "Duration: ${med['startDate']} to ${med['endDate']}"),
                      _infoRow(Icons.access_time, "Timings: ${med['times'].join(', ')}"),
                      _infoRow(Icons.restaurant, "Instructions: ${med['mealCondition']}"),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}