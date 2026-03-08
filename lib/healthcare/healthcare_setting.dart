import 'package:flutter/material.dart';
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
  bool missedDoseNotifications = true;
  bool criticalAlertNotify = true; // Add this line
  bool renewalNotify = true;       // Add this line

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
              // Restore the leading property to add the back button
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF1A3B70)),
                onPressed: () {
                  // Navigates specifically back to the Healthcare Dashboard
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => HealthcareDashboard(userEmail: widget.userEmail)),
                  );
                },
              ),
              automaticallyImplyLeading: false, // Prevents Flutter from adding a duplicate back button
              title: const Text(
                "Settings",
                style: TextStyle(color: Color(0xFF1A3B70), fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.white,
              elevation: 0.5,
              centerTitle: true,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // --- PATIENT MANAGEMENT ---
            _buildSectionHeader("Patient Management"),

            _buildSettingTile(Icons.assignment_ind_outlined, "Linked Patients", onTap: () {
              // Navigates to the list of patients under this provider's care
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => HealthcareLinked(userEmail: widget.userEmail)
              ));
            }),

            _buildSettingTile(Icons.notification_important_outlined, "Incoming Access Requests", onTap: () {
              // Navigates to the screen where doctors approve patient link requests
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => HealthcareAccept(userEmail: widget.userEmail)
              ));
            }),

            _buildSettingTile(Icons.search, "Send Request To Access Patient", onTap: () {
              // Navigates to the screen where doctors search for patients by email
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => HealthcareRequest(userEmail: widget.userEmail)
              ));
            }),
            const SizedBox(height: 20),

            // --- CLINICAL ALERTS ---
            _buildSectionHeader("Clinical Alerts"),
            _buildSwitchTile(Icons.warning_amber_rounded, "Critical Non-Adherence Alerts", criticalAlertNotify, (val) {
              setState(() => criticalAlertNotify = val);
            }),
            _buildSwitchTile(Icons.history_edu, "Prescription Renewal Reminders", renewalNotify, (val) {
              setState(() => renewalNotify = val);
            }),
            const SizedBox(height: 20),

            // --- PROFESSIONAL INFO ---
            _buildSectionHeader("Clinic/Hospital Information"),
            _buildSettingTile(Icons.local_hospital_outlined, "Clinic Profile & Location"),
            _buildSettingTile(Icons.verified_user_outlined, "Medical Registration Details"),
            const SizedBox(height: 20),

            // --- ACCOUNT & SECURITY ---
            _buildSectionHeader("Account Security"),
            _buildSettingTile(Icons.lock_person_outlined, "Change Password & 2FA"),
            const SizedBox(height: 20),

            // --- SUPPORT ---
            _buildSectionHeader("System Support"),
            _buildSettingTile(Icons.bug_report_outlined, "Report Technical Issue"),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Log Out", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      
      // --- BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        role: "Healthcare\nProvider",
        userEmail: "", // Provider might not need email passing for now
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
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2), // Adds a small gap between tiles
      decoration: const BoxDecoration(color: Colors.white),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A3B70)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap, // Correctly applies the navigation function
      ),
    );
  }

  // --- HELPER FOR TOGGLE SWITCHES ---
  Widget _buildSwitchTile(IconData icon, String title, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: const BoxDecoration(color: Colors.white),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF1A3B70)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: Colors.green, // Standard color for active health alerts
        ),
      ),
    );
  }
}