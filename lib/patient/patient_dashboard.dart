import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'patient_schedule.dart'; 
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
  Map<String, dynamic>? nextDose;
  List<dynamic> todaySchedule = [];
  bool _isLoading = true;
  bool _isProcessingTaken = false;
  bool _showRefillAlert = false; 

  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _fetchUserAndMachineData();
  }

  void _initAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // --- DATABASE: CONFIRM DOSE & HANDLE COURSE COMPLETION ---
  Future<void> _markAsTaken() async {
    if (nextDose == null || linkedMachineId == null) return;
    setState(() => _isProcessingTaken = true);

    // Declare variables here so they are accessible throughout the whole function scope
    bool isLate = false;
    bool isFinalDay = false;

    try {
      final String machineId = linkedMachineId!;
      final int targetSlot = nextDose!['slot'];
      final DateTime now = DateTime.now();
      final DateTime todayMidnight = DateTime(now.year, now.month, now.day);
      final DateTime scheduledTime = nextDose!['fullTime'];
      
      // Calculate 'isLate' here
      isLate = now.isAfter(scheduledTime.add(const Duration(minutes: 30)));
      String finalAdherenceStatus = isLate ? "Late" : "Taken";

      DocumentSnapshot machineDoc = await FirebaseFirestore.instance.collection('machines').doc(machineId).get();

      if (machineDoc.exists) {
        List<dynamic> slots = List.from(machineDoc.get('slots'));
        for (int i = 0; i < slots.length; i++) {
          if (slots[i]['slot'] == targetSlot) {
            // Check if this is the final day
            DateTime endDate = DateTime.parse(slots[i]['endDate']);
            isFinalDay = todayMidnight.isAtSameMomentAs(endDate) || todayMidnight.isAfter(endDate);

            if (isFinalDay) {
              // LOGIC: Change status to "Finished" so record remains but hardware is released
              slots[i]['status'] = "Finished";
              slots[i]['isLocked'] = false; 
              slots[i]['isDone'] = true; 
              slots[i]['lastTakenDate'] = DateFormat('yyyy-MM-dd').format(now);
              slots[i]['lastTakenTime'] = DateFormat('hh:mm a').format(now);
              slots[i]['adherenceStatus'] = finalAdherenceStatus;
            } else {
              // COURSE CONTINUES
              slots[i]['isDone'] = true; 
              slots[i]['isLocked'] = false; 
              slots[i]['lastTakenDate'] = DateFormat('yyyy-MM-dd').format(now); 
              slots[i]['lastTakenTime'] = DateFormat('hh:mm a').format(now); 
              slots[i]['adherenceStatus'] = finalAdherenceStatus;
            }
            break; // Exits loop, but isFinalDay/isLate are still saved
          }
        }
        
        await FirebaseFirestore.instance.collection('machines').doc(machineId).update({'slots': slots});
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Dose confirmed. ${isFinalDay ? 'Course Completed!' : ''}"), 
              backgroundColor: isLate ? Colors.orange : Colors.teal,
              duration: const Duration(seconds: 2),
            )
          );
        }
      }
    } catch (e) {
      debugPrint("Confirm Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessingTaken = false);
    }
  }

  // --- DATABASE: FETCH & MONITOR ---
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
          FirebaseFirestore.instance.collection('machines').doc(linkedMachineId).snapshots().listen((snap) {
            if (snap.exists && mounted) {
              _processMachineSlots(snap.data()!['slots'] ?? []);
            }
          });
        } else {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- CORE LOGIC: PROCESS TODAY + "FINISHED" SLOTS ---
  void _processMachineSlots(List<dynamic> slots) {
    DateTime now = DateTime.now();
    DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    String todayStr = DateFormat('yyyy-MM-dd').format(now);
    
    bool needsAutoExpirySync = false;
    List<Map<String, dynamic>> todayScheduleList = [];
    final String myEmail = widget.userEmail.trim().toLowerCase();

    for (int i = 0; i < slots.length; i++) {
      var slot = slots[i];
      if (slot['status'] == "Empty") continue;

      // 1. AUTO-EXPIRY: If date passed, mark as "Finished" instead of "Empty"
      DateTime endDate = DateTime.parse(slot['endDate'] ?? todayStr);
      if (now.isAfter(endDate.add(const Duration(days: 1))) && slot['status'] == "Occupied") {
        slots[i]['status'] = "Finished";
        slots[i]['isLocked'] = false;
        needsAutoExpirySync = true;
      }

      if (slot['patientEmail'] != myEmail) continue;

      // Filter for Today's Alarms
      DateTime start = DateTime.parse(slot['startDate'] ?? todayStr);
      if (todayMidnight.isBefore(DateTime(start.year, start.month, start.day)) || todayMidnight.isAfter(endDate)) continue;

      bool isDoneToday = slot['lastTakenDate'] == todayStr || slot['status'] == "Finished";
      List<String> times = List<String>.from(slot['times'] ?? []);

      for (var t in times) {
        todayScheduleList.add({
          "name": slot['medDetails'] ?? "Medication",
          "fullTime": _parseTimeString(t, todayMidnight),
          "displayTime": t,
          "isDone": isDoneToday,
          "adherenceStatus": slot['adherenceStatus'] ?? "Taken",
          "slot": slot['slot'],
          "status": slot['status'], // Track if Occupied or Finished
          "isPhysicallyEmpty": slot['isDone'] ?? false, 
        });
      }
    }

    todayScheduleList.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));

    // NEXT DOSE: First dose that is not done and status is still "Occupied"
    Map<String, dynamic>? upcoming;
    try {
      upcoming = todayScheduleList.firstWhere((dose) => dose['isDone'] == false && dose['status'] == "Occupied");
    } catch (e) { upcoming = null; }

    // REFILL ALERT: Only for active "Occupied" slots
    bool refillWarning = false;
    if (upcoming != null && upcoming['isPhysicallyEmpty'] == true) {
      if (upcoming['fullTime'].difference(now).inMinutes <= 60) {
        refillWarning = true;
      }
    }

    if (needsAutoExpirySync && linkedMachineId != null) {
      FirebaseFirestore.instance.collection('machines').doc(linkedMachineId).update({'slots': slots});
    }

    if (upcoming != null && upcoming['fullTime'].difference(now).inMinutes <= 30) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }

    if (mounted) {
      setState(() {
        todaySchedule = todayScheduleList;
        nextDose = upcoming;
        _showRefillAlert = refillWarning;
        _isLoading = false;
      });
    }
  }

  DateTime _parseTimeString(String timeStr, DateTime ref) {
    DateTime p = DateFormat("hh:mm a").parse(timeStr);
    return DateTime(ref.year, ref.month, ref.day, p.hour, p.minute);
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
        leading: IconButton(icon: const Icon(Icons.logout, color: Colors.black87, size: 20), onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false)),
        title: const Text("Patient Dashboard", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
        : RefreshIndicator(
          onRefresh: _fetchUserAndMachineData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                if (_showRefillAlert) _buildRefillWarningBanner(),
                const SizedBox(height: 10),
                linkedMachineId == null ? _buildLinkMachinePrompt() : _buildNextDoseCard(),
                const SizedBox(height: 30),
                const Text("Today's Schedule", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
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

  Widget _buildRefillWarningBanner() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(15), margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
        const SizedBox(width: 15),
        const Expanded(child: Text("BIN REFILL REQUIRED: Hardware detected empty bin for next dose.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
      ]),
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

  Widget _buildNextDoseCard() {
    if (nextDose == null) return _buildStaticInfoCard("Schedule Complete", "All confirmed.");
    DateTime sched = nextDose!['fullTime'];
    bool canPress = DateTime.now().isAfter(sched.subtract(const Duration(minutes: 30)));
    bool overdue = DateTime.now().isAfter(sched.add(const Duration(minutes: 30)));

    return Container(
      width: double.infinity, padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: overdue ? Colors.red.shade50 : (canPress ? const Color(0xFF1A3B70) : Colors.white), 
        borderRadius: BorderRadius.circular(25), border: overdue ? Border.all(color: Colors.red.shade200, width: 2) : Border.all(color: Colors.grey.shade100),
      ),
      child: Column(children: [
        Text(overdue ? "OVERDUE" : (canPress ? "DUE NOW" : "UPCOMING:"), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: canPress ? Colors.white70 : Colors.blueGrey)),
        const SizedBox(height: 5),
        Text(_getCountdownText(sched), style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: canPress ? Colors.white : const Color(0xFF1A3B70))),
        Text("${nextDose!['name']} (Bin ${nextDose!['slot']})", style: TextStyle(color: canPress ? Colors.white : Colors.grey, fontSize: 16)),
        if (canPress) ...[
          const SizedBox(height: 25),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _isProcessingTaken ? null : _markAsTaken, 
            style: ElevatedButton.styleFrom(backgroundColor: overdue ? Colors.red : Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 15)), 
            child: _isProcessingTaken ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("TAKEN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )),
        ]
      ]),
    );
  }

  Widget _buildScheduleList() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: todaySchedule.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade50),
        itemBuilder: (context, index) {
          final item = todaySchedule[index];
          String status = "UPCOMING"; Color color = Colors.blueGrey;
          if (item['isDone']) {
            status = item['adherenceStatus'].toString().toUpperCase();
            color = item['adherenceStatus'] == "Late" ? Colors.orange : Colors.green;
          } else if (DateTime.now().isAfter(item['fullTime'].add(const Duration(minutes: 30)))) { 
            status = "MISSED"; color = Colors.red; 
          }

          return ListTile(
            leading: Icon(item['isDone'] ? Icons.check_circle : (status == "MISSED" ? Icons.error : Icons.radio_button_off), color: color),
            title: Text(item['displayTime'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text("${item['name']} ${item['status'] == 'Finished' ? '(Completed Course)' : ''}"), // UI hint for finished course
            trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10))),
          );
        },
      ),
    );
  }

  Widget _buildStaticInfoCard(String t, String s) => Container(width: double.infinity, padding: const EdgeInsets.all(35), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Column(children: [const Icon(Icons.verified_user_outlined, color: Colors.green, size: 45), const SizedBox(height: 15), Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(s, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13))]));
  Widget _buildLinkMachinePrompt() => Container(width: double.infinity, padding: const EdgeInsets.all(30), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)), child: Column(children: [const Icon(Icons.link_off, color: Colors.orange, size: 50), const SizedBox(height: 15), const Text("No Machine", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PatientLinkMachine(userEmail: widget.userEmail))), child: const Text("Link"))]));
}