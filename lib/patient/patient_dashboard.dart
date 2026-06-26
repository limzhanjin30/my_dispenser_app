import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'patient_link_machine.dart'; 

class PatientDashboard extends StatefulWidget {
  final String userEmail;
  const PatientDashboard({super.key, required this.userEmail});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  String fullName = "Patient";
  String? linkedMachineId;
  
  List<Map<String, dynamic>> _availableFallbackDoses = [];
  Map<String, dynamic>? _selectedDose; 

  List<dynamic> todaySchedule = [];
  bool _isLoading = true;
  bool _isProcessingFallback = false;

  @override
  void initState() {
    super.initState();
    _fetchUserAndMachineData();
  }

  // --- PLAN B FALLBACK LOGIC: MANUAL CONFIRMATION BYPASS ---
  Future<bool> _promptForDispenserPin() async {
    final TextEditingController pinController = TextEditingController();
    String? errorText;
    String? correctPin;

    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();
      
      if (userSnap.docs.isNotEmpty) {
        correctPin = userSnap.docs.first.data()['dispenserPin'];
      }
    } catch (e) { 
      debugPrint("PIN Error: $e"); 
    }

    if (correctPin == null) {
      _showErrorSnackBar("Please set a Dispenser PIN in Settings first.");
      return false;
    }

    return await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Verify Dispenser PIN", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Enter PIN to override hardware log manually.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 25),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(letterSpacing: 20, fontSize: 26, fontWeight: FontWeight.bold),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: InputDecoration(
                    errorText: errorText,
                    hintText: "••••",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70)),
                onPressed: () {
                  if (pinController.text == correctPin) {
                    Navigator.pop(context, true);
                  } else {
                    setDialogState(() => errorText = "Incorrect PIN");
                  }
                },
                child: const Text("Verify", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    ) ?? false;
  }

  Future<void> _markAsTakenManualFallback() async {
    if (_selectedDose == null || linkedMachineId == null) return;
    
    bool isAuthorized = await _promptForDispenserPin();
    if (!isAuthorized) return;

    setState(() => _isProcessingFallback = true);
    final doseToLog = _selectedDose!;
    final DateTime now = DateTime.now();
    final String todayStr = DateFormat('yyyy-MM-dd').format(now);
    
    bool isLate = now.isAfter(doseToLog['fullTime'].add(const Duration(minutes: 30)));
    String finalStatus = isLate ? "Late" : "Taken";

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 1. Force state transition inside adherence_logs
      var logQuery = await FirebaseFirestore.instance
          .collection('adherence_logs')
          .where('patientEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .where('slot', isEqualTo: doseToLog['slot'])
          .where('date', isEqualTo: todayStr)
          .where('isDone', isEqualTo: false)
          .limit(1)
          .get();

      if (logQuery.docs.isNotEmpty) {
        batch.update(logQuery.docs.first.reference, {
          "adherenceStatus": finalStatus,
          "lastTakenTime": DateFormat('hh:mm a').format(now),
          "lastTakenDate": todayStr,
          "isDone": true,
          "timestamp": FieldValue.serverTimestamp(),
        });
      }

      // 2. Synchronize variable parameters up to hardware doc level
      DocumentSnapshot machineDoc = await FirebaseFirestore.instance.collection('machines').doc(linkedMachineId!).get();
      if (machineDoc.exists) {
        List<dynamic> slots = List.from(machineDoc.get('slots') ?? []);
        for (int i = 0; i < slots.length; i++) {
          if (slots[i]['slot'] == doseToLog['slot']) {
            slots[i]['isDone'] = true;
            slots[i]['isLocked'] = false;
            slots[i]['lastTakenDate'] = todayStr;
            slots[i]['lastTakenTime'] = DateFormat('hh:mm a').format(now);
            slots[i]['adherenceStatus'] = finalStatus;
            break;
          }
        }
        batch.update(machineDoc.reference, {'slots': slots});
      }

      await batch.commit();
      setState(() => _selectedDose = null);
      _showSuccessSnackBar("Manual override saved for ${doseToLog['name']}.");
    } catch (e) {
      _showErrorSnackBar("Fallback override execution failed.");
    } finally {
      if (mounted) setState(() => _isProcessingFallback = false);
    }
  }

  void _showErrorSnackBar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  void _showSuccessSnackBar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.teal));

  // --- DATA RECOVERY PIPELINE ---
  Future<void> _fetchUserAndMachineData() async {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      var userSnapshot = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: cleanEmail).limit(1).get();
      if (userSnapshot.docs.isNotEmpty) {
        var userData = userSnapshot.docs.first.data();
        fullName = userData['name'] ?? "Patient";
        linkedMachineId = userData['linkedMachineId'];

        if (linkedMachineId != null) {
          String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          
          FirebaseFirestore.instance.collection('adherence_logs')
              .where('patientEmail', isEqualTo: cleanEmail)
              .where('date', isEqualTo: todayStr)
              .snapshots().listen((logSnap) {
                if (mounted) _processGranularLogs(logSnap.docs);
              });
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  void _processGranularLogs(List<QueryDocumentSnapshot> logs) {
    DateTime now = DateTime.now();
    DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    List<Map<String, dynamic>> schedule = [];
    List<Map<String, dynamic>> fallbackAvailable = [];

    for (var doc in logs) {
      var data = doc.data() as Map<String, dynamic>;
      if (data['finalStatus'] == "Course Terminated") continue;

      // Extract single string with structural fallback safety checks
      String timeStr = "00:00 AM";
      if (data['times'] != null) {
        if (data['times'] is String) {
          timeStr = data['times'];
        } else if (data['times'] is List && (data['times'] as List).isNotEmpty) {
          // Safe fallback case handling leftover arrays during DB migration
          timeStr = data['times'][0].toString();
        }
      }

      DateTime fullTime = _parseTimeString(timeStr, todayMidnight);
      String status = data['adherenceStatus'] ?? "Upcoming";
      bool isDone = (status.toLowerCase() == "taken" || status.toLowerCase() == "late" || data['isDone'] == true);

      var doseInfo = {
        "name": data['medDetails'] ?? data['medName'] ?? "Medicine", 
        "fullTime": fullTime, 
        "displayTime": timeStr, 
        "isDone": isDone, 
        "adherenceStatus": status, 
        "slot": data['slot'],
      };
      
      schedule.add(doseInfo);

      // Populate fallback selection if dose is missed/due and within valid timeframe
      if (!isDone && now.isAfter(fullTime.subtract(const Duration(minutes: 30)))) {
        fallbackAvailable.add(doseInfo);
      }
    }

    schedule.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));
    fallbackAvailable.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));
    
    if (mounted) {
      setState(() { 
        todaySchedule = schedule; 
        _availableFallbackDoses = fallbackAvailable;
        _isLoading = false; 
      });
    }
  }

  DateTime _parseTimeString(String timeStr, DateTime ref) {
    try {
      DateTime p = DateFormat("hh:mm a").parse(timeStr);
      return DateTime(ref.year, ref.month, ref.day, p.hour, p.minute);
    } catch (e) { 
      return ref; 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout, size: 20), 
          onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false)
        ),
        title: const Text("Patient Dashboard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _fetchUserAndMachineData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  _buildHeader(),
                  const SizedBox(height: 25),
                  linkedMachineId == null ? _buildLinkMachinePrompt() : _buildFallbackSelectionSection(),
                  const SizedBox(height: 35),
                  const Text("Today's Medication Plan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                  const SizedBox(height: 15),
                  _buildScheduleList(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 0, role: "Patient", userEmail: widget.userEmail),
    );
  }

  Widget _buildHeader() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Hi, $fullName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
        Text(DateFormat('EEEE, MMM d').format(DateTime.now()), style: const TextStyle(color: Colors.grey, fontSize: 14)),
      ]),
      Icon(Icons.wifi, color: linkedMachineId != null ? Colors.green : Colors.grey, size: 20),
    ]);
  }

  Widget _buildFallbackSelectionSection() {
    if (_availableFallbackDoses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(35),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
        child: const Column(children: [
          Icon(Icons.verified, color: Colors.green, size: 45),
          SizedBox(height: 15),
          Text("All Caught Up!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(
            "The automated load cells are keeping track of your weights.", 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          )
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Plan B Fallback: Manual Confirmation Override", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableFallbackDoses.length,
            itemBuilder: (context, index) {
              final dose = _availableFallbackDoses[index];
              bool isSelected = _selectedDose != null && _selectedDose!['slot'] == dose['slot'] && _selectedDose!['displayTime'] == dose['displayTime'];
              return GestureDetector(
                onTap: () => setState(() => _selectedDose = isSelected ? null : dose),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.orange.shade800 : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isSelected ? Colors.orange : Colors.grey.shade200, width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dose['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                      Text("Slot ${dose['slot']}", style: TextStyle(fontSize: 11, color: isSelected ? Colors.white70 : Colors.grey)),
                      Text(dose['displayTime'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.orange.shade700)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_selectedDose != null) ...[
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.withOpacity(0.2))),
            child: Column(
              children: [
                const Text("Sensor out of sync or taken without dispensing?", style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                    onPressed: _isProcessingFallback ? null : _markAsTakenManualFallback,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    label: _isProcessingFallback 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("MANUALLY CONFIRM TAKEN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          )
        ],
      ],
    );
  }

  Widget _buildScheduleList() {
    if (todaySchedule.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const Center(child: Text("No medication logs scheduled for today.", style: TextStyle(color: Colors.grey, fontSize: 13))),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: ListView.separated(
        shrinkWrap: true, 
        physics: const NeverScrollableScrollPhysics(),
        itemCount: todaySchedule.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade50),
        itemBuilder: (context, index) {
          final item = todaySchedule[index];
          String statusStr = item['adherenceStatus'].toString().toUpperCase();
          if (!item['isDone']) {
            statusStr = DateTime.now().isAfter(item['fullTime'].add(const Duration(minutes: 30))) ? "MISSED" : "UPCOMING";
          }
          Color color = statusStr == "TAKEN" ? Colors.green : (statusStr == "MISSED" ? Colors.red : Colors.blueGrey);
          if (statusStr == "LATE") color = Colors.orange;

          return ListTile(
            leading: Icon(item['isDone'] ? Icons.check_circle : (statusStr == "MISSED" ? Icons.error : Icons.radio_button_off), color: color),
            title: Text(item['displayTime'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(item['name']),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), 
              child: Text(statusStr, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10))
            ),
          );
        },
      ),
    );
  }

  Widget _buildLinkMachinePrompt() => Container(width: double.infinity, padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Column(children: [const Icon(Icons.link_off, color: Colors.orange, size: 50), const SizedBox(height: 15), const Text("No Hub Found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 15), ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PatientLinkMachine(userEmail: widget.userEmail))), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("Link Device", style: TextStyle(color: Colors.white)))],),);
}