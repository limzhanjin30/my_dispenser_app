import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- ADDED FIRESTORE IMPORT ---
import '../custom_bottom_nav.dart';
import '../login.dart';
// Note: You can now safely remove the user_model.dart import if you are fully on Firebase!

class CaregiverDashboard extends StatefulWidget {
  final String userEmail;
  const CaregiverDashboard({super.key, required this.userEmail});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  String fullName = "Caregiver";
  int _linkedPatientCount = 0; // --- CHANGED TO A STATE VARIABLE ---

  @override
  void initState() {
    super.initState();
    _fetchFirestoreData(); // Trigger the database fetch when screen loads
  }

  // --- NEW ASYNC FIRESTORE FETCH LOGIC ---
  Future<void> _fetchFirestoreData() async {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();

    try {
      // 1. Fetch Caregiver Name
      // Look into the 'users' collection where the email matches the logged-in user
      QuerySnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        setState(() {
          fullName = userSnapshot.docs.first.get('name') ?? "Caregiver";
        });
      }

      // 2. Fetch Linked Patients Count
      // Look into the 'connections' collection and count how many times this caregiver's email appears
      QuerySnapshot connectionSnapshot = await FirebaseFirestore.instance
          .collection('connections')
          .where('caregiverEmail', isEqualTo: cleanEmail)
          .get();

      setState(() {
        _linkedPatientCount = connectionSnapshot.docs.length;
      });
    } catch (e) {
      print("Error fetching Firestore data: $e");
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
            Icon(Icons.people_alt, color: Colors.white),
            SizedBox(width: 10),
            Text(
              "Smart Med",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),

        // --- MOVED PROFILE TO ACTIONS FOR PROPER ALIGNMENT ---
        actions: [
          const Icon(Icons.notifications_none, color: Colors.white),
          const SizedBox(width: 15),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fullName, // Now pulls from Firestore!
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "Primary Caregiver",
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Caregiver Overview",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A3B70),
              ),
            ),
            const SizedBox(height: 25),

            // --- SUMMARY STATS ---
            _buildStatCard(
              "Linked Patients",
              _linkedPatientCount.toString(), // Uses the new state variable
              Icons.person_add,
              Colors.teal,
            ),
            const SizedBox(height: 15),
            _buildStatCard(
              "Missed Doses (Today)",
              "2",
              Icons.warning_amber_rounded,
              Colors.orange,
            ),

            const SizedBox(height: 35),
            const Text(
              "Recent Activity",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // --- MOCK ACTIVITY LIST ---
            _buildActivityTile(
              "John Doe took Morning Dose",
              "10 min ago",
              Icons.check_circle,
              Colors.green,
            ),
            _buildActivityTile(
              "Jane Smith missed Afternoon Dose",
              "1 hour ago",
              Icons.error,
              Colors.red,
            ),

            const SizedBox(height: 40),

            // --- ACTION BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A3B70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Manage Patient Access",
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
        currentIndex: 0,
        role: "Caregiver",
        userEmail: widget.userEmail,
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
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
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Icon(icon, color: color, size: 35),
        ],
      ),
    );
  }

  Widget _buildActivityTile(
    String msg,
    String time,
    IconData icon,
    Color iconColor,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          msg,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(time, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
