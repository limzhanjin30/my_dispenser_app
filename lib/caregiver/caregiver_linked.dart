import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPendingRequests, and globalConnections
import 'caregiver_schedule_editor.dart'; // Ensure this import is present

class CaregiverLinked extends StatefulWidget {
  final String userEmail; 
  const CaregiverLinked({super.key, required this.userEmail});

  @override
  State<CaregiverLinked> createState() => _CaregiverLinkedState();
}

class _CaregiverLinkedState extends State<CaregiverLinked> {
  
  List<Map<String, String>> get connectedProfiles {
    final myPatientEmails = globalConnections
        .where((conn) => 
            conn['caregiverEmail']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase())
        .map((conn) => conn['patientEmail']?.trim().toLowerCase())
        .toList();

    return registeredUsers
        .where((user) => 
            myPatientEmails.contains(user['email']?.trim().toLowerCase()))
        .map((user) => {
              "name": user['name'] ?? "Unknown User",
              "role": user['role'] ?? "Patient",
              "email": user['email'] ?? "",
            })
        .toList();
  }

  void _unlinkProfile(String email, String name) {
    setState(() {
      globalConnections.removeWhere((conn) => 
        conn['caregiverEmail']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase() && 
        conn['patientEmail']?.trim().toLowerCase() == email.trim().toLowerCase());
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Unlinked from $name"), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = connectedProfiles;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.blue, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Linked Patients", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: profiles.isEmpty 
      ? _buildEmptyState() 
      : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Monitored Patients",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
            ),
            const SizedBox(height: 8),
            const Text(
              "Select a patient profile to manage their medication dispenser schedule.",
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 25),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                return _buildPatientCard(profiles[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, String> profile) {
    return GestureDetector(
      // Tapping the card also navigates to the schedule editor
      onTap: () => _navigateToEditor(profile['email']!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.person_outline, color: Color(0xFF1A3B70)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile['name']!, 
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      const Text("Linked Patient", 
                        style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 15),
            const Divider(),
            const SizedBox(height: 10),
            Text("Email: ${profile['email']}", style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 20),
            Row(
              children: [
                // Manage Schedule Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToEditor(profile['email']!),
                    icon: const Icon(Icons.calendar_month, size: 18, color: Colors.white),
                    label: const Text("Manage Schedule", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3B70),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Remove Patient Button
                OutlinedButton(
                  onPressed: () => _unlinkProfile(profile['email']!, profile['name']!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Icon(Icons.link_off, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper function to handle navigation
  // --- UPDATED NAVIGATION LOGIC ---
  void _navigateToEditor(String targetEmail) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CaregiverScheduleEditor(
          userEmail: widget.userEmail, 
          // FIXED: Changed from targetPatientEmail to initialTargetEmail
          initialTargetEmail: targetEmail, 
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text("No monitored patients yet.", style: TextStyle(color: Colors.grey)),
    );
  }
}