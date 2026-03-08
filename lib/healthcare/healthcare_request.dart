import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPendingRequests, and globalConnections

class HealthcareRequest extends StatefulWidget {
  final String userEmail; // Current Healthcare's email
  const HealthcareRequest({super.key, required this.userEmail});

  @override
  State<HealthcareRequest> createState() => _HealthcareRequestState();
}

class _HealthcareRequestState extends State<HealthcareRequest> {
  final TextEditingController _patientEmailController = TextEditingController();
  
  String fullName = ""; 

  @override
  void initState() {
    super.initState();
    _fetchHealthcareName();
  }

  void _fetchHealthcareName() {
    try {
      final user = registeredUsers.firstWhere(
        (u) => u['email']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase(),
        orElse: () => {},
      );
      if (user.isNotEmpty && user.containsKey('name')) {
        setState(() {
          fullName = user['name']!;
        });
      }
    } catch (e) {
      fullName = "Healthcare Provider"; 
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

    // --- STEP 2: AUTO-ACCEPT LOGIC ---
    // Check if the patient already has an incoming request waiting for this doctor
    var incomingReq = globalPendingRequests.firstWhere(
      (req) => req['senderEmail']?.trim().toLowerCase() == targetEmail && 
               req['receiverEmail']?.trim().toLowerCase() == myEmail,
      orElse: () => {},
    );

    if (incomingReq.isNotEmpty) {
      setState(() {
        // 1. Remove the pending request from the global list
        globalPendingRequests.removeWhere((req) =>
            req['senderEmail']?.trim().toLowerCase() == targetEmail &&
            req['receiverEmail']?.trim().toLowerCase() == myEmail);

        // 2. Establish permanent connection instantly using shared key
        globalConnections.add({
          "caregiverEmail": myEmail, // Standardized key for Doctors/Caregivers
          "patientEmail": targetEmail,
        });
      });

      _showSnackBar("Mutual interest found! Patient linked to your panel instantly.", Colors.teal);
      _patientEmailController.clear();
      Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
      return; // Exit early
    }

    // --- STEP 3: Standard Request Logic ---
    bool alreadyPending = globalPendingRequests.any((req) =>
        req['senderEmail']?.trim().toLowerCase() == myEmail && 
        req['receiverEmail']?.trim().toLowerCase() == targetEmail);
    
    if (alreadyPending) {
      _showSnackBar("A request has already been sent to this email.", Colors.orange);
      return;
    }

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
          "senderRole": "Healthcare\nProvider", 
          "requestText": "$fullName ($myEmail) is requesting access to your dispenser logs.",
        });
      });

      _showSnackBar("Request sent to $targetEmail. Awaiting approval.", Colors.green);
      _patientEmailController.clear();
      Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
    } else {
      _showSnackBar("Patient record not found. Please verify the email.", Colors.red);
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
        title: const Text("Add New Patient", 
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
            const Text("Patient Search", 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
            const SizedBox(height: 10),
            const Text(
              "Search for a patient by their registered email. If they have already requested your oversight, the connection will be established immediately.",
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 30),

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
                      Text("Enter Patient Email", 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _patientEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "example@patient.com",
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
                      child: const Text("Establish Connection", 
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