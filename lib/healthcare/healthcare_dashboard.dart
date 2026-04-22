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
  int _atRiskPatients = 0;
  String _avgAdherence = "0%";
  List<Map<String, dynamic>> _clinicalActivityFeed = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupClinicalSync();
  }

  // --- LOGIC: PER-DOSE ADHERENCE SYNC ---
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

    // 2. Listen to Connections then Adherence Logs
    FirebaseFirestore.instance
        .collection('connections')
        .where('healthcareEmail', isEqualTo: clinicalEmail)
        .snapshots()
        .listen((connectionSnap) async {
      
      List<String> patientEmails = connectionSnap.docs.map((d) => d.get('patientEmail').toString().toLowerCase().trim()).toList();
      
      if (patientEmails.isEmpty) {
        if (mounted) setState(() { _isLoading = false; _totalPatients = 0; _clinicalActivityFeed = []; });
        return;
      }

      // Query granular logs for all linked patients for TODAY
      FirebaseFirestore.instance
          .collection('adherence_logs')
          .where('patientEmail', whereIn: patientEmails)
          .where('date', isEqualTo: todayStr)
          .snapshots()
          .listen((logSnap) {
        
        int totalScheduled = logSnap.docs.length;
        int totalTaken = 0;
        Set<String> atRiskEmails = {}; 
        List<Map<String, dynamic>> feed = [];

        for (var doc in logSnap.docs) {
          var data = doc.data() as Map<String, dynamic>;
          if (data['finalStatus'] == "Course Terminated") continue;

          String status = (data['adherenceStatus'] ?? "Upcoming").toString().toLowerCase().trim();
          String med = data['medName'] ?? data['medDetails'] ?? "Medication";
          String schedT = (data['times'] is List && (data['times'] as List).isNotEmpty) ? (data['times'] as List).first : "--:--";
          String takenT = data['takenTime'] ?? data['lastTakenTime'] ?? "";
          String pName = data['patientName'] ?? "Patient";
          String pEmail = data['patientEmail'] ?? "";

          Color color;
          IconData icon;
          String msg;
          String sub;

          // --- STATUS CLASSIFICATION (Mirrors Caregiver Logic) ---
          if (status == "taken") {
            totalTaken++;
            color = Colors.green;
            icon = Icons.check_circle;
            msg = "$pName took $med";
            sub = "Confirmed on time at $takenT";
          } else if (status == "late") {
            totalTaken++;
            color = Colors.orange;
            icon = Icons.priority_high;
            msg = "$pName took $med late";
            sub = "Taken at $takenT (Scheduled: $schedT)";
          } else {
            // Check if Upcoming has timed out (schedule + 30 mins)
            bool isActuallyMissed = false;
            try {
              DateTime st = DateFormat("hh:mm a").parse(schedT);
              DateTime fullS = DateTime(now.year, now.month, now.day, st.hour, st.minute);
              if (now.isAfter(fullS.add(const Duration(minutes: 30)))) {
                isActuallyMissed = true;
              }
            } catch (e) {}

            if (isActuallyMissed || status == "missed") {
              atRiskEmails.add(pEmail);
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
            "timestamp": (data['timestamp'] as Timestamp?)?.toDate() ?? now,
          });
        }

        // Sort feed by most recent activity/schedule
        feed.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

        if (mounted) {
          setState(() {
            _totalPatients = patientEmails.length;
            _atRiskPatients = atRiskEmails.length;
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
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Registry Performance", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                  const SizedBox(height: 20),

                  Row(children: [
                    Expanded(child: _buildStatCard("Patients", _totalPatients.toString(), Icons.groups, Colors.blue)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard("At-Risk", _atRiskPatients.toString(), Icons.warning_amber_rounded, Colors.red)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard("Daily Adh.", _avgAdherence, Icons.analytics, Colors.green)),
                  ]),

                  const SizedBox(height: 35),
                  const Text("Real-Time Activity Feed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text("Monitoring per-dose logs across the registry", style: TextStyle(fontSize: 11, color: Colors.grey)),
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 9, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> act) {
    bool isUrgent = act['color'] == Colors.red;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
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