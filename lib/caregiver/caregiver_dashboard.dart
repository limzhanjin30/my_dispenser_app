import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'caregiver_linked.dart';
import 'caregiver_adherence.dart';

class CaregiverDashboard extends StatefulWidget {
  final String userEmail;
  const CaregiverDashboard({super.key, required this.userEmail});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  String fullName = "Caregiver";
  int _linkedPatientCount = 0;
  int _pendingDosesToday = 0; 
  List<Map<String, dynamic>> _recentActivity = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupRealTimeListeners();
  }

  void _setupRealTimeListeners() {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();
    final DateTime now = DateTime.now();
    // Normalize today's date for range comparison
    final DateTime todayMidnight = DateTime(now.year, now.month, now.day);

    FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        setState(() => fullName = snap.docs.first.get('name') ?? "Caregiver");
      }
    });

    FirebaseFirestore.instance
        .collection('connections')
        .where('caregiverEmail', isEqualTo: cleanEmail)
        .snapshots()
        .listen((connectionSnap) async {
      
      int patientCount = connectionSnap.docs.length;
      int pendingAggregate = 0;
      List<Map<String, dynamic>> activities = [];

      for (var doc in connectionSnap.docs) {
        String pEmail = doc.get('patientEmail').toString().toLowerCase();

        var pUserSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: pEmail)
            .limit(1)
            .get();
        String pName = pUserSnap.docs.isNotEmpty ? pUserSnap.docs.first.get('name') : "Unknown";

        var scheduleDoc = await FirebaseFirestore.instance.collection('schedules').doc(pEmail).get();
        if (scheduleDoc.exists) {
          List<dynamic> slots = scheduleDoc.data()?['slots'] ?? [];
          for (var slot in slots) {
            if (slot['name'] == null || slot['name'].toString().contains("Empty Slot")) continue;

            // --- STEP 1: VALIDATE CURRENT DAY IS IN RANGE ---
            DateTime start = DateTime.parse(slot['startDate'] ?? now.toString());
            DateTime end = DateTime.parse(slot['endDate'] ?? now.toString());
            DateTime startDate = DateTime(start.year, start.month, start.day);
            DateTime endDate = DateTime(end.year, end.month, end.day);

            if (todayMidnight.isBefore(startDate) || todayMidnight.isAfter(endDate)) continue;

            bool isDone = slot['isDone'] ?? false;
            String medName = slot['name'];
            List<String> times = List<String>.from(slot['times'] ?? []);

            for (String timeStr in times) {
              DateTime doseTimeToday;
              try {
                DateTime parsedTime = DateFormat("hh:mm a").parse(timeStr);
                doseTimeToday = DateTime(now.year, now.month, now.day, parsedTime.hour, parsedTime.minute);
              } catch (e) {
                continue;
              }

              if (isDone) {
                activities.add({
                  "patientEmail": pEmail,
                  "msg": "$pName ($pEmail) took $medName",
                  "time": "Today, $timeStr",
                  "icon": Icons.check_circle,
                  "color": Colors.green,
                });
              } else if (now.isAfter(doseTimeToday)) {
                // Time passed and NOT done = MISSED
                pendingAggregate++;
                activities.add({
                  "patientEmail": pEmail,
                  "msg": "$pName ($pEmail) missed $medName",
                  "time": "Today, $timeStr",
                  "icon": Icons.error,
                  "color": Colors.red,
                });
              } else {
                // Time has NOT arrived yet = UPCOMING
                pendingAggregate++;
                activities.add({
                  "patientEmail": pEmail,
                  "msg": '$pName ($pEmail) has "$medName" coming up at $timeStr',
                  "time": "Today",
                  "icon": Icons.access_time_filled,
                  "color": Colors.blueGrey,
                });
              }
            }
          }
        }
      }

      // Sort activity: Missed/Upcoming doses first
      activities.sort((a, b) => b['time'].compareTo(a['time']));

      if (mounted) {
        setState(() {
          _linkedPatientCount = patientCount;
          _pendingDosesToday = pendingAggregate;
          _recentActivity = activities;
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
        backgroundColor: const Color(0xFF1A3B70),
        elevation: 0,
        title: const Text("Smart Med Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          const Icon(Icons.notifications_none, color: Colors.white),
          const SizedBox(width: 15),
          Center(
            child: Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Caregiver Overview", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
              const SizedBox(height: 25),

              _buildStatCard("Linked Patients", _linkedPatientCount.toString(), Icons.person_add, Colors.teal),
              const SizedBox(height: 15),
              _buildStatCard("Total Doses (Today)", _pendingDosesToday.toString(), Icons.warning_amber_rounded, Colors.orange),

              const SizedBox(height: 35),
              const Text("Adherence Activity Feed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),

              if (_recentActivity.isEmpty)
                const Center(child: Text("No medication activity for today.", style: TextStyle(color: Colors.grey)))
              else
                ..._recentActivity.take(10).map((act) => _buildActivityTile(
                  act['msg'], 
                  act['time'], 
                  act['icon'], 
                  act['color'],
                  act['patientEmail'], 
                )),

              const SizedBox(height: 40),
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
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 0, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
          Icon(icon, color: color, size: 35),
        ],
      ),
    );
  }

  Widget _buildActivityTile(String msg, String time, IconData icon, Color iconColor, String patientEmail) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(msg, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), 
        subtitle: Text(time, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () {
          Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => CaregiverAdherence(userEmail: widget.userEmail))
          );
        },
      ),
    );
  }
}