import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- ADDED FIRESTORE IMPORT ---
import '../custom_bottom_nav.dart';
import '../login.dart';

class HealthcareDashboard extends StatefulWidget {
  final String userEmail; 
  const HealthcareDashboard({super.key, required this.userEmail});

  @override
  State<HealthcareDashboard> createState() => _HealthcareDashboardState();
}

class _HealthcareDashboardState extends State<HealthcareDashboard> {
  String fullName = "Healthcare Provider";

  @override
  void initState() {
    super.initState();
    _fetchFirestoreData(); // --- TRIGGER ASYNC FETCH ---
  }

  // --- NEW ASYNC FIRESTORE FETCH LOGIC ---
  Future<void> _fetchFirestoreData() async {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();

    try {
      // Look into the 'users' collection where the email matches the logged-in user
      QuerySnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        setState(() {
          fullName = userSnapshot.docs.first.get('name') ?? "Healthcare Provider";
        });
      }
    } catch (e) {
      print("Error fetching user data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()), 
              (route) => false,
            );
          },
        ),
        backgroundColor: const Color(0xFF1A3B70),
        elevation: 0,
        automaticallyImplyLeading: false,
        
        // --- FIXED APPBAR TITLE LAYOUT ---
        title: const Row(
          children: [
            Icon(Icons.health_and_safety, color: Colors.white),
            SizedBox(width: 10),
            Text(
              "Smart Med",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),

        // --- MOVED PROFILE TO ACTIONS FOR PROPER RIGHT-ALIGNMENT ---
        actions: [
          const Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications, color: Colors.white, size: 24),
              Positioned(
                right: 0,
                top: 12, // Adjusted slightly for visual balance
                child: CircleAvatar(radius: 5, backgroundColor: Colors.red),
              )
            ],
          ),
          const SizedBox(width: 15),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFE3F2FD), // Replaced broken NetworkImage with a solid color placeholder
            child: Icon(Icons.person, color: Color(0xFF1A3B70), size: 20),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center, // Centers the text vertically
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fullName, // --- PULLS DYNAMICALLY FROM FIRESTORE ---
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12, // Increased slightly from 10 for better readability
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 14),
            ],
          ),
          const SizedBox(width: 20), // Adds a bit of padding to the far right edge
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Healthcare Provider Main Dashboard",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A3B70),
              ),
            ),
            const SizedBox(height: 25),

            _buildStatCard("Total Patients", "150", Icons.groups, Colors.blue),
            const SizedBox(height: 15),
            _buildStatCard(
              "At-Risk Patients",
              "12",
              Icons.priority_high,
              Colors.red,
              badgeCount: "12",
            ),
            const SizedBox(height: 15),
            _buildStatCard("Avg. Adherence", "88%", Icons.donut_large, Colors.green),

            const SizedBox(height: 35),
            const Text(
              "Critical Alerts",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 15),

            _buildAlertTile(
              "John Doe - Missed 3 consecutive doses",
              Icons.error_outline,
              Colors.red,
            ),
            const SizedBox(height: 12),
            _buildAlertTile("Mary Smith - Low Battery", Icons.battery_alert, Colors.orange),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1A3B70), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "View All Patients",
                  style: TextStyle(
                    color: Color(0xFF1A3B70),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        role: "Healthcare\nProvider",
        userEmail: widget.userEmail, 
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? badgeCount}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: badgeCount != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(icon, color: color, size: 28),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 8,
                          backgroundColor: Colors.red,
                          child: Text(
                            badgeCount,
                            style: const TextStyle(color: Colors.white, fontSize: 8),
                          ),
                        ),
                      )
                    ],
                  )
                : Icon(icon, color: color, size: 28),
          )
        ],
      ),
    );
  }

  Widget _buildAlertTile(String message, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
        ],
      ),
    );
  }
}