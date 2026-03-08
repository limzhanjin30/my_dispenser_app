import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- ADDED FIRESTORE IMPORT ---
import 'healthcare_dashboard.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'healthcare_accept.dart';
import 'healthcare_linked.dart';
import 'healthcare_request.dart';

class HealthcareSetting extends StatefulWidget {
  final String userEmail;
  const HealthcareSetting({super.key, required this.userEmail});

  @override
  State<HealthcareSetting> createState() => _HealthcareSettingState();
}

class _HealthcareSettingState extends State<HealthcareSetting> {
  String fullName = "Healthcare Provider"; // --- ADDED STATE VARIABLE ---
  bool missedDoseNotifications = true;
  bool criticalAlertNotify = true;
  bool renewalNotify = true;

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
          fullName =
              userSnapshot.docs.first.get('name') ?? "Healthcare Provider";
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
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A3B70)),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    HealthcareDashboard(userEmail: widget.userEmail),
              ),
            );
          },
        ),
        automaticallyImplyLeading: false,
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Color(0xFF1A3B70),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
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
                      color: Colors.purple,
                    ), // Purple icon!
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

            // --- PATIENT MANAGEMENT ---
            _buildSectionHeader("Patient Management"),

            _buildSettingTile(
              Icons.assignment_ind_outlined,
              "Linked Patients",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        HealthcareLinked(userEmail: widget.userEmail),
                  ),
                );
              },
            ),

            _buildSettingTile(
              Icons.notification_important_outlined,
              "Incoming Access Requests",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        HealthcareAccept(userEmail: widget.userEmail),
                  ),
                );
              },
            ),

            _buildSettingTile(
              Icons.search,
              "Send Request To Access Patient",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        HealthcareRequest(userEmail: widget.userEmail),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // --- CLINICAL ALERTS ---
            _buildSectionHeader("Clinical Alerts"),
            _buildSwitchTile(
              Icons.warning_amber_rounded,
              "Critical Non-Adherence Alerts",
              criticalAlertNotify,
              (val) {
                setState(() => criticalAlertNotify = val);
              },
            ),
            _buildSwitchTile(
              Icons.history_edu,
              "Prescription Renewal Reminders",
              renewalNotify,
              (val) {
                setState(() => renewalNotify = val);
              },
            ),
            const SizedBox(height: 20),

            // --- PROFESSIONAL INFO ---
            _buildSectionHeader("Clinic/Hospital Information"),
            _buildSettingTile(
              Icons.local_hospital_outlined,
              "Clinic Profile & Location",
            ),
            _buildSettingTile(
              Icons.verified_user_outlined,
              "Medical Registration Details",
            ),
            const SizedBox(height: 20),

            // --- ACCOUNT & SECURITY ---
            _buildSectionHeader("Account Security"),
            _buildSettingTile(
              Icons.lock_person_outlined,
              "Change Password & 2FA",
            ),
            const SizedBox(height: 20),

            // --- SUPPORT ---
            _buildSectionHeader("System Support"),
            _buildSettingTile(
              Icons.bug_report_outlined,
              "Report Technical Issue",
            ),
            _buildSettingTile(Icons.help_outline, "Provider Documentation"),
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

      // --- BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        role: "Healthcare\nProvider",
        userEmail: widget
            .userEmail, // FIXED: Now passes the actual email instead of ""
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(color: Colors.white),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A3B70)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  // --- HELPER FOR TOGGLE SWITCHES ---
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
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
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
