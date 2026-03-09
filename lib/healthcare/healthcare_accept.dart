import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---

class HealthcareAccept extends StatefulWidget {
  final String userEmail;
  const HealthcareAccept({super.key, required this.userEmail});

  @override
  State<HealthcareAccept> createState() => _HealthcareAcceptState();
}

class _HealthcareAcceptState extends State<HealthcareAccept> {
  
  // --- NEW: LOGIC TO HANDLE FIREBASE ACTIONS ---
  Future<void> _handleAction(String requestId, Map<String, dynamic> requestData, bool isAccepted) async {
    try {
      if (isAccepted) {
        // 1. Create a permanent connection in the 'connections' collection
        // We use 'caregiverEmail' as the common key for both Caregivers and Healthcare Providers
        await FirebaseFirestore.instance.collection('connections').add({
          "caregiverEmail": widget.userEmail.trim().toLowerCase(),
          "patientEmail": requestData['senderEmail']!.trim().toLowerCase(),
          "connectedAt": FieldValue.serverTimestamp(),
        });
      }

      // 2. Delete the request from the 'requests' collection
      await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAccepted ? "Patient linked to your clinical panel!" : "Request declined"),
            backgroundColor: isAccepted ? Colors.teal : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error handling healthcare request: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NEW: REAL-TIME STREAM OF INCOMING REQUESTS ---
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('receiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
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

        final requests = snapshot.data!.docs;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F9FF),
          appBar: _buildAppBar(),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Connection Requests",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Patients listed below want you to manage their medication dispenser.",
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 25),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    var requestDoc = requests[index];
                    var data = requestDoc.data() as Map<String, dynamic>;
                    return _buildRequestCard(requestDoc.id, data);
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
      title: const Text("Healthcare Access Requests",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildRequestCard(String docId, Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[100],
                radius: 25,
                child: const Icon(Icons.person, color: Color(0xFF1A3B70), size: 28),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['senderRole'] ?? "Patient",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 12, 
                        color: Colors.blue,
                        letterSpacing: 1.1
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${request['requestText']}",
                      style: const TextStyle(
                        fontSize: 15, 
                        color: Colors.black87,
                        height: 1.3
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
                child: ElevatedButton(
                  onPressed: () => _handleAction(docId, request, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Accept", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleAction(docId, request, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueGrey),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Decline", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 100),
          Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text("No pending requests", style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 5),
          const Text("Patients you link with will appear here.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}