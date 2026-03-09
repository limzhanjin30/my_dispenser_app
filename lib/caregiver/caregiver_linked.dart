import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---
import 'caregiver_schedule_editor.dart';

class CaregiverLinked extends StatefulWidget {
  final String userEmail; 
  const CaregiverLinked({super.key, required this.userEmail});

  @override
  State<CaregiverLinked> createState() => _CaregiverLinkedState();
}

class _CaregiverLinkedState extends State<CaregiverLinked> {
  
  // --- NEW: LOGIC TO DELETE CONNECTION FROM FIREBASE ---
  Future<void> _unlinkProfile(String docId, String name) async {
    try {
      await FirebaseFirestore.instance.collection('connections').doc(docId).delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Access revoked for $name"), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      debugPrint("Error unlinking patient: $e");
    }
  }

  // Helper function to handle navigation
  void _navigateToEditor(String targetEmail) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CaregiverScheduleEditor(
          userEmail: widget.userEmail, 
          initialTargetEmail: targetEmail, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- NEW: REAL-TIME STREAM OF PATIENTS LINKED TO THIS CAREGIVER ---
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
                  itemCount: connectionDocs.length,
                  itemBuilder: (context, index) {
                    var connData = connectionDocs[index].data() as Map<String, dynamic>;
                    String patientEmail = connData['patientEmail'];
                    String docId = connectionDocs[index].id;

                    // Fetch the Patient's detailed info from the 'users' collection
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
                          userData['name'] ?? "Unknown User", 
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
      title: const Text("Linked Patients", 
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildPatientCard(String docId, String name, String email) {
    return GestureDetector(
      onTap: () => _navigateToEditor(email),
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
                      Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
            Text("Email: $email", style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToEditor(email),
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
                OutlinedButton(
                  onPressed: () => _unlinkProfile(docId, name),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("No monitored patients yet.", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}