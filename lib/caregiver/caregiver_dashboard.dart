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

  // --- ARCHITECTURE: MULTI-MACHINE REAL-TIME SYNC ---
  void _setupRealTimeSync() {
    final String caregiverEmail = widget.userEmail.trim().toLowerCase();
    final DateTime now = DateTime.now();
    final String todayStr = DateFormat('yyyy-MM-dd').format(now);
    final DateTime todayMidnight = DateTime(now.year, now.month, now.day);

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

    FirebaseFirestore.instance
        .collection('connections')
        .where('caregiverEmail', isEqualTo: caregiverEmail)
        .snapshots()
        .listen((connectionSnap) async {
      
      int totalPatients = connectionSnap.docs.length;
      int urgentActions = 0;
      List<Map<String, dynamic>> consolidatedActivity = [];

      for (var doc in connectionSnap.docs) {
        String pEmail = doc.get('patientEmail').toString().toLowerCase();

        var pUserSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: pEmail)
            .limit(1)
            .get();
        
        if (pUserSnap.docs.isEmpty) continue;
        var pData = pUserSnap.docs.first.data();
        String pName = pData['name'] ?? "Unknown";
        String? machineId = pData['linkedMachineId'];

        if (machineId == null || machineId.isEmpty) continue;

        var machineDoc = await FirebaseFirestore.instance.collection('machines').doc(machineId).get();
        if (machineDoc.exists) {
          List<dynamic> slots = List.from(machineDoc.data()?['slots'] ?? []);
          bool needsCleanupUpdate = false;

          for (int i = 0; i < slots.length; i++) {
            var slot = slots[i];
            
            // SECURITY: Skip genuinely empty slots
            if (slot['status'] == "Empty") continue;

            // 1. LOGIC: AUTO-FINISH SLOT WHEN DATE ENDS
            DateTime endDate = DateTime.parse(slot['endDate'] ?? todayStr);
            if (now.isAfter(endDate.add(const Duration(days: 1))) && slot['status'] == "Occupied") {
              slots[i]['status'] = "Finished";
              slots[i]['isLocked'] = false; // Physically release hardware
              needsCleanupUpdate = true;
            }

            if (slot['patientEmail'] != pEmail) continue;

            // Date Range Filter for Today's Activity
            DateTime start = DateTime.parse(slot['startDate'] ?? todayStr);
            if (todayMidnight.isBefore(DateTime(start.year, start.month, start.day)) || 
                todayMidnight.isAfter(endDate)) continue;

            String med = slot['medDetails'] ?? "Medication";
            List<String> times = List<String>.from(slot['times'] ?? []);
            bool isTakenToday = slot['lastTakenDate'] == todayStr;
            bool isPhysicallyEmpty = slot['isDone'] ?? false;
            bool isFinishedStatus = slot['status'] == "Finished";

            for (String t in times) {
              DateTime scheduledDose;
              try {
                DateTime parsed = DateFormat("hh:mm a").parse(t);
                scheduledDose = DateTime(now.year, now.month, now.day, parsed.hour, parsed.minute);
              } catch (e) { continue; }

              // 2. LOGIC: REFILL ALERT (Only for active "Occupied" slots)
              Duration timeUntilDose = scheduledDose.difference(now);
              if (!isTakenToday && !isFinishedStatus && isPhysicallyEmpty && timeUntilDose.inMinutes <= 60 && timeUntilDose.inMinutes > 0) {
                urgentActions++;
                consolidatedActivity.add({
                  "patientEmail": pEmail,
                  "msg": "URGENT REFILL: $pName",
                  "sub": "$med due in ${timeUntilDose.inMinutes}m (Slot ${slot['slot']})",
                  "icon": Icons.assignment_return,
                  "color": Colors.deepOrange,
                  "timestamp": scheduledDose,
                });
              }

              // 3. LOGIC: FEED STATUS (Taken / Missed / Upcoming / Finished)
              DateTime graceLimit = scheduledDose.add(const Duration(minutes: 30));
              
              if (isFinishedStatus) {
                // Display finished courses as successfully completed records
                consolidatedActivity.add({
                  "patientEmail": pEmail,
                  "msg": "$pName: Course Finished",
                  "sub": "$med course completed successfully.",
                  "icon": Icons.verified,
                  "color": Colors.blue,
                  "timestamp": scheduledDose,
                });
              } else if (isTakenToday) {
                consolidatedActivity.add({
                  "patientEmail": pEmail,
                  "msg": "$pName took $med",
                  "sub": "${(slot['adherenceStatus'] ?? "Taken").toUpperCase()} (Slot ${slot['slot']})",
                  "icon": slot['adherenceStatus'] == "Late" ? Icons.priority_high : Icons.check_circle,
                  "color": slot['adherenceStatus'] == "Late" ? Colors.orange : Colors.green,
                  "timestamp": scheduledDose,
                });
              } else if (now.isAfter(graceLimit)) {
                urgentActions++;
                consolidatedActivity.add({
                  "patientEmail": pEmail,
                  "msg": "$pName MISSED $med",
                  "sub": "Scheduled for $t • Action Required",
                  "icon": Icons.error_outline,
                  "color": Colors.red,
                  "timestamp": scheduledDose,
                });
              } else {
                consolidatedActivity.add({
                  "patientEmail": pEmail,
                  "msg": '$pName: Upcoming $med',
                  "sub": "Due today at $t",
                  "icon": Icons.watch_later,
                  "color": Colors.blueGrey,
                  "timestamp": scheduledDose,
                });
              }
            }
          }

          // Trigger Autonomous Slot Cleanup in Firestore
          if (needsCleanupUpdate) {
            await FirebaseFirestore.instance.collection('machines').doc(machineId).update({'slots': slots});
          }
        }
      }

      consolidatedActivity.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

      if (mounted) {
        setState(() {
          _linkedPatientCount = totalPatients;
          _actionRequiredCount = urgentActions;
          _machineActivityFeed = consolidatedActivity;
          _isLoading = false;
        });
      }
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
                const Text("Hardware Monitoring", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                const SizedBox(height: 20),

                Row(children: [
                  Expanded(child: _buildStatCard("Linked Patients", _linkedPatientCount.toString(), Icons.people, Colors.teal)),
                  const SizedBox(width: 15),
                  Expanded(child: _buildStatCard("Action Required", _actionRequiredCount.toString(), Icons.notification_important, Colors.red)),
                ]),

                const SizedBox(height: 35),
                const Text("Live Activity Feed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),

                if (_machineActivityFeed.isEmpty)
                  const Center(child: Text("No machine activity detected today.", style: TextStyle(color: Colors.grey, fontSize: 13)))
                else
                  ..._machineActivityFeed.take(15).map((activity) => _buildActivityCard(activity)),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CaregiverLinked(userEmail: widget.userEmail))),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text("Manage Patient Access", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
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
    bool isUrgent = act['msg'].contains("URGENT") || act['color'] == Colors.red;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isUrgent ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), 
        side: BorderSide(color: isUrgent ? Colors.red.shade100 : Colors.grey.shade100, width: isUrgent ? 2 : 1)
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: act['color'].withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(act['icon'], color: act['color'], size: 20),
        ),
        title: Text(act['msg'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isUrgent ? Colors.red.shade900 : Colors.black)), 
        subtitle: Text(act['sub'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CaregiverScheduleEditor(userEmail: widget.userEmail, initialTargetEmail: act['patientEmail']))),
      ),
    );
  }
}