import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientAccept extends StatefulWidget {
  final String userEmail;
  const PatientAccept({super.key, required this.userEmail});

  @override
  State<PatientAccept> createState() => _PatientAcceptState();
}

class _PatientAcceptState extends State<PatientAccept> {
  
  // --- LOGIC: PROCESS INCOMING REQUESTS ---
  Future<void> _handleAction(String requestId, Map<String, dynamic> requestData, bool isAccepted) async {
    try {
      if (isAccepted) {
        String senderRole = requestData['senderRole'] ?? "";
        String senderEmail = requestData['senderEmail']!.trim().toLowerCase();
        String myEmail = widget.userEmail.trim().toLowerCase();

        // 1. Prepare connection data based on the Sender's Role
        Map<String, dynamic> connectionMap = {
          "patientEmail": myEmail,
          "connectedAt": FieldValue.serverTimestamp(),
        };

        // Determine if this is a clinical or family connection
        if (senderRole.contains("Healthcare")) {
          connectionMap["healthcareEmail"] = senderEmail;
        } else {
          connectionMap["caregiverEmail"] = senderEmail;
        }

        // 2. Create the permanent link in 'connections'
        await FirebaseFirestore.instance.collection('connections').add(connectionMap);
      }

      // 3. Remove the request from the 'requests' collection
      await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAccepted ? "Connection established!" : "Request declined"),
            backgroundColor: isAccepted ? Colors.teal : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error handling patient acceptance: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // REAL-TIME STREAM: Show requests sent to the current Patient
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('receiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
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

        final requests = snapshot.data!.docs;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F9FF),
          appBar: _buildAppBar(),
          body: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              var requestDoc = requests[index];
              var data = requestDoc.data() as Map<String, dynamic>;
              return _buildRequestCard(requestDoc.id, data);
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
      title: const Text("Access Authorization",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildRequestCard(String docId, Map<String, dynamic> request) {
    bool isDoctor = (request['senderRole'] ?? "").toString().contains("Healthcare");

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
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
                backgroundColor: isDoctor ? const Color(0xFFE0F2F1) : const Color(0xFFE3F2FD),
                child: Icon(
                  isDoctor ? Icons.medical_services : Icons.person_outline,
                  color: isDoctor ? Colors.teal : const Color(0xFF1A3B70),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['senderName'] ?? "Unknown User",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    Text(
                      isDoctor ? "CLINICAL PROVIDER" : "FAMILY CAREGIVER",
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
                        color: isDoctor ? Colors.teal : Colors.blue,
                        letterSpacing: 1.1
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
            "${request['requestText']}",
            style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
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
                  child: const Text("Authorize", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleAction(docId, request, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blueGrey,
                    side: const BorderSide(color: Colors.blueGrey),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.bold)),
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
          Icon(Icons.notifications_none_rounded, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 15),
          const Text("Inbox Clear", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const Text("New access requests will appear here.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}