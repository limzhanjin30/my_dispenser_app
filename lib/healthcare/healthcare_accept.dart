import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HealthcareAccept extends StatefulWidget {
  final String userEmail;
  const HealthcareAccept({super.key, required this.userEmail});

  @override
  State<HealthcareAccept> createState() => _HealthcareAcceptState();
}

class _HealthcareAcceptState extends State<HealthcareAccept> {
  
  // --- LOGIC: PROCESS CLINICAL ACCESS REQUESTS ---
  Future<void> _handleAction(String requestId, Map<String, dynamic> requestData, bool isAccepted) async {
    try {
      if (isAccepted) {
        // 1. Create a permanent connection in the 'connections' collection
        // FIXED: Using 'healthcareEmail' key so clinical dashboard can find the patient
        await FirebaseFirestore.instance.collection('connections').add({
          "healthcareEmail": widget.userEmail.trim().toLowerCase(),
          "patientEmail": requestData['senderEmail']!.trim().toLowerCase(),
          "connectedAt": FieldValue.serverTimestamp(),
        });
      }

      // 2. Delete the request from the 'requests' collection to clear the inbox
      await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAccepted ? "Patient added to your clinical panel!" : "Request declined"),
            backgroundColor: isAccepted ? Colors.teal : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error handling healthcare request: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // REAL-TIME STREAM: Show clinical requests sent to this Doctor
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Pending Authorizations",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Patients listed below have invited you to monitor their dispenser activity professionally.",
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
      title: const Text("Access Inbox",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
      backgroundColor: Colors.white,
      elevation: 0.5,
      centerTitle: true,
    );
  }

  Widget _buildRequestCard(String docId, Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Color(0xFFE0F2F1), shape: BoxShape.circle),
                child: const Icon(Icons.person_add_alt_1_outlined, color: Colors.teal, size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['senderName'] ?? "Patient",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                    const Text(
                      "CLINICAL OVERSIGHT REQUEST",
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 10, 
                        color: Colors.blue,
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
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "${request['requestText']}",
              style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
            ),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleAction(docId, request, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Accept Access", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleAction(docId, request, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blueGrey,
                    side: const BorderSide(color: Colors.blueGrey),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
          Icon(Icons.mark_email_read_outlined, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 15),
          const Text("No pending clinical requests", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const Text("Patients you verify will appear here.", style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}