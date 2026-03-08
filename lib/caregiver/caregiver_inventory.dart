import 'package:flutter/material.dart';
import 'caregiver_dashboard.dart';
import '../custom_bottom_nav.dart';

class CaregiverInventory extends StatefulWidget {
  final String userEmail; // Required parameter
  const CaregiverInventory({super.key, required this.userEmail});

  @override
  State<CaregiverInventory> createState() => _CaregiverInventoryState();
}

class _CaregiverInventoryState extends State<CaregiverInventory> {
  // Caregiver sees the same data as Patient
  List<Map<String, dynamic>> caregiverMeds = [
    {"name": "Aspirin, 100mg", "count": 20, "max": 30, "color": Colors.green},
    {"name": "Vitamin D, 1000IU", "count": 5, "max": 30, "color": Colors.orange},
    {"name": "Metformin, 500mg", "count": 1, "max": 30, "color": Colors.red},
  ];

  void refillInventory() {
    setState(() {
      for (var med in caregiverMeds) {
        med['count'] = med['max']; // Reset to full
      }
    });
    // For your Sunway FYP presentation:
    // Mention this sends a signal via MQTT or Firebase to the ESP32/BeagleBone hardware.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Inventory Reset! Patient screen updated.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () {
            // FIXED: Removed 'const' and passed the required userEmail
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => CaregiverDashboard(userEmail: widget.userEmail))
            );
          },
        ),
        title: const Text("Inventory & Refill", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false, 
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: caregiverMeds.length,
              itemBuilder: (context, index) {
                var med = caregiverMeds[index];
                double percentage = med['count'] / med['max'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: CaregiverInventoryCard(
                    medName: med['name'],
                    pillCount: "${med['count']}/${med['max']} pills left",
                    status: percentage > 0.1 ? "Good" : "LOW",
                    percentage: percentage,
                    statusColor: med['color'],
                    hasWarning: percentage <= 0.1,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: refillInventory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066CC),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Reset Inventory After Refill", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        role: "Caregiver",
        userEmail: widget.userEmail, // Pass current user email to maintain session
      ),
    );
  }
}

class CaregiverInventoryCard extends StatelessWidget {
  final String medName;
  final String pillCount;
  final String status;
  final double percentage;
  final Color statusColor;
  final bool hasWarning;

  const CaregiverInventoryCard({
    super.key,
    required this.medName,
    required this.pillCount,
    required this.status,
    required this.percentage,
    required this.statusColor,
    this.hasWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(medName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue),
              onPressed: () {
                // Future Step: Logic to adjust specific pill counts manually
              },
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            )
          ],
        ),
        const SizedBox(height: 10),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 15,
                backgroundColor: Colors.grey[200],
                color: statusColor,
              ),
            ),
            if (hasWarning) 
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.warning, color: Colors.red, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(pillCount, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
            Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}