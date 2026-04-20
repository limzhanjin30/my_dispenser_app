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

class _PatientDashboardState extends State<PatientDashboard> with TickerProviderStateMixin {
  String fullName = "Patient";
  String? linkedMachineId;
  
  List<Map<String, dynamic>> _availableDoses = [];
  Map<String, dynamic>? _selectedDose; 

  List<dynamic> todaySchedule = [];
  bool _isLoading = true;
  bool _isProcessingTaken = false;

  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _fetchUserAndMachineData();
  }

  void _initAnimation() {
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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
    } catch (e) { debugPrint("PIN Error: $e"); }

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
                const Text("Enter PIN to unlock medication bin.", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                  if (pinController.text == correctPin) Navigator.pop(context, true);
                  else setDialogState(() => errorText = "Incorrect PIN");
                },
                child: const Text("Unlock Bin", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    ) ?? false;
  }

  // --- DATABASE: MARK SPECIFIC DOSE LOG AS TAKEN ---
  Future<void> _markAsTaken() async {
    if (_selectedDose == null || linkedMachineId == null) return;
    
    final doseToLog = _selectedDose!;
    bool isAuthorized = await _promptForDispenserPin();
    if (!isAuthorized) return;

    setState(() => _isProcessingTaken = true);
    final DateTime now = DateTime.now();
    final String todayStr = DateFormat('yyyy-MM-dd').format(now);
    final String tomorrowStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));
    
    bool isLate = now.isAfter(doseToLog['fullTime'].add(const Duration(minutes: 30)));
    String finalStatus = isLate ? "Late" : "Taken";

    try {
      // 1. UPDATE THE LOG FOR TODAY
      var logQuery = await FirebaseFirestore.instance
          .collection('adherence_logs')
          .where('patientEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .where('slot', isEqualTo: doseToLog['slot'])
          .where('date', isEqualTo: todayStr)
          .where('times', arrayContains: doseToLog['displayTime']) 
          .limit(1)
          .get();

      if (logQuery.docs.isNotEmpty) {
        await logQuery.docs.first.reference.update({
          "adherenceStatus": finalStatus,
          "takenTime": DateFormat('hh:mm a').format(now),
          "lastTakenTime": DateFormat('hh:mm a').format(now),
          "isDone": true,
          "timestamp": FieldValue.serverTimestamp(),
        });
      }

      // 2. NEW LOOK-AHEAD LOGIC: Check if there is medicine tomorrow
      var tomorrowLogs = await FirebaseFirestore.instance
          .collection('adherence_logs')
          .where('patientEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .where('slot', isEqualTo: doseToLog['slot'])
          .where('date', isEqualTo: tomorrowStr)
          .limit(1)
          .get();

      bool hasDoseTomorrow = tomorrowLogs.docs.isNotEmpty;

      // 3. UPDATE PHYSICAL MACHINE STATE
      final String machineId = linkedMachineId!;
      DocumentSnapshot machineDoc = await FirebaseFirestore.instance.collection('machines').doc(machineId).get();

      if (machineDoc.exists) {
        List<dynamic> slots = List.from(machineDoc.get('slots'));
        for (int i = 0; i < slots.length; i++) {
          if (slots[i]['slot'] == doseToLog['slot']) {
            if (hasDoseTomorrow) {
              // CONTINUE COURSE: Show "Awaiting Refill" in Inventory
              slots[i]['isDone'] = true; 
              slots[i]['isLocked'] = false; 
              slots[i]['adherenceStatus'] = finalStatus;
            } else {
              // FINISH COURSE: Set slot to Empty (removes from Inventory)
              slots[i]['status'] = "Empty";
              slots[i]['isDone'] = false;
              slots[i]['isLocked'] = false;
              slots[i]['medDetails'] = "";
              slots[i]['patientEmail'] = "";
              slots[i]['times'] = [];
            }
            slots[i]['lastTakenDate'] = todayStr;
            slots[i]['lastTakenTime'] = DateFormat('hh:mm a').format(now);
            break;
          }
        }
        await FirebaseFirestore.instance.collection('machines').doc(machineId).update({'slots': slots});
      }
      
      setState(() => _selectedDose = null);
      _showSuccessSnackBar("${doseToLog['name']} confirmed!");
      
    } catch (e) {
      debugPrint("Update Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessingTaken = false);
    }
  }

  void _showErrorSnackBar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  void _showSuccessSnackBar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.teal));

  // --- DATA FETCHING ---
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
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _processGranularLogs(List<QueryDocumentSnapshot> logs) {
    DateTime now = DateTime.now();
    DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    List<Map<String, dynamic>> schedule = [];
    List<Map<String, dynamic>> availableToTake = [];

    for (var doc in logs) {
      var data = doc.data() as Map<String, dynamic>;
      if (data['finalStatus'] == "Course Terminated") continue;

      String timeStr = (data['times'] is List && (data['times'] as List).isNotEmpty) 
          ? (data['times'] as List).first 
          : "00:00 AM";

      DateTime fullTime = _parseTimeString(timeStr, todayMidnight);
      String status = data['adherenceStatus'] ?? "Upcoming";
      bool isDone = (status.toLowerCase() == "taken" || status.toLowerCase() == "late");

      var doseInfo = {
        "name": data['medDetails'] ?? data['medName'] ?? "Medicine", 
        "fullTime": fullTime, "displayTime": timeStr, "isDone": isDone, 
        "adherenceStatus": status, "slot": data['slot'],
      };
      
      schedule.add(doseInfo);
      if (!isDone && now.isAfter(fullTime.subtract(const Duration(minutes: 30)))) {
        availableToTake.add(doseInfo);
      }
    }

    schedule.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));
    availableToTake.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));
    
    if (availableToTake.isNotEmpty) _pulseController.repeat(reverse: true); 
    else _pulseController.stop();

    if (mounted) {
      setState(() { todaySchedule = schedule; _availableDoses = availableToTake; _isLoading = false; });
    }
  }

  DateTime _parseTimeString(String timeStr, DateTime ref) {
    try {
      DateTime p = DateFormat("hh:mm a").parse(timeStr);
      return DateTime(ref.year, ref.month, ref.day, p.hour, p.minute);
    } catch (e) { return ref; }
  }

  String _getCountdownText(DateTime target) {
    Duration diff = target.difference(DateTime.now());
    if (diff.isNegative) return "OVERDUE";
    return "${diff.inHours}h ${diff.inMinutes % 60}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.logout, size: 20), onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false)),
        title: const Text("Patient Dashboard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _fetchUserAndMachineData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildHeader(),
                const SizedBox(height: 25),
                linkedMachineId == null ? _buildLinkMachinePrompt() : _buildSelectionSection(),
                const SizedBox(height: 35),
                const Text("Today's Medication Plan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                const SizedBox(height: 15),
                _buildScheduleList(),
                const SizedBox(height: 30),
              ]),
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

  Widget _buildSelectionSection() {
    if (_availableDoses.isEmpty) {
      return Container(width: double.infinity, padding: const EdgeInsets.all(35), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Column(children: [const Icon(Icons.verified, color: Colors.green, size: 45), const SizedBox(height: 15), const Text("All Caught Up!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Text("No doses are currently due.", style: TextStyle(color: Colors.grey, fontSize: 13))]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Select medication to take now:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableDoses.length,
            itemBuilder: (context, index) {
              final dose = _availableDoses[index];
              bool isSelected = _selectedDose != null && _selectedDose!['slot'] == dose['slot'] && _selectedDose!['displayTime'] == dose['displayTime'];
              return GestureDetector(
                onTap: () => setState(() => _selectedDose = dose),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1A3B70) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isSelected ? Colors.blueAccent : Colors.grey.shade200, width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dose['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                      const SizedBox(height: 4),
                      Text("Bin ${dose['slot']}", style: TextStyle(fontSize: 11, color: isSelected ? Colors.white70 : Colors.grey)),
                      Text(dose['displayTime'], style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.blueGrey)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 25),
        if (_selectedDose != null) _buildActionCard() else _buildInstructionsCard(),
      ],
    );
  }

  Widget _buildActionCard() {
    DateTime sched = _selectedDose!['fullTime'];
    bool overdue = DateTime.now().isAfter(sched.add(const Duration(minutes: 30)));
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(color: overdue ? Colors.red.shade50 : const Color(0xFF1A3B70), borderRadius: BorderRadius.circular(25), border: overdue ? Border.all(color: Colors.red.shade200, width: 2) : null),
        child: Column(children: [
          Text(overdue ? "OVERDUE" : "DUE NOW", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 8),
          Text(_getCountdownText(sched), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
          Text("Ready to take ${_selectedDose!['name']}", style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 25),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _isProcessingTaken ? null : _markAsTaken, 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
            child: _isProcessingTaken ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("PRESS TO CONFIRM TAKEN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )),
        ]),
      ),
    );
  }

  Widget _buildInstructionsCard() => Container(width: double.infinity, padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.grey.shade100)), child: Column(children: [Icon(Icons.touch_app, size: 40, color: Colors.grey[400]), const SizedBox(height: 10), const Text("Select a medicine to confirm intake", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))]));

  Widget _buildScheduleList() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
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
            trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(statusStr, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10))),
          );
        },
      ),
    );
  }

  Widget _buildLinkMachinePrompt() => Container(width: double.infinity, padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Column(children: [const Icon(Icons.link_off, color: Colors.orange, size: 50), const SizedBox(height: 15), const Text("No Hub Found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PatientLinkMachine(userEmail: widget.userEmail))), child: const Text("Link Device"))]));
}