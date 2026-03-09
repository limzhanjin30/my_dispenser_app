import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---

class HealthcareRequest extends StatefulWidget {
  final String userEmail; // Current Healthcare's email
  const HealthcareRequest({super.key, required this.userEmail});

  @override
  State<HealthcareRequest> createState() => _HealthcareRequestState();
}

class _HealthcareRequestState extends State<HealthcareRequest> {
  final TextEditingController _patientEmailController = TextEditingController();
  String fullName = ""; 
  bool isLoading = false; // Added for async feedback

  @override
  void initState() {
    super.initState();
    _fetchHealthcareName();
  }

  // Fetches Provider name from Firestore users collection
  Future<void> _fetchHealthcareName() async {
    try {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userDoc.docs.isNotEmpty) {
        setState(() {
          fullName = userDoc.docs.first.get('name') ?? "Healthcare Provider";
        });
      }
    } catch (e) {
      debugPrint("Error fetching name: $e");
    }
  }

  Future<void> _findAndRequest() async {
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

    setState(() => isLoading = true);

    try {
      // 1. Check if already linked in 'connections' collection
      var existingConn = await FirebaseFirestore.instance
          .collection('connections')
          .where('caregiverEmail', isEqualTo: myEmail)
          .where('patientEmail', isEqualTo: targetEmail)
          .get();

      if (existingConn.docs.isNotEmpty) {
        _showSnackBar("You are already linked to this patient.", Colors.blue);
        setState(() => isLoading = false);
        return;
      }

      // 2. AUTO-ACCEPT LOGIC: Check if patient already sent a request to ME
      var incomingReq = await FirebaseFirestore.instance
          .collection('requests')
          .where('senderEmail', isEqualTo: targetEmail)
          .where('receiverEmail', isEqualTo: myEmail)
          .get();

      if (incomingReq.docs.isNotEmpty) {
        // HANDSHAKE: Establish connection instantly
        await FirebaseFirestore.instance.collection('connections').add({
          "caregiverEmail": myEmail, // Standardized shared key
          "patientEmail": targetEmail,
          "connectedAt": FieldValue.serverTimestamp(),
        });

        // Delete the redundant request
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(incomingReq.docs.first.id)
            .delete();

        _showSnackBar("Mutual interest found! Connection established.", Colors.teal);
        Navigator.pop(context);
        return;
      }

      // 3. Verify Patient exists and check for duplicate outgoing requests
      var patientQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .where('role', isEqualTo: 'Patient')
          .limit(1)
          .get();

      if (patientQuery.docs.isEmpty) {
        _showSnackBar("Patient record not found. Please verify the email.", Colors.red);
      } else {
        // Check if I already sent a request
        var pending = await FirebaseFirestore.instance
            .collection('requests')
            .where('senderEmail', isEqualTo: myEmail)
            .where('receiverEmail', isEqualTo: targetEmail)
            .get();

        if (pending.docs.isNotEmpty) {
          _showSnackBar("A request has already been sent to this patient.", Colors.orange);
        } else {
          // Create the request document in Firestore
          await FirebaseFirestore.instance.collection('requests').add({
            "senderEmail": myEmail,
            "senderName": fullName, 
            "receiverEmail": targetEmail,
            "senderRole": "Healthcare\nProvider", 
            "requestText": "$fullName ($myEmail) is requesting access to your dispenser logs.",
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp(),
          });

          _showSnackBar("Request sent to $targetEmail. Awaiting approval.", Colors.green);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showSnackBar("Database error: ${e.toString()}", Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
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
                children: [
                  TextField(
                    controller: _patientEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "example@patient.com",
                      prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF1A3B70)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 25),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _findAndRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A3B70),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Establish Connection", 
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