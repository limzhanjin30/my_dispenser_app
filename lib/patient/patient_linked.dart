import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---

class PatientLinked extends StatefulWidget {
  final String userEmail;
  const PatientLinked({super.key, required this.userEmail});

  @override
  State<PatientLinked> createState() => _PatientLinkedState();
}

class _PatientLinkedState extends State<PatientLinked> {
  
  // --- NEW: LOGIC TO DELETE CONNECTION FROM FIREBASE ---
  Future<void> _unlinkProfile(String docId, String name) async {
    try {
      await FirebaseFirestore.instance.collection('connections').doc(docId).delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unlinked from $name"), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      debugPrint("Error unlinking: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NEW: REAL-TIME STREAM OF CONNECTIONS ---
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('connections')
          .where('patientEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F9FF),
            appBar: _buildAppBar(),
            body: _buildEmptyState(),
          );
        }

        final connectionDocs = snapshot.data!.docs;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F9FF),
          appBar: _buildAppBar(),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Active Connections",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
                ),
                const SizedBox(height: 8),
                const Text(
                  "These individuals can monitor your Smart Medicine Dispenser logs and receive medication alerts.",
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 25),

                // We map each connection to a FutureBuilder to fetch the Caregiver's Name/Role from the 'users' collection
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: connectionDocs.length,
                  itemBuilder: (context, index) {
                    var connData = connectionDocs[index].data() as Map<String, dynamic>;
                    String caregiverEmail = connData['caregiverEmail'];
                    String docId = connectionDocs[index].id;

                    return FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .where('email', isEqualTo: caregiverEmail)
                          .limit(1)
                          .get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        var userData = userSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                        return _buildRequestCard(
                          docId, 
                          userData['name'] ?? "Unknown User", 
                          userData['role'] ?? "Caregiver", 
                          caregiverEmail
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.blue, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text("Linked Caregivers/Providers", 
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildRequestCard(String docId, String name, String role, String email) {
    IconData roleIcon = role.contains("Healthcare") 
        ? Icons.medical_services_outlined 
        : Icons.person_outline;

    return Container(
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
              CircleAvatar(
                backgroundColor: const Color(0xFFE3F2FD),
                child: Icon(roleIcon, color: const Color(0xFF1A3B70)),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(role.replaceAll('\n', ' '), 
                      style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(),
          const SizedBox(height: 10),
          Text("Email: $email", style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _unlinkProfile(docId, name),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text("Unlink Profile"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          const Text("No active connections.", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          const Text("Your linked caregivers will appear here.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}