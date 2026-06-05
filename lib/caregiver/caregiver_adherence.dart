import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import 'caregiver_dashboard.dart';

class CaregiverAdherence extends StatefulWidget {
  final String userEmail;
  const CaregiverAdherence({super.key, required this.userEmail});

  @override
  State<CaregiverAdherence> createState() => _CaregiverAdherenceState();
}

class _CaregiverAdherenceState extends State<CaregiverAdherence> {
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
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CaregiverDashboard(userEmail: widget.userEmail))),
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
              ? _buildEmptyState("Select a patient to audit their weekly adherence.")
              : _buildWeeklyLogsStream(),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 2, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  Widget _buildPatientSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('connections').where('caregiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase()).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        var connections = snapshot.data!.docs;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: Colors.white,
          child: DropdownButtonFormField<String>(
            value: _selectedPatientEmail,
            hint: const Text("Select Patient"),
            decoration: InputDecoration(labelText: "Clinical Monitoring", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            items: connections.map((c) {
              String cleanEmail = c.get('patientEmail').toString().toLowerCase().trim();
              return DropdownMenuItem(value: cleanEmail, child: Text(cleanEmail));
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedPatientEmail = val;
                });
              }
            },
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
            const Text("CURRENT WEEK", style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
            Text(_getWeekRangeString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeWeek(1)),
        ],
      ),
    );
  }

  Widget _buildWeeklyLogsStream() {
    String startStr = DateFormat('yyyy-MM-dd').format(_currentWeekStart);
    String endStr = DateFormat('yyyy-MM-dd').format(_currentWeekStart.add(const Duration(days: 7)));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('adherence_logs')
          .where('patientEmail', isEqualTo: _selectedPatientEmail!.trim().toLowerCase())
          .where('date', isGreaterThanOrEqualTo: startStr) 
          .where('date', isLessThan: endStr)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildEmptyState("Error loading logs. Check compound indexes layout.");
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

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
          itemCount: 7, 
          itemBuilder: (context, dayIndex) {
            DateTime currentDay = _currentWeekStart.add(Duration(days: dayIndex));
            String dayStr = DateFormat('yyyy-MM-dd').format(currentDay);
            
            List<Map<String, dynamic>> dayItems = List.from(masterMap[dayStr] ?? []);

            dayItems.sort((a, b) {
              String tA = (a['times'] is List && (a['times'] as List).isNotEmpty) ? (a['times'] as List).first : "00:00 AM";
              String tB = (b['times'] is List && (b['times'] as List).isNotEmpty) ? (b['times'] as List).first : "00:00 AM";
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
                  const Padding(padding: EdgeInsets.only(left: 10, bottom: 10), child: Text("No medication activity logs.", style: TextStyle(color: Colors.grey, fontSize: 11))),
                
                ...dayItems.map((item) {
                  String displayStatus = item['adherenceStatus'] ?? "Upcoming";
                  String sched = (item['times'] is List && (item['times'] as List).isNotEmpty) ? (item['times'] as List).first : "--:--";
                  String actual = item['takenTime'] ?? item['lastTakenTime'] ?? "";
                  String lifecycleStatus = item['finalStatus'] ?? "Course Active";

                  // Missed execution tracking window check
                  if (displayStatus.toLowerCase() == "upcoming" && sched != "--:--") {
                    try {
                      DateTime st = DateFormat("hh:mm a").parse(sched);
                      DateTime fullSched = DateTime(currentDay.year, currentDay.month, currentDay.day, st.hour, st.minute);
                      if (now.isAfter(fullSched.add(const Duration(minutes: 30)))) {
                        displayStatus = "Missed";
                      }
                    } catch (e) {}
                  }

                  // Force explicit intercept override status check mapping for archived channels
                  if (displayStatus.toLowerCase() == "archived" || lifecycleStatus == "Course Terminated") {
                    displayStatus = "Terminated";
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
    String med = item['medDetails'] ?? item['medName'] ?? "Medicine";
    int bin = item['slot'] ?? 0;

    Color color; IconData icon; String subText;

    switch (displayStatus.toLowerCase()) {
      case "taken":
        color = Colors.green; icon = Icons.check_circle;
        subText = "Taken at $actualTime (Scheduled: $scheduledTime)";
        break;
      case "late":
        color = Colors.orange; icon = Icons.watch_later;
        subText = "Taken LATE at $actualTime (Scheduled: $scheduledTime)";
        break;
      case "missed":
        color = Colors.red; icon = Icons.error_outline;
        subText = "Missed: Dose was scheduled for $scheduledTime";
        break;
      case "terminated":
        color = Colors.purple; icon = Icons.cancel_presentation_outlined;
        subText = "Terminated: Course stopped by Caregiver (Was: $scheduledTime)";
        break;
      default:
        color = Colors.blueGrey; icon = Icons.timer_outlined;
        subText = "Upcoming: Dose scheduled for $scheduledTime";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))]),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 5, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)))),
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
            // 👇 FIXED: Aligned trailing structural icon segment into an absolute horizontal row line
            Padding(
              padding: const EdgeInsets.only(right: 15), 
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    displayStatus.toUpperCase(), 
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 0.5)
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Padding(padding: const EdgeInsets.all(40.0), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13))));
}