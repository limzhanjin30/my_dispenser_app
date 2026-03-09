import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';

class PatientDashboard extends StatefulWidget {
  final String userEmail;
  const PatientDashboard({super.key, required this.userEmail});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  String fullName = "Patient";
  Map<String, dynamic>? nextDose;
  List<dynamic> todaySchedule = [];

  @override
  void initState() {
    super.initState();
    _fetchFirestoreData();
  }

  Future<void> _fetchFirestoreData() async {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();

    try {
      var userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        setState(() => fullName = userSnapshot.docs.first.get('name') ?? "Patient");
      }

      FirebaseFirestore.instance
          .collection('schedules')
          .doc(cleanEmail)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          _processDynamicSchedule(snapshot.data()!['slots'] ?? []);
        }
      });
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  // --- UPDATED LOGIC: FILTER FOR TODAY'S DATE & FIND NEXT DOSE ---
  void _processDynamicSchedule(List<dynamic> slots) {
    DateTime now = DateTime.now();
    DateTime todayOnly = DateTime(now.year, now.month, now.day);
    
    List<Map<String, dynamic>> allFutureTimings = [];
    List<Map<String, dynamic>> todayDisplayList = [];

    for (var slot in slots) {
      if (slot['name'] == null || slot['name'].toString().contains("Empty Slot")) continue;
      
      // Parse prescription range
      DateTime start = DateTime.parse(slot['startDate'] ?? now.toString());
      DateTime end = DateTime.parse(slot['endDate'] ?? now.add(const Duration(days: 365)).toString());
      
      // Normalize to midnight for comparison
      DateTime startDate = DateTime(start.year, start.month, start.day);
      DateTime endDate = DateTime(end.year, end.month, end.day);

      List<String> times = List<String>.from(slot['times'] ?? []);
      for (var t in times) {
        // Look ahead up to 7 days to find the next valid dose
        for (int dayOffset = 0; dayOffset <= 7; dayOffset++) {
          DateTime checkDate = todayOnly.add(Duration(days: dayOffset));
          
          // Only process if within the valid treatment duration
          if ((checkDate.isAtSameMomentAs(startDate) || checkDate.isAfter(startDate)) && 
              (checkDate.isAtSameMomentAs(endDate) || checkDate.isBefore(endDate))) {
            
            DateTime doseFullDateTime = _parseTimeString(t, checkDate);
            
            var doseMap = {
              "name": slot['name'],
              "pills": slot['pills'],
              "fullTime": doseFullDateTime,
              "displayTime": t,
              "isDone": slot['isDone'] ?? false,
            };

            allFutureTimings.add(doseMap);
            // ONLY add to Display List if it is strictly TODAY
            if (dayOffset == 0) todayDisplayList.add(doseMap);
          }
        }
      }
    }

    allFutureTimings.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));
    todayDisplayList.sort((a, b) => (a['fullTime'] as DateTime).compareTo(b['fullTime'] as DateTime));

    // Find absolute next dose (even if it's tomorrow)
    Map<String, dynamic>? upcoming;
    try {
      upcoming = allFutureTimings.firstWhere((dose) => (dose['fullTime'] as DateTime).isAfter(now));
    } catch (e) {
      upcoming = null; 
    }

    setState(() {
      todaySchedule = todayDisplayList;
      nextDose = upcoming;
    });
  }

  DateTime _parseTimeString(String timeStr, DateTime referenceDate) {
    DateFormat format = DateFormat("hh:mm a");
    DateTime parsed = format.parse(timeStr);
    return DateTime(referenceDate.year, referenceDate.month, referenceDate.day, parsed.hour, parsed.minute);
  }

  String _getCountdownText(DateTime target) {
    Duration diff = target.difference(DateTime.now());
    int days = diff.inDays;
    int hours = diff.inHours % 24;
    int minutes = diff.inMinutes % 60;

    List<String> parts = [];
    if (days > 0) parts.add("${days}d");
    if (hours > 0) parts.add("${hours}h");
    if (minutes > 0 || parts.isEmpty) parts.add("${minutes}m");

    return parts.join(" ");
  }

  @override
  Widget build(BuildContext context) {
    String currentDay = DateFormat('EEEE').format(DateTime.now());
    String currentDate = DateFormat('MMMM d, y').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false),
        ),
        title: const Text("Dashboard", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchFirestoreData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(currentDay, currentDate),
              const SizedBox(height: 30),
              _buildNextDoseCard(),
              const SizedBox(height: 30),
              const Text("Today's Progress", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildHeader(String day, String date) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Hi, $fullName", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text("$day, $date", style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const Icon(Icons.online_prediction, color: Colors.green),
      ],
    );
  }

  Widget _buildNextDoseCard() {
    if (nextDose == null) {
      return _buildStaticInfoCard("Course Completed!", "You have no upcoming doses within the current schedule range.");
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          const Text("NEXT DOSE IN:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 5),
          Text(_getCountdownText(nextDose!['fullTime']), 
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70), letterSpacing: -1)),
          Text("${nextDose!['name']} • ${nextDose!['pills']} Pill(s)", 
            style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 25),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: 0.6,
              backgroundColor: Colors.grey[100],
              color: const Color(0xFF1A3B70),
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList() {
    if (todaySchedule.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text("No medications assigned for today."),
      ));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: todaySchedule.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final item = todaySchedule[index];
          bool isPast = (item['fullTime'] as DateTime).isBefore(DateTime.now());
          
          return ListTile(
            leading: Icon(item['isDone'] ? Icons.check_circle : Icons.radio_button_off, 
                color: item['isDone'] ? Colors.green : (isPast ? Colors.red.shade300 : Colors.blueGrey.shade300)),
            title: Text(item['displayTime'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(item['name'], style: TextStyle(color: Colors.grey.shade600)),
            trailing: Text(
              item['isDone'] ? "Taken" : (isPast ? "Missed" : "Upcoming"), 
              style: TextStyle(
                color: item['isDone'] ? Colors.green : (isPast ? Colors.red : Colors.blueGrey), 
                fontWeight: FontWeight.bold,
                fontSize: 12
              )
            ),
          );
        },
      ),
    );
  }

  Widget _buildStaticInfoCard(String title, String sub) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Column(children: [
        Icon(Icons.calendar_today_outlined, color: Colors.blue.shade200, size: 40),
        const SizedBox(height: 15),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
    );
  }
}