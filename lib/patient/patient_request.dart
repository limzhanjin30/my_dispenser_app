import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientRequest extends StatefulWidget {
  final String userEmail; 
  const PatientRequest({super.key, required this.userEmail});

  @override
  State<PatientRequest> createState() => _PatientRequestState();
}

class _PatientRequestState extends State<PatientRequest> {
  final TextEditingController _targetEmailController = TextEditingController();
  String patientName = "";
  bool isLoading = false;

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
      debugPrint("Error fetching name: $e");
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
      _showSnackBar("You cannot request your own account.", Colors.red);
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Check if already linked (Checking BOTH possible keys)
      var existingConn = await FirebaseFirestore.instance
          .collection('connections')
          .where('patientEmail', isEqualTo: myEmail)
          .get();

      bool alreadyLinked = existingConn.docs.any((doc) {
        var data = doc.data();
        return data['caregiverEmail'] == targetEmail || data['healthcareEmail'] == targetEmail;
      });

      if (alreadyLinked) {
        _showSnackBar("You are already linked to this profile.", Colors.blue);
        setState(() => isLoading = false);
        return;
      }

      // 2. AUTO-ACCEPT HANDSHAKE: Check if target already sent a request to ME
      var incomingReq = await FirebaseFirestore.instance
          .collection('requests')
          .where('senderEmail', isEqualTo: targetEmail)
          .where('receiverEmail', isEqualTo: myEmail)
          .get();

      if (incomingReq.docs.isNotEmpty) {
        String senderRole = incomingReq.docs.first.get('senderRole') ?? "";

        // Establish connection using correct role key
        Map<String, dynamic> connectionData = {
          "patientEmail": myEmail,
          "connectedAt": FieldValue.serverTimestamp(),
        };

        if (senderRole.contains("Healthcare")) {
          connectionData["healthcareEmail"] = targetEmail;
        } else {
          connectionData["caregiverEmail"] = targetEmail;
        }

        await FirebaseFirestore.instance.collection('connections').add(connectionData);

        // Delete the redundant request
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(incomingReq.docs.first.id)
            .delete();

        _showSnackBar("Handshake complete! Connection established.", Colors.teal);
        if (mounted) Navigator.pop(context);
        return;
      }

      // 3. Verify target role and send outgoing request
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        _showSnackBar("No registered user found with this email.", Colors.red);
      } else {
        var userDoc = userQuery.docs.first;
        String role = userDoc.get('role');

        if (role == 'Caregiver' || role == 'Healthcare\nProvider') {
          // Check for pending outgoing request
          var pending = await FirebaseFirestore.instance
              .collection('requests')
              .where('senderEmail', isEqualTo: myEmail)
              .where('receiverEmail', isEqualTo: targetEmail)
              .get();

          if (pending.docs.isNotEmpty) {
            _showSnackBar("A request is already pending for this user.", Colors.orange);
          } else {
            // Send request
            await FirebaseFirestore.instance.collection('requests').add({
              "senderEmail": myEmail,
              "senderName": patientName,
              "receiverEmail": targetEmail,
              "senderRole": "Patient",
              "requestText": "$patientName ($myEmail) wants to link with you.",
              "status": "pending",
              "createdAt": FieldValue.serverTimestamp(),
            });

            _showSnackBar("Request sent to $targetEmail ($role).", Colors.green);
            if (mounted) Navigator.pop(context);
          }
        } else {
          _showSnackBar("Patients can only link with Caregivers or Doctors.", Colors.orange);
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
        title: const Text("Link New Provider", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Secure Connection", 
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
            const SizedBox(height: 10),
            const Text(
              "Add a caregiver or doctor to allow them to monitor your medication logs and receive hardware alerts.",
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 35),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _targetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Provider Email",
                      hintText: "Enter email address",
                      prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF1A3B70)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Send Link Request", 
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