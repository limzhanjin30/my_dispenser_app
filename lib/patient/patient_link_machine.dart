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
  bool _isProcessing = true;
  String? _currentlyLinkedMachineId;

  @override
  void initState() {
    super.initState();
    _checkCurrentLinkStatus();
  }

  Future<void> _checkCurrentLinkStatus() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        setState(() {
          _currentlyLinkedMachineId = userQuery.docs.first.data()['linkedMachineId'];
        });
      }
    } catch (e) {
      _showMsg("Error checking link status: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- LOGIC: LINK MACHINE (Strict 1-to-1 Checks & Full-Schema Initialization) ---
  Future<void> _handleLinkMachine() async {
    String serial = _serialController.text.trim().toUpperCase();
    if (serial.isEmpty) {
      _showMsg("Please enter a valid Serial Number", Colors.red);
      return;
    }

    setState(() => _isProcessing = true);
    final String cleanEmail = widget.userEmail.trim().toLowerCase();
    String patientFullName = "Patient";

    try {
      // 1. Fetch the patient's full name from the users collection first
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        patientFullName = userQuery.docs.first.data()['name'] ?? "Patient";
      } else {
        _showMsg("User profile mismatch error.", Colors.red);
        setState(() => _isProcessing = false);
        return;
      }

      // 2. Check if this machine is ALREADY claimed by another active user session
      var machineClaimedCheck = await FirebaseFirestore.instance
          .collection('users')
          .where('linkedMachineId', isEqualTo: serial)
          .limit(1)
          .get();

      if (machineClaimedCheck.docs.isNotEmpty) {
        String occupant = machineClaimedCheck.docs.first.data()['email'] ?? "another user";
        if (occupant != cleanEmail) {
          _showMsg("Link Failed: This machine is already linked to another patient", Colors.red);
          setState(() => _isProcessing = false);
          return;
        }
      }

      // 3. Initialize or Update the Virtual Machine Document Structure
      var machineDoc = await FirebaseFirestore.instance.collection('machines').doc(serial).get();

      if (!machineDoc.exists) {
        // 🎯 UPDATED: Added boxOpenTime initialization for tamper and anomaly diagnostics tracking
        List<Map<String, dynamic>> initialSlots = List.generate(3, (index) => {
          "slot": index + 1,
          "status": "Empty",
          "medDetails": "",
          "times": "",
          "startDate": "",
          "endDate": "",
          "frequency": "Everyday",
          "mealCondition": "After Meal",
          "isLocked": false,
          "isDone": false,
          "adherenceStatus": "Upcoming",
          "lastTakenDate": "",
          "lastTakenTime": "",
          "singleDoseWeight": 0.0,
          "boxOpenTime": "",
          "boxCloseTime": "", // 👈 Telemetry tracking baseline for unauthorized entries
          "remainingDays": 0, // 👈 Add this field initialized to 0
        });
        
        // Save the complete schema payload straight down to the root level of the doc
        await FirebaseFirestore.instance.collection('machines').doc(serial).set({
          'machineId': serial,
          'linkedPatientEmail': cleanEmail,      
          'linkedPatientName': patientFullName,   
          'slots': initialSlots,
          'adherenceHistory': [],                 
          
          // REAL-TIME LOAD CELL TRACKING VARS ADDED TO ROOT DOCUMENT DIRECTLY
          'totalWeight': 0.0,                     // Real-time mass from HX711 Load Cell
          'hardwareCommand': "Online",            // Handshake directive for ESP32-C3
          'lastRefilledSlot': 0,                  // Evaluates past physical actions
          
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // If the machine document framework already exists, cleanly update its root ownership contexts
        await FirebaseFirestore.instance.collection('machines').doc(serial).update({
          'linkedPatientEmail': cleanEmail,
          'linkedPatientName': patientFullName,
          'hardwareCommand': "Online", // Reset to standard state upon fresh coupling
        });
      }

      // 4. Update core patient profile reference map pointer
      await userQuery.docs.first.reference.update({
        'linkedMachineId': serial,
      });

      _showMsg("Machine Connected Successfully!", Colors.teal);
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail)),
        );
      }
    } catch (e) {
      _showMsg("Linking failed: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- LOGIC: UNLINK MACHINE (Performs bidirectional data reset safety cycles) ---
  Future<void> _handleUnlinkMachine() async {
    if (_currentlyLinkedMachineId == null) return;
    setState(() => _isProcessing = true);
    
    final String machineToClear = _currentlyLinkedMachineId!;

    try {
      // 1. Strip root metadata ownership locks off from the target hardware machine document
      var machineDoc = await FirebaseFirestore.instance.collection('machines').doc(machineToClear).get();
      if (machineDoc.exists) {
        await FirebaseFirestore.instance.collection('machines').doc(machineToClear).update({
          'linkedPatientEmail': FieldValue.delete(),
          'linkedPatientName': FieldValue.delete(),
          'hardwareCommand': "UNLINKED",
        });
      }

      // 2. Clear pointer from user profile document context references
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        await userQuery.docs.first.reference.update({
          'linkedMachineId': FieldValue.delete(),
        });

        _showMsg("Machine Unlinked Successfully.", Colors.blueGrey);
        setState(() {
          _currentlyLinkedMachineId = null;
          _serialController.clear();
        });
      }
    } catch (e) {
      _showMsg("Unlinking failed: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text("Hardware Manager", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail))),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_currentlyLinkedMachineId != null) ...[
                    const Icon(Icons.phonelink_setup, size: 80, color: Colors.green),
                    const SizedBox(height: 20),
                    const Text("Active Connection", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.developer_board, color: Colors.blueGrey, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            _currentlyLinkedMachineId!,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "To bind a different device terminal, you must safely disconnect your current session first.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: OutlinedButton.icon(
                        onPressed: _handleUnlinkMachine,
                        icon: const Icon(Icons.link_off),
                        label: const Text("Unlink Device Terminal", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  ] else ...[
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
                        onPressed: _handleLinkMachine,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A3B70),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Link Machine", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}