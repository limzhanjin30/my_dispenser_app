import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; 
class PatientRequest extends StatefulWidget {
  final String userEmail; // Current patient's email
  const PatientRequest({super.key, required this.userEmail});

  @override
  State<PatientRequest> createState() => _PatientRequestState();
}

class _PatientRequestState extends State<PatientRequest> {
  final TextEditingController _targetEmailController = TextEditingController();
  String patientName = "";

  @override
  void initState() {
    super.initState();
    _fetchPatientName();
  }

  // Fetches the patient's name from global storage for the request text
  void _fetchPatientName() {
    final user = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase(),
      orElse: () => {},
    );
    if (user.isNotEmpty) {
      setState(() {
        patientName = user['name'] ?? "Patient";
      });
    }
  }

  void _findAndRequest() {
    // 1. Normalize emails immediately
    String targetEmail = _targetEmailController.text.trim().toLowerCase();
    String myEmail = widget.userEmail.trim().toLowerCase();

    if (targetEmail.isEmpty) {
      _showSnackBar("Please enter an email address", Colors.orange);
      return;
    }

    if (targetEmail == myEmail) {
      _showSnackBar("You cannot request access to your own account.", Colors.red);
      return;
    }

    // 2. Check if already linked
    bool alreadyLinked = globalConnections.any((conn) =>
        conn['patientEmail']?.trim().toLowerCase() == myEmail && 
        conn['caregiverEmail']?.trim().toLowerCase() == targetEmail);
    
    if (alreadyLinked) {
      _showSnackBar("You are already linked to this profile.", Colors.blue);
      return;
    }

    // --- STEP 3: NEW AUTO-ACCEPT LOGIC ---
    // Check if there is an INCOMING request from this targetEmail to ME
    var incomingReq = globalPendingRequests.firstWhere(
      (req) => req['senderEmail']?.trim().toLowerCase() == targetEmail && 
               req['receiverEmail']?.trim().toLowerCase() == myEmail,
      orElse: () => {},
    );

    if (incomingReq.isNotEmpty) {
      setState(() {
        // 1. Remove the pending incoming request
        globalPendingRequests.removeWhere((req) =>
            req['senderEmail']?.trim().toLowerCase() == targetEmail &&
            req['receiverEmail']?.trim().toLowerCase() == myEmail);

        // 2. Establish the permanent connection immediately
        globalConnections.add({
          "patientEmail": myEmail,
          "caregiverEmail": targetEmail, // Shared key for both caregivers and doctors
        });
      });

      _showSnackBar("Mutual request found! Connection established instantly.", Colors.teal);
      _targetEmailController.clear();
      Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
      return; // Exit early since we are now connected
    }

    // 4. Check if a request has already been sent by me (Duplicate check)
    bool alreadyPending = globalPendingRequests.any((req) =>
        req['senderEmail']?.trim().toLowerCase() == myEmail && 
        req['receiverEmail']?.trim().toLowerCase() == targetEmail);
    
    if (alreadyPending) {
      _showSnackBar("A request has already been sent to this email.", Colors.orange);
      return;
    }

    // 5. Verify the target user exists and has a valid role
    var provider = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == targetEmail && 
             (u['role'] == 'Caregiver' || u['role'] == 'Healthcare\nProvider'),
      orElse: () => {},
    );

    if (provider.isNotEmpty) {
      String targetRole = provider['role']!.replaceAll('\n', ' ');
      
      setState(() {
        globalPendingRequests.add({
          "senderEmail": myEmail,
          "senderName": patientName,
          "receiverEmail": targetEmail,
          "senderRole": "Patient",
          "requestText": "$patientName ($myEmail) is requesting you to manage their medication dispenser.",
        });
      });

      _showSnackBar("Request sent to $targetEmail ($targetRole).", Colors.green);
      _targetEmailController.clear();
      Future.delayed(const Duration(seconds: 1), () => Navigator.pop(context));
    } else {
      _showSnackBar("Provider record not found. Please verify the email.", Colors.red);
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
        title: const Text("Connect Provider", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Link a Caregiver/Doctor", 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
            const SizedBox(height: 10),
            const Text(
              "Enter the email of a caregiver or healthcare provider. If they have already requested access, searching for them will connect you instantly.",
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
                      Text("Provider Search", 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _targetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "Enter Caregiver or Doctor's Email",
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
                      child: const Text("Search & Connect", 
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