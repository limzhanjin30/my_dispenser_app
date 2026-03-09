import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---

class PatientAccept extends StatefulWidget {
  final String userEmail;
  const PatientAccept({super.key, required this.userEmail});

  @override
  State<PatientAccept> createState() => _PatientAcceptState();
}

class _PatientAcceptState extends State<PatientAccept> {
  
  // --- NEW: LOGIC TO HANDLE FIREBASE ACTIONS ---
  Future<void> _handleAction(String requestId, Map<String, dynamic> requestData, bool isAccepted) async {
    try {
      if (isAccepted) {
        // 1. Create a permanent connection in Firestore
        await FirebaseFirestore.instance.collection('connections').add({
          "patientEmail": widget.userEmail.trim().toLowerCase(),
          "caregiverEmail": requestData['senderEmail']!.trim().toLowerCase(),
          "connectedAt": FieldValue.serverTimestamp(),
        });
      }

      // 2. Delete the request from the 'requests' collection
      await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAccepted ? "Connection established!" : "Request declined"),
            backgroundColor: isAccepted ? Colors.teal : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error handling request: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- NEW: REAL-TIME STREAM OF REQUESTS ---
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('receiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .snapshots(),
      builder: (context, snapshot) {
        // Show loading while waiting for Firebase
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // Handle empty states
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
              children: [
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
      title: const Text("Pending Requests",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildRequestCard(String docId, Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
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
                backgroundColor: Colors.grey[200],
                child: Icon(
                  request['senderRole'] == "Healthcare\nProvider" ? Icons.medical_services : Icons.person,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['senderRole']?.replaceAll('\n', ' ') ?? "User",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16, 
                        color: Color(0xFF1A3B70)
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${request['requestText']}",
                      style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleAction(docId, request, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Accept", style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleAction(docId, request, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueGrey),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Decline", style: TextStyle(color: Colors.blueGrey)),
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
          Icon(Icons.mark_email_read_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 10),
          Text("No pending requests", style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}