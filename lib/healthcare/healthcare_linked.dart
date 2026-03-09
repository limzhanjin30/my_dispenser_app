import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---

class HealthcareLinked extends StatefulWidget {
  final String userEmail; 
  const HealthcareLinked({super.key, required this.userEmail});

  @override
  State<HealthcareLinked> createState() => _HealthcareLinkedState();
}

class _HealthcareLinkedState extends State<HealthcareLinked> {
  
  // --- NEW: DELETE CONNECTION FROM FIREBASE ---
  Future<void> _unlinkPatient(String docId, String name) async {
    try {
      await FirebaseFirestore.instance.collection('connections').doc(docId).delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Access revoked for $name"), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint("Error revoking access: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NEW: REAL-TIME STREAM OF PATIENTS LINKED TO THIS DOCTOR ---
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('connections')
          .where('caregiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
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
                  "Managed Patients",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Below are the patients who have authorized you to monitor their dispenser activity.",
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 25),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: connectionDocs.length,
                  itemBuilder: (context, index) {
                    var connData = connectionDocs[index].data() as Map<String, dynamic>;
                    String patientEmail = connData['patientEmail'];
                    String docId = connectionDocs[index].id;

                    // Fetch the Patient's Name from the 'users' collection
                    return FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .where('email', isEqualTo: patientEmail)
                          .limit(1)
                          .get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        var userData = userSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                        return _buildPatientCard(
                          docId, 
                          userData['name'] ?? "Unknown Patient", 
                          patientEmail
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
      title: const Text("Clinical Patient Panel", 
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildPatientCard(String docId, String name, String email) {
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
              const CircleAvatar(
                backgroundColor: Color(0xFFE0F2F1),
                child: Icon(Icons.person, color: Colors.teal),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Text("Active Clinical Connection", 
                      style: TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.w600)),
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
                  onPressed: () => _unlinkPatient(docId, name),
                  icon: const Icon(Icons.person_remove_outlined, size: 18),
                  label: const Text("Revoke My Access"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_ind_outlined, size: 80, color: Colors.grey),
          SizedBox(height: 10),
          Text("No clinical patients assigned.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}