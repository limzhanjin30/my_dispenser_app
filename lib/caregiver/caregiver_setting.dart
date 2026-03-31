import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- ADDED FIRESTORE IMPORT ---
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'caregiver_dashboard.dart';
import 'caregiver_accept.dart';
import 'caregiver_linked.dart';
import 'caregiver_request.dart';

class CaregiverSetting extends StatefulWidget {
  final String userEmail;
  const CaregiverSetting({super.key, required this.userEmail});

  @override
  State<CaregiverSetting> createState() => _CaregiverSettingState();
}

class _CaregiverSettingState extends State<CaregiverSetting> {
  String fullName = "Caregiver"; // --- ADDED STATE VARIABLE ---
  bool missedDoseNotify = true;
  bool lowInventoryAlert = true;

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
          fullName = userSnapshot.docs.first.get('name') ?? "Caregiver";
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
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CaregiverDashboard(userEmail: widget.userEmail),
              ),
            );
          },
        ),
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // --- NEW PROFILE HEADER ---
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Color(0xFFE0E0E0),
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.teal,
                    ), // Green icon!
                  ),
                  const SizedBox(height: 10),
                  Text(
                    fullName, // --- PULLS DYNAMICALLY FROM FIRESTORE ---
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.userEmail,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // --- PATIENT CONNECTIONS ---
            _buildSectionHeader("Patient Connections"),

            _buildSettingTile(
              Icons.people_outline,
              "Linked Patients",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CaregiverLinked(userEmail: widget.userEmail),
                  ),
                );
              },
            ),

            _buildSettingTile(
              Icons.person_add,
              "Incoming Access Request",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CaregiverAccept(userEmail: widget.userEmail),
                  ),
                );
              },
            ),

            _buildSettingTile(
              Icons.person_add_alt,
              "Send Request To Access Patient",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CaregiverRequest(userEmail: widget.userEmail),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // --- CAREGIVER ALERTS ---
            _buildSectionHeader("Caregiver Alerts"),
            _buildSwitchTile(
              Icons.notifications_none,
              "Missed Dose Notifications",
              missedDoseNotify,
              (val) {
                setState(() => missedDoseNotify = val);
              },
            ),
            _buildSwitchTile(
              Icons.medication_liquid,
              "Low Inventory Alerts",
              lowInventoryAlert,
              (val) {
                setState(() => lowInventoryAlert = val);
              },
            ),
            const SizedBox(height: 20),

            // --- ACCOUNT ---
            _buildSectionHeader("Account"),
            _buildSettingTile(Icons.lock_outline, "Profile & Security"),
            const SizedBox(height: 20),

            // --- APP ACTIONS ---
            _buildSectionHeader("App Actions"),
            _buildSettingTile(Icons.chat_bubble_outline, "Report an Issue"),
            _buildSettingTile(Icons.info_outline, "About App"),
            const SizedBox(height: 30),

            // --- LOGOUT BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Log Out",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 4,
        role: "Caregiver",
        userEmail: widget.userEmail,
      ),
    );
  }

  // Helper to build section headers
  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  // Helper to build standard tiles
  Widget _buildSettingTile(IconData icon, String title, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(color: Colors.white),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A3B70)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  // Helper to build switch tiles
  Widget _buildSwitchTile(
    IconData icon,
    String title,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(color: Colors.white),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A3B70)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: Colors.green,
        ),
      ),
    );
  }
}
