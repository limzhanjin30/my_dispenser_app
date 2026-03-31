import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'patient_dashboard.dart';

class PatientLinkMachine extends StatefulWidget {
  final String userEmail;
  const PatientLinkMachine({super.key, required this.userEmail});

  @override
  State<PatientLinkMachine> createState() => _PatientLinkMachineState();
}

class _PatientLinkMachineState extends State<PatientLinkMachine> {
  final TextEditingController _serialController = TextEditingController();
  bool _isLinking = false;

  Future<void> _handleLinkMachine() async {
    String serial = _serialController.text.trim().toUpperCase();
    if (serial.isEmpty) {
      _showMsg("Please enter a valid Serial Number", Colors.red);
      return;
    }

    setState(() => _isLinking = true);

    try {
      // 1. Check if the machine already exists in Firestore
      var machineDoc = await FirebaseFirestore.instance.collection('machines').doc(serial).get();

      if (!machineDoc.exists) {
        // Initialize a new "Virtual Machine" with 10 empty slots
        List<Map<String, dynamic>> initialSlots = List.generate(10, (index) => {
          "slot": index + 1,
          "status": "Empty",
          "patientEmail": "",
          "medDetails": "",
          "times": [],
          "startDate": "",
          "endDate": "",
          "frequency": "Everyday",
          "mealCondition": "After Meal",
          "isLocked": false,
          "isDone": false,
        });
        await FirebaseFirestore.instance.collection('machines').doc(serial).set({
          'machineId': serial,
          'slots': initialSlots,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // 2. Link the patient to this machine
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        await userQuery.docs.first.reference.update({
          'linkedMachineId': serial,
        });

        _showMsg("Machine Connected Successfully!", Colors.teal);
        
        // Return to dashboard
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail)),
          );
        }
      }
    } catch (e) {
      _showMsg("Linking failed: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(title: const Text("Link Hardware"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.settings_input_component, size: 80, color: Color(0xFF1A3B70)),
            const SizedBox(height: 20),
            const Text("Connect Your Machine", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text("Enter the unique serial number located on the bottom of your dispenser.", 
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            TextField(
              controller: _serialController,
              decoration: InputDecoration(
                hintText: "E.g. SMART-MED-101",
                prefixIcon: const Icon(Icons.qr_code_scanner),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton(
                onPressed: _isLinking ? null : _handleLinkMachine,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70)),
                child: _isLinking ? const CircularProgressIndicator(color: Colors.white) : const Text("Link Machine"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}