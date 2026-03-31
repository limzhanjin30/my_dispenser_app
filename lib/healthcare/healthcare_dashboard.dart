import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import 'healthcare_linked.dart';
import 'healthcare_adherence.dart';

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
  List<Map<String, dynamic>> _criticalAlerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupClinicalSync();
  }

  // --- ARCHITECTURE: MULTI-PATIENT CLINICAL MONITORING ---
  void _setupClinicalSync() {
    final String clinicalEmail = widget.userEmail.trim().toLowerCase();
    final DateTime now = DateTime.now();
    final String todayStr = DateFormat('yyyy-MM-dd').format(now);

    // 1. Fetch Provider Profile
    FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: clinicalEmail)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty && mounted) {
        setState(() => fullName = snap.docs.first.get('name') ?? "Healthcare Provider");
      }
    });

    // 2. Listen to Clinical Connections
    FirebaseFirestore.instance
        .collection('connections')
        .where('healthcareEmail', isEqualTo: clinicalEmail)
        .snapshots()
        .listen((connectionSnap) async {
      
      int totalScheduled = 0;
      int totalTaken = 0;
      int atRiskCount = 0;
      List<Map<String, dynamic>> alerts = [];

      for (var doc in connectionSnap.docs) {
        String pEmail = doc.get('patientEmail').toString().toLowerCase();

        // Step A: Find Patient Hardware
        var pUserSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: pEmail).limit(1).get();
        if (pUserSnap.docs.isEmpty) continue;
        
        var pData = pUserSnap.docs.first.data();
        String pName = pData['name'] ?? "Unknown";
        String? machineId = pData['linkedMachineId'];

        if (machineId == null || machineId.isEmpty) continue;

        // Step B: Audit Hardware State
        var machineDoc = await FirebaseFirestore.instance.collection('machines').doc(machineId).get();
        if (machineDoc.exists) {
          List<dynamic> slots = List.from(machineDoc.data()?['slots'] ?? []);
          bool patientHasMissed = false;

          for (var slot in slots) {
            if (slot['patientEmail'] != pEmail || slot['status'] == "Empty") continue;

            // Date validation for today
            DateTime end = DateTime.parse(slot['endDate'] ?? todayStr);
            if (now.isAfter(end.add(const Duration(days: 1)))) continue;

            List<String> times = List<String>.from(slot['times'] ?? []);
            bool isTakenToday = slot['lastTakenDate'] == todayStr || slot['status'] == "Finished";

            for (String t in times) {
              totalScheduled++;
              DateTime scheduledTime = _parseTimeString(t);
              DateTime graceLimit = scheduledTime.add(const Duration(minutes: 30));

              if (isTakenToday) {
                totalTaken++;
                if (slot['adherenceStatus'] == "Late") {
                  alerts.add({"msg": "$pName: Late Dose", "sub": "${slot['medDetails']} taken late at ${slot['lastTakenTime']}", "color": Colors.orange, "icon": Icons.access_time});
                }
              } else if (now.isAfter(graceLimit)) {
                patientHasMissed = true;
                alerts.add({"msg": "$pName: MISSED DOSE", "sub": "${slot['medDetails']} schedule for $t was missed.", "color": Colors.red, "icon": Icons.error_outline});
              }
            }
          }
          if (patientHasMissed) atRiskCount++;
        }
      }

      // Calculate Clinical Adherence Rate
      double adherenceRate = totalScheduled > 0 ? (totalTaken / totalScheduled) * 100 : 0;

      if (mounted) {
        setState(() {
          _totalPatients = connectionSnap.docs.length;
          _atRiskPatients = atRiskCount;
          _avgAdherence = "${adherenceRate.toStringAsFixed(0)}%";
          _criticalAlerts = alerts;
          _isLoading = false;
        });
      }
    });
  }

  DateTime _parseTimeString(String timeStr) {
    DateTime now = DateTime.now();
    DateTime p = DateFormat("hh:mm a").parse(timeStr);
    return DateTime(now.year, now.month, now.day, p.hour, p.minute);
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
        title: const Row(children: [Icon(Icons.health_and_safety, color: Colors.white), SizedBox(width: 10), Text("Clinical Hub", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]),
        actions: [
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            const Text("Online", style: TextStyle(color: Colors.greenAccent, fontSize: 9)),
          ]),
          const SizedBox(width: 20),
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
                const Text("Oversight Dashboard", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70))),
                const SizedBox(height: 25),

                // Statistics Row
                _buildStatCard("Total Patients", _totalPatients.toString(), Icons.groups, Colors.blue),
                const SizedBox(height: 15),
                _buildStatCard("At-Risk Patients", _atRiskPatients.toString(), Icons.priority_high, Colors.red, badgeCount: _atRiskPatients > 0 ? _atRiskPatients.toString() : null),
                const SizedBox(height: 15),
                _buildStatCard("Daily Avg. Adherence", _avgAdherence, Icons.donut_large, Colors.green),

                const SizedBox(height: 35),
                const Text("Priority Clinical Alerts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 15),

                if (_criticalAlerts.isEmpty)
                  _buildNoAlertsState()
                else
                  ..._criticalAlerts.take(5).map((alert) => _buildAlertTile(alert['msg'], alert['sub'], alert['icon'], alert['color'])),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 55,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => HealthcareLinked(userEmail: widget.userEmail))),
                    icon: const Icon(Icons.list_alt),
                    label: const Text("View Patient Registry", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A3B70),
                      side: const BorderSide(color: Color(0xFF1A3B70), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 0, role: "Healthcare\nProvider", userEmail: widget.userEmail),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? badgeCount}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: badgeCount != null 
              ? Badge(label: Text(badgeCount), child: Icon(icon, color: color, size: 28))
              : Icon(icon, color: color, size: 28),
          )
        ],
      ),
    );
  }

  Widget _buildAlertTile(String title, String sub, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 11)),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 16),
        ],
      ),
    );
  }

  Widget _buildNoAlertsState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.green.withOpacity(0.1))),
      child: const Column(children: [
        Icon(Icons.check_circle_outline, color: Colors.green, size: 40),
        SizedBox(height: 10),
        Text("No immediate clinical risks detected today.", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
    );
  }
}