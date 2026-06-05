import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'healthcare_linked.dart';
import 'healthcare_prescription.dart';

class HealthcareDashboard extends StatefulWidget {
  final String userEmail; 
  const HealthcareDashboard({super.key, required this.userEmail});

  @override
  State<HealthcareDashboard> createState() => _HealthcareDashboardState();
}

class _HealthcareDashboardState extends State<HealthcareDashboard> {
  String fullName = "Healthcare Provider";
  int _totalPatients = 0;
  int _missedCount = 0; 
  int _lateCount = 0; 
  String _avgAdherence = "0%";
  List<Map<String, dynamic>> _clinicalActivityFeed = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupClinicalSync();
  }

  // --- LOGIC: PER-DOSE SYSTEM RE-SYNC PIPELINE ---
  void _setupClinicalSync() {
    final String clinicalEmail = widget.userEmail.trim().toLowerCase();
    final DateTime now = DateTime.now();
    final String todayStr = DateFormat('yyyy-MM-dd').format(now);

    // 1. Fetch Provider Profile Name
    FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: clinicalEmail)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && mounted) {
        setState(() => fullName = snap.docs.first.get('name') ?? "Provider");
      }
    });

    // 2. Listen to Connections then fetch Daily Log Collections
    FirebaseFirestore.instance
        .collection('connections')
        .where('healthcareEmail', isEqualTo: clinicalEmail)
        .snapshots()
        .listen((connectionSnap) async {
      
      List<String> patientEmails = connectionSnap.docs.map((d) => d.get('patientEmail').toString().toLowerCase().trim()).toList();
      
      if (patientEmails.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _totalPatients = 0; _clinicalActivityFeed = []; _missedCount = 0; _lateCount = 0; _avgAdherence = "0%"; });
        return;
      }

      // --- REVERTED STREAM: MONITOR CHRONOLOGICAL FEED VIA ADHERENCE_LOGS FOR TODAY ---
      FirebaseFirestore.instance
          .collection('adherence_logs')
          .where('patientEmail', whereIn: patientEmails)
          .where('date', isEqualTo: todayStr)
          .snapshots()
          .listen((logSnap) async {
        
        int totalScheduled = logSnap.docs.length;
        int totalTaken = 0;
        int totalMissed = 0;
        int totalLate = 0;
        List<Map<String, dynamic>> feed = [];

        // --- HARDWARE LOOKUP: Pull in-memory hardware slots configurations ---
        Map<String, List<dynamic>> hardwareStates = {};
        try {
          var machineQuery = await FirebaseFirestore.instance
              .collection('machines')
              .where('linkedPatientEmail', whereIn: patientEmails)
              .get();

          for (var mDoc in machineQuery.docs) {
            String? pEmail = mDoc.data()['linkedPatientEmail'];
            if (pEmail != null) {
              hardwareStates[pEmail] = mDoc.data()['slots'] ?? [];
            }
          }
        } catch (e) {
          debugPrint("Clinical machine state extraction error: $e");
        }

        for (var doc in logSnap.docs) {
          var data = doc.data();
          if (data['finalStatus'] == "Course Terminated") continue;

          String status = (data['adherenceStatus'] ?? "Upcoming").toString().toLowerCase().trim();
          String med = data['medName'] ?? data['medDetails'] ?? "Medication";
          String schedT = (data['times'] is List && (data['times'] as List).isNotEmpty) ? (data['times'] as List).first : "--:--";
          String takenT = data['takenTime'] ?? data['lastTakenTime'] ?? "";
          String pName = data['patientName'] ?? "Patient";
          String pEmail = data['patientEmail'] ?? "";
          int slotNum = data['slot'] ?? 0;

          bool needsRefill = false;
          if (hardwareStates.containsKey(pEmail)) {
            var slots = hardwareStates[pEmail]!;
            var physicalSlot = slots.firstWhere((s) => s['slot'] == slotNum, orElse: () => null);
            if (physicalSlot != null && physicalSlot['isDone'] == true) {
              needsRefill = true;
            }
          }

          Color color;
          IconData icon;
          String msg;
          String sub;

          // --- FEED COMPLIANCE MAP RECLASSIFICATION ---
          if (status == "taken") {
            totalTaken++;
            color = Colors.green;
            icon = Icons.check_circle;
            msg = "$pName took $med";
            sub = "Confirmed on time at $takenT";
          } else if (status == "late") {
            totalTaken++;
            totalLate++; // Increment the daily late counts explicitly
            color = Colors.orange;
            icon = Icons.priority_high;
            msg = "$pName took $med late";
            sub = "Taken at $takenT (Scheduled: $schedT)";
          } else if (needsRefill && status == "upcoming") {
            color = Colors.deepPurple;
            icon = Icons.inventory_2;
            msg = "NOT REFILLED: $pName - $med";
            sub = "Slot $slotNum requires refill for today's intake";
          } else {
            bool isActuallyMissed = false;
            try {
              DateTime st = DateFormat("hh:mm a").parse(schedT);
              DateTime fullS = DateTime(now.year, now.month, now.day, st.hour, st.minute);
              if (now.isAfter(fullS.add(const Duration(minutes: 30)))) {
                isActuallyMissed = true;
              }
            } catch (e) {}

            if (isActuallyMissed || status == "missed") {
              totalMissed++; // Increment the daily missed metrics explicitly
              color = Colors.red;
              icon = Icons.error_outline;
              msg = "MISSED: $pName - $med";
              sub = "Failed to take dose scheduled for $schedT";
            } else {
              color = Colors.blueGrey;
              icon = Icons.watch_later_outlined;
              msg = "Upcoming: $pName - $med";
              sub = "Scheduled for today at $schedT";
            }
          }

          feed.add({
            "patientEmail": pEmail,
            "msg": msg,
            "sub": sub,
            "color": color,
            "icon": icon,
            "timeForSort": schedT,
          });
        }

        // Sort activity feed items chronologically by Scheduled Time (Descending)
        feed.sort((a, b) => b['timeForSort'].compareTo(a['timeForSort']));

        if (mounted) {
          setState(() {
            _totalPatients = patientEmails.length;
            _missedCount = totalMissed;
            _lateCount = totalLate;
            _avgAdherence = totalScheduled > 0 ? "${((totalTaken / totalScheduled) * 100).toStringAsFixed(0)}%" : "0%";
            _clinicalActivityFeed = feed;
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
        title: const Text("Clinical Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          Center(child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Text(fullName, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          )),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
        : RefreshIndicator(
            onRefresh: () async => _setupClinicalSync(),
            color: const Color(0xFF1A3B70),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Registry Performance", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                  const SizedBox(height: 20),

                  // 🎯 FIXED STATS SECTION: Formatted grid splitting 4 metrics evenly
                  Row(
                    children: [
                      Expanded(child: _buildStatCard("Patients", _totalPatients.toString(), Icons.groups, Colors.blue)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard("Missed", _missedCount.toString(), Icons.error_outline, Colors.red)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard("Late", _lateCount.toString(), Icons.watch_later_outlined, Colors.orange)),
                    ],
                  ),

                  const SizedBox(height: 35),
                  const Text("Real-Time Activity Feed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text("Monitoring per-dose log array data within individual devices", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 15),

                  if (_clinicalActivityFeed.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Text("No medication activity recorded today.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ))
                  else
                    ..._clinicalActivityFeed.take(25).map((activity) => _buildActivityCard(activity)),

                  const SizedBox(height: 30),
                  _buildRegistryButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 0, role: "Healthcare\nProvider", userEmail: widget.userEmail),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            title, 
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold)
          ),
        ]
      ),
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => HealthcarePrescription(userEmail: widget.userEmail, initialTargetEmail: act['patientEmail']))),
      ),
    );
  }

  Widget _buildRegistryButton() {
    return SizedBox(
      width: double.infinity, height: 55,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => HealthcareLinked(userEmail: widget.userEmail))),
        icon: const Icon(Icons.manage_accounts_outlined, color: Colors.white),
        label: const Text("View Full Patient Registry", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }
}