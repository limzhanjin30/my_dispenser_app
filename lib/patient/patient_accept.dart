import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPendingRequests, and globalConnections

class PatientAccept extends StatefulWidget {
  final String userEmail;
  const PatientAccept({super.key, required this.userEmail});

  @override
  State<PatientAccept> createState() => _PatientAcceptState();
}

class _PatientAcceptState extends State<PatientAccept> {
  // Logic to filter the global list for requests specifically for this patient
  List<Map<String, String>> get myRequests => globalPendingRequests
      .where((req) => req['receiverEmail'] == widget.userEmail)
      .toList();

  void _handleAction(int index, bool isAccepted) {
    var request = myRequests[index];
    String senderName = request['senderName']!;

    if (isAccepted) {
      setState(() {
        // --- NORMALIZED DATA STORAGE ---
        globalConnections.add({
          "patientEmail": widget.userEmail.trim().toLowerCase(),
          "caregiverEmail": request['senderEmail']!.trim().toLowerCase(),
        });
      });
    }

    // Remove the request (use normalized check here too)
    setState(() {
      globalPendingRequests.removeWhere((req) =>
          req['senderEmail']?.trim().toLowerCase() == request['senderEmail']?.trim().toLowerCase() &&
          req['receiverEmail']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase());
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isAccepted ? "Accepted request from $senderName" : "Declined $senderName"),
        backgroundColor: isAccepted ? Colors.teal : Colors.redAccent,
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
        title: const Text("Pending Requests",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: myRequests.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
              child: Column(
                children: [
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
                    // --- BOLD ROLE AT TOP ---
                    Text(
                      request['senderRole']?.replaceAll('\n', ' ') ?? "User",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16, 
                        color: Color(0xFF1A3B70)
                      ),
                    ),
                    const SizedBox(height: 4),
                    // --- NAME + DESCRIPTION TEXT ---
                    Text(
                      "${request['requestText']}",
                      style: const TextStyle(
                        fontSize: 14, 
                        color: Colors.black87,
                        height: 1.3
                      ),
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
                  onPressed: () => _handleAction(index, true),
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
                  onPressed: () => _handleAction(index, false),
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