import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPendingRequests, and globalConnections

class CaregiverRequest extends StatefulWidget {
  final String userEmail; // Current Caregiver's email
  const CaregiverRequest({super.key, required this.userEmail});

  @override
  State<CaregiverRequest> createState() => _CaregiverRequestState();
}

class _CaregiverRequestState extends State<CaregiverRequest> {
  final TextEditingController _patientEmailController = TextEditingController();
  
  // Initialize with a loading state
  String fullName = ""; 

  @override
  void initState() {
    super.initState();
    _fetchCaregiverName();
  }

  // Fetches the sender's full name from the global user list
  void _fetchCaregiverName() {
    try {
      final user = registeredUsers.firstWhere(
        (u) => u['email'] == widget.userEmail,
        orElse: () => {},
      );
      if (user.isNotEmpty && user.containsKey('name')) {
        setState(() {
          fullName = user['name']!;
        });
      }
    } catch (e) {
      fullName = "User"; // Fallback name
    }
  }

  void _findAndRequest() {
    String targetEmail = _patientEmailController.text.trim().toLowerCase();
    String myEmail = widget.userEmail.trim().toLowerCase();

    if (targetEmail.isEmpty) {
      _showSnackBar("Please enter an email address", Colors.orange);
      return;
    }

    if (targetEmail == myEmail) {
      _showSnackBar("You cannot request access to your own account.", Colors.red);
      return;
    }

    // --- STEP 1: Check if already linked ---
    bool alreadyLinked = globalConnections.any((conn) =>
        conn['caregiverEmail']?.trim().toLowerCase() == myEmail && 
        conn['patientEmail']?.trim().toLowerCase() == targetEmail);
    
    if (alreadyLinked) {
      _showSnackBar("You are already linked to this patient.", Colors.blue);
      return;
    }

    // --- STEP 2: NEW AUTO-ACCEPT LOGIC ---
    // Check if there is an INCOMING request from this patient to ME
    var incomingReq = globalPendingRequests.firstWhere(
      (req) => req['senderEmail']?.trim().toLowerCase() == targetEmail && 
               req['receiverEmail']?.trim().toLowerCase() == myEmail,
      orElse: () => {},
    );

    if (incomingReq.isNotEmpty) {
      setState(() {
        // 1. Remove the patient's request from the pending list
        globalPendingRequests.removeWhere((req) =>
            req['senderEmail']?.trim().toLowerCase() == targetEmail &&
            req['receiverEmail']?.trim().toLowerCase() == myEmail);

        // 2. Add to permanent connections
        globalConnections.add({
          "caregiverEmail": myEmail,
          "patientEmail": targetEmail,
        });
      });

      _showSnackBar("A request from this patient was already waiting. Connection established!", Colors.teal);
      Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
      return; // Exit early, no need to send a new request
    }

    // --- STEP 3: Standard Request Logic (Check if I already sent one) ---
    bool alreadyPending = globalPendingRequests.any((req) =>
        req['senderEmail']?.trim().toLowerCase() == myEmail && 
        req['receiverEmail']?.trim().toLowerCase() == targetEmail);
    
    if (alreadyPending) {
      _showSnackBar("A request has already been sent to this email.", Colors.orange);
      return;
    }

    // --- STEP 4: Verify Patient exists and send new request ---
    var patient = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == targetEmail && u['role'] == 'Patient',
      orElse: () => {},
    );

    if (patient.isNotEmpty) {
      setState(() {
        globalPendingRequests.add({
          "senderEmail": myEmail,
          "senderName": fullName, 
          "receiverEmail": targetEmail,
          "senderRole": "Caregiver", // Or "Healthcare\nProvider" for that file
          "requestText": "$fullName ($myEmail) is requesting access to your dispenser logs.",
        });
      });
      _showSnackBar("Request sent to $targetEmail. Awaiting approval.", Colors.green);
      Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
    } else {
      _showSnackBar("Patient record not found.", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 2)),
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
        title: const Text("Request Patient Access", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Connect with Patient", 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
            const SizedBox(height: 10),
            const Text(
              "Enter the patient's registered email to link their medication dispenser to your clinical dashboard.",
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 30),

            // --- SEARCH CARD ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person_search_outlined, color: Color(0xFF1A3B70)),
                      SizedBox(width: 10),
                      Text("Search Patient", 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _patientEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "Enter Patient's Email",
                      prefixIcon: const Icon(Icons.alternate_email),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _findAndRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A3B70),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Send Access Request", 
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}