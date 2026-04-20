import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'healthcare_dashboard.dart';
import '../custom_bottom_nav.dart';

class HealthcareAdherence extends StatefulWidget {
  final String userEmail;
  const HealthcareAdherence({super.key, required this.userEmail});

  @override
  State<HealthcareAdherence> createState() => _HealthcareAdherenceState();
}

class _HealthcareAdherenceState extends State<HealthcareAdherence> {
  String? _selectedPatientEmail;
  
  // Logic: Force current week to start on Monday
  DateTime _currentWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  void _changeWeek(int weeks) => setState(() => _currentWeekStart = _currentWeekStart.add(Duration(days: weeks * 7)));

  String _getWeekRangeString() {
    DateTime end = _currentWeekStart.add(const Duration(days: 6));
    return "${DateFormat('MMM d').format(_currentWeekStart)} - ${DateFormat('MMM d, yyyy').format(end)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HealthcareDashboard(userEmail: widget.userEmail))),
        ),
        title: const Text("Weekly Adherence Audit", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPatientSelector(),
          _buildWeekNavigator(),
          Expanded(
            child: _selectedPatientEmail == null 
              ? _buildEmptyState("Select a clinical patient to audit their weekly adherence history.")
              : _buildWeeklyLogs(),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 2, role: "Healthcare\nProvider", userEmail: widget.userEmail),
    );
  }

  Widget _buildPatientSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('connections')
          .where('healthcareEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        var connections = snapshot.data!.docs;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: Colors.white,
          child: DropdownButtonFormField<String>(
            value: _selectedPatientEmail,
            hint: const Text("Select Patient Registry"),
            decoration: InputDecoration(labelText: "Clinical Oversight", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            items: connections.map((c) => DropdownMenuItem(
              value: c.get('patientEmail').toString().toLowerCase().trim(), 
              child: Text(c.get('patientEmail'))
            )).toList(),
            onChanged: (val) => setState(() => _selectedPatientEmail = val),
          ),
        );
      },
    );
  }

  Widget _buildWeekNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeWeek(-1)),
          Column(children: [
            const Text("AUDIT PERIOD", style: TextStyle(fontSize: 10, color: Color(0xFF1A3B70), fontWeight: FontWeight.bold)),
            Text(_getWeekRangeString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeWeek(1)),
        ],
      ),
    );
  }

  Widget _buildWeeklyLogs() {
    String startStr = DateFormat('yyyy-MM-dd').format(_currentWeekStart);
    String endStr = DateFormat('yyyy-MM-dd').format(_currentWeekStart.add(const Duration(days: 7)));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('adherence_logs')
          .where('patientEmail', isEqualTo: _selectedPatientEmail!.trim().toLowerCase())
          .where('date', isGreaterThanOrEqualTo: startStr) 
          .where('date', isLessThan: endStr)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildEmptyState("Error loading clinical records.");
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        // Group logs by their date field
        Map<String, List<Map<String, dynamic>>> masterMap = {};
        for (var doc in snapshot.data?.docs ?? []) {
          var data = doc.data() as Map<String, dynamic>;
          String recordDate = data['date'] ?? "Unknown";
          masterMap.putIfAbsent(recordDate, () => []).add(data);
        }

        DateTime now = DateTime.now();
        DateTime todayMidnight = DateTime(now.year, now.month, now.day);

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 7, // Fixed Mon-Sun loop
          itemBuilder: (context, dayIndex) {
            DateTime currentDay = _currentWeekStart.add(Duration(days: dayIndex));
            String dayStr = DateFormat('yyyy-MM-dd').format(currentDay);
            
            List<Map<String, dynamic>> dayItems = List.from(masterMap[dayStr] ?? []);

            // Sort individual doses chronologically
            dayItems.sort((a, b) {
              String tA = (a['times'] as List).isNotEmpty ? (a['times'] as List).first : "00:00 AM";
              String tB = (b['times'] as List).isNotEmpty ? (b['times'] as List).first : "00:00 AM";
              return tA.compareTo(tB);
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(DateFormat('EEEE, MMM d').format(currentDay), 
                    style: TextStyle(fontWeight: FontWeight.bold, color: currentDay.isAtSameMomentAs(todayMidnight) ? Colors.blue : Colors.blueGrey)),
                ),
                if (dayItems.isEmpty) 
                  const Padding(padding: EdgeInsets.only(left: 10, bottom: 10), child: Text("No clinical logs for this date.", style: TextStyle(color: Colors.grey, fontSize: 11))),
                
                ...dayItems.map((item) {
                  // --- MISSED LOGIC ---
                  String displayStatus = item['adherenceStatus'] ?? "Upcoming";
                  String sched = (item['times'] as List).isNotEmpty ? (item['times'] as List).first : "--:--";
                  String actual = item['takenTime'] ?? item['lastTakenTime'] ?? "";

                  // Real-time audit: if Upcoming and time passed + 30 mins
                  if (displayStatus.toLowerCase() == "upcoming" && sched != "--:--") {
                    try {
                      DateTime st = DateFormat("hh:mm a").parse(sched);
                      DateTime fullSched = DateTime(currentDay.year, currentDay.month, currentDay.day, st.hour, st.minute);
                      if (now.isAfter(fullSched.add(const Duration(minutes: 30)))) {
                        displayStatus = "Missed";
                      }
                    } catch (e) {}
                  }

                  return _buildAdherenceCard(item, displayStatus, sched, actual);
                }),
                const Divider(height: 30),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAdherenceCard(Map<String, dynamic> item, String displayStatus, String scheduledTime, String actualTime) {
    String med = item['medName'] ?? item['medDetails'] ?? "Medication";
    int bin = item['slot'] ?? 0;

    Color color; IconData icon; String subText;

    switch (displayStatus.toLowerCase()) {
      case "taken":
        color = Colors.teal; icon = Icons.check_circle;
        subText = "Taken at $actualTime (Scheduled: $scheduledTime)";
        break;
      case "late":
        color = Colors.orange; icon = Icons.warning_amber_rounded;
        subText = "LATE Intake at $actualTime (Scheduled: $scheduledTime)";
        break;
      case "missed":
        color = Colors.redAccent; icon = Icons.error_outline;
        subText = "MISSED: Scheduled for $scheduledTime";
        break;
      default:
        color = Colors.blueGrey; icon = Icons.hourglass_empty;
        subText = "Scheduled for $scheduledTime";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))]),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 6, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)))),
            const SizedBox(width: 15),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15), 
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(med, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text("Bin $bin • $subText", style: const TextStyle(fontSize: 10, color: Colors.black54)),
                ])
              )
            ),
            Padding(
              padding: const EdgeInsets.only(right: 15), 
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(height: 4),
                Text(displayStatus.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 8)),
              ])
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Padding(padding: const EdgeInsets.all(40.0), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13))));
}