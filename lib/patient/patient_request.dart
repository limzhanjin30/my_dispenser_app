import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // --- IMPORT FIRESTORE ---

class PatientRequest extends StatefulWidget {
  final String userEmail; 
  const PatientRequest({super.key, required this.userEmail});

  @override
  State<PatientRequest> createState() => _PatientRequestState();
}

class _PatientRequestState extends State<PatientRequest> {
  final TextEditingController _targetEmailController = TextEditingController();
  String patientName = "";
  bool isLoading = false; // Added to show loading state during DB calls

  @override
  void initState() {
    super.initState();
    _fetchPatientName();
  }

  // Fetches current user's name from Firestore
  Future<void> _fetchPatientName() async {
    try {
      var userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userDoc.docs.isNotEmpty) {
        setState(() {
          patientName = userDoc.docs.first.get('name') ?? "Patient";
        });
      }
    } catch (e) {
      print("Error fetching name: $e");
    }
  }

  Future<void> _findAndRequest() async {
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

    setState(() => isLoading = true);

    try {
      // 1. Check if already linked in 'connections' collection
      var existingConn = await FirebaseFirestore.instance
          .collection('connections')
          .where('patientEmail', isEqualTo: myEmail)
          .where('caregiverEmail', isEqualTo: targetEmail)
          .get();

      if (existingConn.docs.isNotEmpty) {
        _showSnackBar("You are already linked to this profile.", Colors.blue);
        setState(() => isLoading = false);
        return;
      }

      // 2. AUTO-ACCEPT LOGIC: Check if target already sent a request to ME
      var incomingReq = await FirebaseFirestore.instance
          .collection('requests')
          .where('senderEmail', isEqualTo: targetEmail)
          .where('receiverEmail', isEqualTo: myEmail)
          .get();

      if (incomingReq.docs.isNotEmpty) {
        // HANDSHAKE: Establish connection immediately
        await FirebaseFirestore.instance.collection('connections').add({
          "patientEmail": myEmail,
          "caregiverEmail": targetEmail,
          "connectedAt": FieldValue.serverTimestamp(),
        });

        // Delete the now-obsolete request
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(incomingReq.docs.first.id)
            .delete();

        _showSnackBar("Mutual request found! Connection established.", Colors.teal);
        Navigator.pop(context);
        return;
      }

      // 3. Verify the target user exists and is a Provider/Caregiver
      var providerQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .get();

      if (providerQuery.docs.isEmpty) {
        _showSnackBar("No user found with this email.", Colors.red);
      } else {
        var userDoc = providerQuery.docs.first;
        String role = userDoc.get('role');

        // Only allow connection to Caregiver or Healthcare Provider
        if (role == 'Caregiver' || role == 'Healthcare\nProvider') {
          
          // Check if I already sent a request
          var pending = await FirebaseFirestore.instance
              .collection('requests')
              .where('senderEmail', isEqualTo: myEmail)
              .where('receiverEmail', isEqualTo: targetEmail)
              .get();

          if (pending.docs.isNotEmpty) {
            _showSnackBar("Request is already pending.", Colors.orange);
          } else {
            // Create the request document
            await FirebaseFirestore.instance.collection('requests').add({
              "senderEmail": myEmail,
              "senderName": patientName,
              "receiverEmail": targetEmail,
              "senderRole": "Patient",
              "requestText": "$patientName ($myEmail) is requesting you to manage their dispenser.",
              "status": "pending",
              "createdAt": FieldValue.serverTimestamp(),
            });

            _showSnackBar("Request sent to $targetEmail ($role).", Colors.green);
            Navigator.pop(context);
          }
        } else {
          _showSnackBar("You can only link with Caregivers or Doctors.", Colors.orange);
        }
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", Colors.red);
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
        title: const Text("Connect Provider", 
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
            const Text("Link a Caregiver/Doctor", 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
            const SizedBox(height: 10),
            const Text(
              "Enter the email of a registered caregiver or healthcare provider to establish a secure link.",
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
                    controller: _targetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "Enter Provider's Email",
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
                        : const Text("Send Connection Request", 
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