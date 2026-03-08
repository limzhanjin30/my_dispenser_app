import 'package:flutter/material.dart';
// REPLACE the 'main.dart' import with your new model:
import '../modals/user_modal.dart'; // <--- CHANGED THIS LINE

class PatientLinked extends StatefulWidget {
  final String userEmail;
  const PatientLinked({super.key, required this.userEmail});

  @override
  State<PatientLinked> createState() => _PatientLinkedState();
}

class _PatientLinkedState extends State<PatientLinked> {
  // Logic to find real connected caregivers and providers
  List<Map<String, String>> get connectedProfiles {
    // 1. Find all connection emails where THIS user is the patient
    // (This now successfully pulls from user_model.dart!)
    final myConnectionEmails = globalConnections
        .where(
          (conn) =>
              conn['patientEmail']?.trim().toLowerCase() ==
              widget.userEmail.trim().toLowerCase(),
        )
        .map((conn) => conn['caregiverEmail']?.trim().toLowerCase())
        .toList();

    // 2. Map those emails to their full user profiles from registeredUsers
    // (This also successfully pulls from user_model.dart!)
    return registeredUsers
        .where(
          (user) =>
              myConnectionEmails.contains(user['email']?.trim().toLowerCase()),
        )
        .map(
          (user) => {
            "name": user['name'] ?? "Unknown User",
            "role": user['role'] ?? "Caregiver",
            "email": user['email'] ?? "",
          },
        )
        .toList();
  }

  void _unlinkProfile(String email, String name) {
    setState(() {
      // Removes the specific connection from the global list using normalization
      globalConnections.removeWhere(
        (conn) =>
            conn['patientEmail']?.trim().toLowerCase() ==
                widget.userEmail.trim().toLowerCase() &&
            conn['caregiverEmail']?.trim().toLowerCase() ==
                email.trim().toLowerCase(),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Unlinked from $name"),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Refresh the list every time the screen builds
    final profiles = connectedProfiles;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.blue, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Linked Caregivers/Providers",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
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
                    "Active Connections",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A3B70),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "These individuals can monitor your Smart Medicine Dispenser logs and receive medication alerts.",
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 25),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return _buildRequestCard(profile);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRequestCard(Map<String, String> profile) {
    // Determine icon based on role for better UX
    IconData roleIcon = profile['role'] == "Healthcare\nProvider"
        ? Icons.medical_services_outlined
        : Icons.person_outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
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
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE3F2FD),
                child: Icon(roleIcon, color: const Color(0xFF1A3B70)),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile['name']!,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      profile['role']!.replaceAll('\n', ' '),
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(),
          const SizedBox(height: 10),
          Text(
            "Email: ${profile['email']}",
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _unlinkProfile(profile['email']!, profile['name']!),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text("Unlink Profile"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text(
            "No active connections.",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            "Your linked caregivers will appear here.",
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
