import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPendingRequests, and globalConnections

class CaregiverAccept extends StatefulWidget {
  final String userEmail;
  const CaregiverAccept({super.key, required this.userEmail});

  @override
  State<CaregiverAccept> createState() => _CaregiverAcceptState();
}

class _CaregiverAcceptState extends State<CaregiverAccept> {
  
  // --- UPDATED: NORMALIZED FILTERING ---
  // Filters the global list for requests specifically for THIS caregiver
  // Inside _CaregiverAcceptState
  List<Map<String, String>> get myRequests {
    // 1. Normalize the email of the caregiver currently logged in
    String cleanMyEmail = widget.userEmail.trim().toLowerCase();
    
    // 2. Filter the global list using normalized comparisons
    return globalPendingRequests.where((req) {
      String receiver = req['receiverEmail']?.trim().toLowerCase() ?? "";
      
      return receiver == cleanMyEmail;
    }).toList();
  }

  void _handleAction(int index, bool isAccepted) {
    var request = myRequests[index];
    String senderName = request['senderName']!;
    String senderEmail = request['senderEmail']!;

    if (isAccepted) {
      setState(() {
        // Create permanent link in globalConnections
        globalConnections.add({
          "caregiverEmail": widget.userEmail.trim().toLowerCase(),
          "patientEmail": senderEmail.trim().toLowerCase(),
        });
      });
    }

    // Remove the request from globalPendingRequests using normalized check
    setState(() {
      globalPendingRequests.removeWhere((req) =>
          req['senderEmail']?.trim().toLowerCase() == senderEmail.trim().toLowerCase() &&
          req['receiverEmail']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase());
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isAccepted ? "Accepted request from $senderName" : "Declined $senderName"),
        backgroundColor: isAccepted ? Colors.teal : Colors.redAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.blue, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Caregiver Access Requests",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: myRequests.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
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
                    itemCount: myRequests.length,
                    itemBuilder: (context, index) {
                      final request = myRequests[index];
                      return _buildRequestCard(index, request);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRequestCard(int index, Map<String, String> request) {
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
                  onPressed: () => _handleAction(index, true),
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
                  onPressed: () => _handleAction(index, false),
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