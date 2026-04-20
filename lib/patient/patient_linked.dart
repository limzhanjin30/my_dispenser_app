import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientLinked extends StatefulWidget {
  final String userEmail;
  const PatientLinked({super.key, required this.userEmail});

  @override
  State<PatientLinked> createState() => _PatientLinkedState();
}

class _PatientLinkedState extends State<PatientLinked> {
  
  // --- LOGIC: DELETE CONNECTION ---
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
    // 1. Listen to all connections where the current user is the Patient
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('connections')
          .where('patientEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70))));
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
          body: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: connectionDocs.length,
            itemBuilder: (context, index) {
              var connData = connectionDocs[index].data() as Map<String, dynamic>;
              
              // 2. LOGIC FIX: Identify which email key exists in this document
              String? caregiverEmail = connData['caregiverEmail'];
              String? healthcareEmail = connData['healthcareEmail'];
              String targetEmail = caregiverEmail ?? healthcareEmail ?? "";
              
              String docId = connectionDocs[index].id;

              if (targetEmail.isEmpty) return const SizedBox.shrink();

              // 3. RELATIONAL LOOKUP: Fetch details from 'users' using the identified email
              return FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: targetEmail)
                    .limit(1)
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                    // This handles cases where the link exists but the user profile is missing
                    return const SizedBox.shrink();
                  }

                  var userData = userSnapshot.data!.docs.first.data() as Map<String, dynamic>;
                  return _buildRequestCard(
                    docId, 
                    userData['name'] ?? "Unknown User", 
                    userData['role'] ?? "Provider", 
                    targetEmail
                  );
                },
              );
            },
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
      title: const Text("Trusted Connections", 
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildRequestCard(String docId, String name, String role, String email) {
    // Dynamic styling based on Role
    bool isHealthcare = role.contains("Healthcare");
    IconData roleIcon = isHealthcare ? Icons.medical_services_outlined : Icons.people_outline;
    Color themeColor = isHealthcare ? Colors.teal : const Color(0xFF1A3B70);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: isHealthcare ? const Color(0xFFE0F2F1) : const Color(0xFFE3F2FD),
                child: Icon(roleIcon, color: themeColor),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(
                      role.replaceAll('\n', ' ').toUpperCase(), 
                      style: TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("REGISTERED EMAIL", style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                    Text(email, style: const TextStyle(color: Colors.black87, fontSize: 13)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _unlinkProfile(docId, name),
                icon: const Icon(Icons.link_off, size: 14),
                label: const Text("Revoke", style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          Icon(Icons.supervised_user_circle_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("No active connections.", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text("Link with a family member or doctor to enable remote monitoring.", 
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}