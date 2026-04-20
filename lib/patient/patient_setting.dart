import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'patient_dashboard.dart';
import 'patient_request.dart';
import 'patient_linked.dart';
import 'patient_accept.dart';
import 'patient_link_machine.dart';
import 'patient_password.dart'; // The 4-digit PIN page

class PatientSetting extends StatefulWidget {
  final String userEmail;
  const PatientSetting({super.key, required this.userEmail});

  @override
  State<PatientSetting> createState() => _PatientSettingState();
}

class _PatientSettingState extends State<PatientSetting> {
  String fullName = "Patient";
  String? linkedMachineId; 
  bool _isLoading = true;

  bool medReminders = true;
  bool refillAlerts = true;
  bool missedDoseNotify = true;
  bool largeTextMode = false;
  bool highContrast = false;

  @override
  void initState() {
    super.initState();
    _fetchFirestoreData();
  }

  Future<void> _fetchFirestoreData() async {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();
    try {
      var userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            var data = userSnapshot.docs.first.data();
            fullName = data['name'] ?? "Patient";
            linkedMachineId = data['linkedMachineId']; 
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching settings data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper for dummy actions
  void _showDummyMessage(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$feature feature will be available in the next update."),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 2),
      ),
    );
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
              MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail)),
            );
          },
        ),
        title: const Text("Settings", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
          : SingleChildScrollView(
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
                  Text(fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(widget.userEmail, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- ACCOUNT & SECURITY ---
            _buildSection("Account & Security", Icons.shield_outlined, [
              _buildListTile("Edit Profile", onTap: () => _showDummyMessage("Edit Profile")),
              
              // 1. DUMMY CHANGE PASSWORD TILE
              _buildListTile(
                "Change Account Password", 
                onTap: () => _showDummyMessage("Change Password"),
              ),

              // 2. FUNCTIONAL DISPENSER PIN TILE
              _buildListTile(
                "Dispenser Security PIN", 
                trailingText: "4-Digits",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PatientPassword(userEmail: widget.userEmail)
                    ),
                  );
                },
              ),
            ]),

            // --- CAREGIVER CONNECTIONS ---
            _buildSection("Caregiver Connections", Icons.people_alt_outlined, [
              _buildListTile("Linked Caregivers/Healthcare Provider", onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PatientLinked(userEmail: widget.userEmail)));
              }),
              _buildListTile("Pending Requests", onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PatientAccept(userEmail: widget.userEmail)));
              }),
              _buildListTile("Connect New Caregiver/Healthcare Provider", onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PatientRequest(userEmail: widget.userEmail)));
              }),
            ]),

            // --- HARDWARE SETTINGS ---
            _buildSection("Hardware Settings", Icons.settings_outlined, [
              _buildListTile(
                "Medicine Dispenser Hardware",
                trailingText: linkedMachineId != null ? "Linked ($linkedMachineId)" : "Not Connected",
                dotColor: linkedMachineId != null ? Colors.green : Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => PatientLinkMachine(userEmail: widget.userEmail)),
                  );
                },
              ),
              _buildListTile("Configure Wi-Fi", onTap: () => _showDummyMessage("Wi-Fi Configuration")),
              _buildListTile("Device Calibration", onTap: () => _showDummyMessage("Calibration")),
            ]),

            // --- NOTIFICATIONS ---
            _buildSection("Notifications & Alerts", Icons.notifications_none, [
              _buildSwitchTile("Medication Reminders", medReminders, (v) => setState(() => medReminders = v)),
              _buildSwitchTile("Missed Dose Alerts", missedDoseNotify, (v) => setState(() => missedDoseNotify = v)),
            ]),

            // --- LOGOUT ---
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[400], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text("Log Out", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 15, top: 15, right: 15),
          child: Row(children: [
            Icon(icon, color: const Color(0xFF1A3B70), size: 22),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
          ]),
        ),
        ...children,
        const SizedBox(height: 5),
      ]),
    );
  }

  Widget _buildListTile(String title, {String? trailingText, Color? dotColor, VoidCallback? onTap}) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(trailingText, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(width: 5),
            if (dotColor != null) Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          ],
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return ListTile(
      dense: true,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: Colors.green,
      ),
    );
  }
}