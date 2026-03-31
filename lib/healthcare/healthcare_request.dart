import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HealthcareRequest extends StatefulWidget {
  final String userEmail; // Current Doctor's email
  const HealthcareRequest({super.key, required this.userEmail});

  @override
  State<HealthcareRequest> createState() => _HealthcareRequestState();
}

class _HealthcareRequestState extends State<HealthcareRequest> {
  final TextEditingController _patientEmailController = TextEditingController();
  String fullName = "Healthcare Provider"; 
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchHealthcareName();
  }

  // Fetches Doctor's name from Firestore for the request text
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
      _showSnackBar("Please enter the patient's email address", Colors.orange);
      return;
    }

    if (targetEmail == myEmail) {
      _showSnackBar("You cannot request your own account.", Colors.red);
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Check if already linked using the healthcareEmail key
      var existingConn = await FirebaseFirestore.instance
          .collection('connections')
          .where('healthcareEmail', isEqualTo: myEmail)
          .where('patientEmail', isEqualTo: targetEmail)
          .get();

      if (existingConn.docs.isNotEmpty) {
        _showSnackBar("This patient is already in your clinical registry.", Colors.blue);
        setState(() => isLoading = false);
        return;
      }

      // 2. AUTO-ACCEPT HANDSHAKE: Check if patient already sent a request to this Doctor
      var incomingReq = await FirebaseFirestore.instance
          .collection('requests')
          .where('senderEmail', isEqualTo: targetEmail)
          .where('receiverEmail', isEqualTo: myEmail)
          .get();

      if (incomingReq.docs.isNotEmpty) {
        // Mutual handshake found: Establish connection using healthcareEmail key
        await FirebaseFirestore.instance.collection('connections').add({
          "healthcareEmail": myEmail, 
          "patientEmail": targetEmail,
          "connectedAt": FieldValue.serverTimestamp(),
        });

        // Clear the pending request
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(incomingReq.docs.first.id)
            .delete();

        _showSnackBar("Patient successfully added to your clinical panel!", Colors.teal);
        if (mounted) Navigator.pop(context);
        return;
      }

      // 3. Verify target is a Patient and send Clinical Request
      var patientQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .where('role', isEqualTo: 'Patient')
          .limit(1)
          .get();

      if (patientQuery.docs.isEmpty) {
        _showSnackBar("No registered patient found with this email.", Colors.red);
      } else {
        // Check for duplicate pending clinical requests
        var pending = await FirebaseFirestore.instance
            .collection('requests')
            .where('senderEmail', isEqualTo: myEmail)
            .where('receiverEmail', isEqualTo: targetEmail)
            .get();

        if (pending.docs.isNotEmpty) {
          _showSnackBar("Clinical request is already pending for this patient.", Colors.orange);
        } else {
          // Send request with senderRole as Healthcare Provider
          await FirebaseFirestore.instance.collection('requests').add({
            "senderEmail": myEmail,
            "senderName": fullName, 
            "receiverEmail": targetEmail,
            "senderRole": "Healthcare Provider", 
            "requestText": "Dr. $fullName is requesting clinical oversight of your dispenser logs.",
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp(),
          });

          _showSnackBar("Clinical request sent to $targetEmail.", Colors.green);
          if (mounted) Navigator.pop(context);
        }
      }
    } catch (e) {
      _showSnackBar("Database connection error.", Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("New Patient Request", 
          style: TextStyle(color: Color(0xFF1A3B70), fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Clinical Search", 
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
            const SizedBox(height: 10),
            const Text(
              "Enter the registered email of a patient to request access to their Smart Dispenser logs and adherence data.",
              style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 35),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _patientEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Patient Email",
                      hintText: "patient@example.com",
                      prefixIcon: const Icon(Icons.person_search_outlined, color: Color(0xFF1A3B70)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
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
                        elevation: 0,
                      ),
                      child: isLoading 
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Verify & Link Patient", 
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            _buildGuidanceBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidanceBox() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.1))),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 20),
          SizedBox(width: 12),
          Expanded(child: Text(
            "Patients must have an active account with the 'Patient' role. Successful links will appear in your 'Managed Patients' registry.",
            style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4),
          ))
        ],
      ),
    );
  }
}