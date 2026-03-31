import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'caregiver_schedule_editor.dart';

class CaregiverLinked extends StatefulWidget {
  final String userEmail; 
  const CaregiverLinked({super.key, required this.userEmail});

  @override
  State<CaregiverLinked> createState() => _CaregiverLinkedState();
}

class _CaregiverLinkedState extends State<CaregiverLinked> {
  
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
          body: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: connectionDocs.length,
            itemBuilder: (context, index) {
              var connData = connectionDocs[index].data() as Map<String, dynamic>;
              String patientEmail = connData['patientEmail'];
              String docId = connectionDocs[index].id;

              // RELATIONAL LOOKUP: Fetch patient name and hardware status
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
                    userData['name'] ?? "Unknown User", 
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
      title: const Text("Linked Patients", 
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
                    Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              // NEW: Hardware Status Indicator
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
                      size: 12, 
                      color: isHardwareReady ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isHardwareReady ? "Hardware Linked" : "No Hardware",
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
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
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("No monitored patients yet.", 
            style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}