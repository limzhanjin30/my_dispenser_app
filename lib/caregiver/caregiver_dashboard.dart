import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'caregiver_linked.dart';
import 'caregiver_schedule_editor.dart';

class CaregiverDashboard extends StatefulWidget {
  final String userEmail;
  const CaregiverDashboard({super.key, required this.userEmail});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  String fullName = "Caregiver";
  int _linkedPatientCount = 0;
  int _actionRequiredCount = 0; 
  List<Map<String, dynamic>> _machineActivityFeed = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupRealTimeSync();
  }

  void _setupRealTimeSync() {
    final String caregiverEmail = widget.userEmail.trim().toLowerCase();
    final DateTime now = DateTime.now();
    final String todayStr = DateFormat('yyyy-MM-dd').format(now);

    // 1. Fetch Caregiver Profile Name
    FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: caregiverEmail)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && mounted) {
        setState(() => fullName = snap.docs.first.get('name') ?? "Caregiver");
      }
    });

    // 2. Listen to Connections then fetch Daily Logs
    FirebaseFirestore.instance
        .collection('connections')
        .where('caregiverEmail', isEqualTo: caregiverEmail)
        .snapshots()
        .listen((connectionSnap) async {
      
      List<String> patientEmails = connectionSnap.docs.map((d) => d.get('patientEmail').toString().toLowerCase().trim()).toList();
      
      if (patientEmails.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _linkedPatientCount = 0; _machineActivityFeed = []; });
        return;
      }

      // Sync Adherence Logs for all linked patients FOR TODAY
      FirebaseFirestore.instance
          .collection('adherence_logs')
          .where('patientEmail', whereIn: patientEmails)
          .where('date', isEqualTo: todayStr)
          .snapshots()
          .listen((logSnap) async {
            
        int urgentActions = 0;
        List<Map<String, dynamic>> activityItems = [];

        // --- HARDWARE LOOKUP: Get bin statuses for all patients ---
        Map<String, List<dynamic>> hardwareStates = {};
        for (String pEmail in patientEmails) {
          var uSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: pEmail).limit(1).get();
          if (uSnap.docs.isNotEmpty) {
            String? mId = uSnap.docs.first.get('linkedMachineId');
            if (mId != null) {
              var mSnap = await FirebaseFirestore.instance.collection('machines').doc(mId).get();
              if (mSnap.exists) hardwareStates[pEmail] = mSnap.get('slots') ?? [];
            }
          }
        }

        for (var doc in logSnap.docs) {
          var data = doc.data();
          if (data['finalStatus'] == "Course Terminated") continue;

          String status = (data['adherenceStatus'] ?? "Upcoming").toString().toLowerCase().trim();
          String med = data['medName'] ?? data['medDetails'] ?? "Medicine";
          String schedTime = (data['times'] is List && (data['times'] as List).isNotEmpty) ? (data['times'] as List).first : "--:--";
          String takenAt = data['takenTime'] ?? data['lastTakenTime'] ?? "";
          String pEmail = data['patientEmail'] ?? "";
          String pName = data['patientName'] ?? "Patient";
          int slotNum = data['slot'] ?? 0;

          // Check if physical hardware bin for this slot is still "Done" (needs refill)
          bool needsRefill = false;
          if (hardwareStates.containsKey(pEmail)) {
            var slots = hardwareStates[pEmail]!;
            var physicalSlot = slots.firstWhere((s) => s['slot'] == slotNum, orElse: () => null);
            if (physicalSlot != null && physicalSlot['isDone'] == true) {
              needsRefill = true;
            }
          }

          Color itemColor;
          IconData itemIcon;
          String msg;
          String sub;

          // --- FEED LOGIC: HANDLE LATE, TAKEN, MISSED, AND REFILL ---
          if (status == "taken") {
            itemColor = Colors.green;
            itemIcon = Icons.check_circle;
            msg = "$pName took $med";
            sub = "Confirmed on time at $takenAt";
          } else if (status == "late") {
            itemColor = Colors.orange;
            itemIcon = Icons.priority_high;
            msg = "$pName took $med late";
            sub = "Taken at $takenAt (Scheduled: $schedTime)";
          } else if (needsRefill && status == "upcoming") {
            // NEW STATUS: NOT REFILLED
            itemColor = Colors.deepPurple;
            itemIcon = Icons.inventory_2;
            msg = "NOT REFILLED: $pName - $med";
            sub = "Slot $slotNum requires refill for today's intake";
          } else {
            bool isActuallyMissed = false;
            try {
              DateTime st = DateFormat("hh:mm a").parse(schedTime);
              DateTime fullSched = DateTime(now.year, now.month, now.day, st.hour, st.minute);
              if (now.isAfter(fullSched.add(const Duration(minutes: 30)))) {
                isActuallyMissed = true;
              }
            } catch (e) {}

            if (isActuallyMissed || status == "missed") {
              urgentActions++;
              itemColor = Colors.red;
              itemIcon = Icons.error_outline;
              msg = "MISSED: $pName - $med";
              sub = "Failed to take dose scheduled for $schedTime";
            } else {
              itemColor = Colors.blueGrey;
              itemIcon = Icons.watch_later_outlined;
              msg = "Upcoming: $pName - $med";
              sub = "Scheduled for today at $schedTime";
            }
          }

          activityItems.add({
            "patientEmail": pEmail,
            "msg": msg,
            "sub": sub,
            "icon": itemIcon,
            "color": itemColor,
            "timeForSort": schedTime,
          });
        }

        // Sort by Scheduled Time
        activityItems.sort((a, b) => b['timeForSort'].compareTo(a['timeForSort']));

        if (mounted) {
          setState(() {
            _linkedPatientCount = patientEmails.length;
            _actionRequiredCount = urgentActions;
            _machineActivityFeed = activityItems;
            _isLoading = false;
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white, size: 20),
          onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false),
        ),
        backgroundColor: const Color(0xFF1A3B70), elevation: 0,
        title: const Text("Caregiver Hub", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: Text(fullName, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
        : RefreshIndicator(
            onRefresh: () async => _setupRealTimeSync(),
            color: const Color(0xFF1A3B70),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Today's Oversight", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                  const SizedBox(height: 20),

                  Row(children: [
                    Expanded(child: _buildStatCard("Linked Patients", _linkedPatientCount.toString(), Icons.people, Colors.teal)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildStatCard("Urgent Missed", _actionRequiredCount.toString(), Icons.notification_important, Colors.red)),
                  ]),

                  const SizedBox(height: 35),
                  const Text("Activity Feed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text("Real-time monitoring of doses and hardware status", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 15),

                  if (_machineActivityFeed.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text("No medication logs for today.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ))
                  else
                    ..._machineActivityFeed.map((activity) => _buildActivityCard(activity)),

                  const SizedBox(height: 30),
                  _buildRegistryButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 0, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  Widget _buildStatCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 10),
        Text(val, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> act) {
    bool isUrgent = act['color'] == Colors.red;
    bool isRefill = act['color'] == Colors.deepPurple;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), 
        side: BorderSide(
          color: isUrgent ? Colors.red.shade100 : (isRefill ? Colors.deepPurple.shade100 : Colors.grey.shade100), 
          width: (isUrgent || isRefill) ? 2 : 1
        )
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: act['color'].withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(act['icon'], color: act['color'], size: 20),
        ),
        title: Text(act['msg'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isUrgent ? Colors.red.shade900 : (isRefill ? Colors.deepPurple.shade900 : Colors.black))), 
        subtitle: Text(act['sub'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CaregiverScheduleEditor(userEmail: widget.userEmail, initialTargetEmail: act['patientEmail']))),
      ),
    );
  }

  Widget _buildRegistryButton() {
    return SizedBox(
      width: double.infinity, height: 55,
      child: ElevatedButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CaregiverLinked(userEmail: widget.userEmail))),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: const Text("Manage Patient Registry", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}