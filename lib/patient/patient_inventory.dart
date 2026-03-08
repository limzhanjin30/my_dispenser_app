import 'package:flutter/material.dart';
import '../custom_bottom_nav.dart';
import 'patient_dashboard.dart';

class PatientInventory extends StatefulWidget {
  // Pass the email to maintain the user session
  final String userEmail;

  const PatientInventory({super.key, required this.userEmail});

  @override
  State<PatientInventory> createState() => _PatientInventoryState();
}

class _PatientInventoryState extends State<PatientInventory> {
  // Simulating real-time data for your Smart Medicine Dispenser
  static List<Map<String, dynamic>> patientMeds = [
    {"name": "Aspirin, 100mg", "count": 20, "max": 30, "color": Colors.green},
    {"name": "Vitamin D, 1000IU", "count": 6, "max": 30, "color": Colors.orange},
    {"name": "Metformin, 500mg", "count": 1, "max": 30, "color": Colors.red},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () {
            // Navigates back to the personalized Dashboard
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail))
            );
          },
        ),
        title: const Text("Medication Inventory", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: patientMeds.length,
        itemBuilder: (context, index) {
          var med = patientMeds[index];
          double percentage = med['count'] / med['max'];
          String status = percentage > 0.5 ? "Good" : (percentage > 0.1 ? "Refill Soon" : "LOW");

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: InventoryCard(
              medName: med['name'],
              pillCount: "${med['count']}/${med['max']} pills left",
              status: status,
              percentage: percentage,
              statusColor: med['color'],
              showAlert: percentage <= 0.1,
            ),
          );
        },
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 2,
        role: "Patient",
        userEmail: widget.userEmail,
      ),
    );
  }
}

class InventoryCard extends StatelessWidget {
  final String medName;
  final String pillCount;
  final String status;
  final double percentage;
  final Color statusColor;
  final bool showAlert;

  const InventoryCard({
    super.key,
    required this.medName,
    required this.pillCount,
    required this.status,
    required this.percentage,
    required this.statusColor,
    this.showAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(medName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Row(
              children: [
                if (showAlert) const Icon(Icons.warning, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text(
                  "$pillCount - $status",
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 12,
            backgroundColor: Colors.grey[200],
            color: statusColor,
          ),
        ),
        const SizedBox(height: 5),
        Text("${(percentage * 100).toInt()}%", style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}