import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'healthcare_prescription.dart'; // Navigation target

class HealthcareLinked extends StatefulWidget {
  final String userEmail; 
  const HealthcareLinked({super.key, required this.userEmail});

  @override
  State<HealthcareLinked> createState() => _HealthcareLinkedState();
}

class _HealthcareLinkedState extends State<HealthcareLinked> {
  
  // --- LOGIC: REVOKE CLINICAL ACCESS ---
  Future<void> _unlinkProfile(String docId, String name) async {
    try {
      await FirebaseFirestore.instance.collection('connections').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Clinical oversight ended for $name"), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      debugPrint("Error unlinking patient: $e");
    }
  }

  // --- NAVIGATION: TO CLINICAL PRESCRIPTION EDITOR ---
  void _navigateToEditor(String targetEmail) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HealthcarePrescription(
          userEmail: widget.userEmail, 
          initialTargetEmail: targetEmail, // Passes the clicked patient email
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIXED: The query must look for 'healthcareEmail' for this role
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('connections')
          .where('healthcareEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
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
              String patientEmail = connData['patientEmail'];
              String docId = connectionDocs[index].id;

              // RELATIONAL LOOKUP: Fetch patient name and hardware status from 'users'
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
                  String? machineId = userData['linkedMachineId'];

                  return _buildPatientCard(
                    docId, 
                    userData['name'] ?? "Unknown Patient", 
                    patientEmail,
                    machineId
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
      title: const Text("Clinical Patient Registry", 
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildPatientCard(String docId, String name, String email, String? machineId) {
    bool isHardwareReady = machineId != null && machineId.isNotEmpty;

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
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.person_outline, color: Color(0xFF1A3B70)),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              // Hardware Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isHardwareReady ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isHardwareReady ? Icons.check_circle : Icons.warning_amber_rounded,
                      size: 12, color: isHardwareReady ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isHardwareReady ? "Active Hub" : "Offline",
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, 
                        color: isHardwareReady ? Colors.green : Colors.orange.shade800
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToEditor(email),
                  icon: const Icon(Icons.settings_suggest, size: 18, color: Colors.white),
                  label: const Text("Configure Bins", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_ind_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("No clinical patients assigned.", 
            style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
            child: Text("Ensure patients have linked your doctor email in their app dashboard.", 
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
          )
        ],
      ),
    );
  }
}