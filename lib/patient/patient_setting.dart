import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- ADDED FIRESTORE IMPORT ---
import '../custom_bottom_nav.dart';
import '../login.dart';
// Note: Removed user_model.dart import since we are fetching from Firebase now
import 'patient_dashboard.dart';
import 'patient_request.dart';
import 'patient_linked.dart';
import 'patient_accept.dart';

class PatientSetting extends StatefulWidget {
  final String userEmail;
  const PatientSetting({super.key, required this.userEmail});

  @override
  State<PatientSetting> createState() => _PatientSettingState();
}

class _PatientSettingState extends State<PatientSetting> {
  String fullName = "Patient";
  bool medReminders = true;
  bool refillAlerts = true;
  bool missedDoseNotify = true;
  bool largeTextMode = false;
  bool highContrast = false;

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
          fullName = userSnapshot.docs.first.get('name') ?? "Patient";
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
          icon: const Icon(Icons.arrow_back_ios, color: Colors.blue, size: 20),
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
          "Settings",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            // --- PROFILE HEADER ---
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 35,
                    backgroundColor: Color(0xFFE0E0E0),
                    child: Icon(Icons.person, size: 50, color: Colors.blue),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    fullName, // --- NOW PULLS DYNAMICALLY FROM FIRESTORE ---
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
            const SizedBox(height: 20),

            // --- ACCOUNT INFO ---
            _buildSection("Account Info", Icons.person_outline, [
              _buildListTile("Edit Profile"),
              _buildListTile("Change Password"),
              _buildListTile("Security Questions"),
            ]),

            // --- CAREGIVER CONNECTIONS ---
            _buildSection("Caregiver Connections", Icons.people_alt_outlined, [
              _buildListTile(
                "Linked Caregiver/Healthcare Provider",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PatientLinked(userEmail: widget.userEmail),
                    ),
                  );
                },
              ),
              _buildListTile(
                "Caregiver/Healthcare Provider Access Requests",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PatientAccept(userEmail: widget.userEmail),
                    ),
                  );
                },
              ),
              _buildListTile(
                "Send Request to Caregiver/Healthcare Provider",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PatientRequest(userEmail: widget.userEmail),
                    ),
                  );
                },
              ),
            ]),

            // --- DEVICE SETTINGS ---
            _buildSection(
              "Device Settings (Crucial for Smart Dispenser)",
              Icons.settings_outlined,
              [
                _buildListTile(
                  "Connect Medicine Dispenser",
                  trailingText: "Connected",
                  dotColor: Colors.green,
                ),
                _buildListTile("Configure Wi-Fi"),
                _buildListTile("Dispenser Volume"),
              ],
            ),

            // --- NOTIFICATIONS & ALERTS ---
            _buildSection("Notifications & Alerts", Icons.notifications_none, [
              _buildSwitchTile(
                "Medication Reminders",
                medReminders,
                (v) => setState(() => medReminders = v),
              ),
              _buildSwitchTile(
                "Refill Alerts",
                refillAlerts,
                (v) => setState(() => refillAlerts = v),
              ),
              _buildSwitchTile(
                "Missed Dose Notifications",
                missedDoseNotify,
                (v) => setState(() => missedDoseNotify = v),
              ),
            ]),

            // --- PRIVACY & SUPPORT ---
            _buildSection("Privacy & Support", Icons.shield_outlined, [
              _buildListTile("Privacy Policy"),
              _buildListTile("Terms of Service"),
              _buildListTile("Contact Support"),
            ]),

            // --- DISPLAY & ACCESSIBILITY ---
            _buildSection("Display & Accessibility", Icons.text_fields, [
              _buildSwitchTile(
                "Large Text Mode",
                largeTextMode,
                (v) => setState(() => largeTextMode = v),
              ),
              _buildSwitchTile(
                "High Contrast",
                highContrast,
                (v) => setState(() => highContrast = v),
              ),
            ]),

            const SizedBox(height: 15),

            // --- LOGOUT ---
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
            const SizedBox(height: 30),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        role: "Patient",
        userEmail: widget.userEmail,
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
          Padding(
            padding: const EdgeInsets.only(left: 15, top: 15, right: 15),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF1A3B70), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  Widget _buildListTile(
    String title, {
    String? trailingText,
    Color? dotColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(width: 5),
            if (dotColor != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: Colors.green,
      ),
    );
  }
}
