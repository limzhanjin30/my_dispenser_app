import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'healthcare_dashboard.dart';
import '../custom_bottom_nav.dart';
import '../modals/user_modal.dart'; 

class HealthcareAdherence extends StatefulWidget {
  final String userEmail;
  const HealthcareAdherence({super.key, required this.userEmail});

  @override
  State<HealthcareAdherence> createState() => _HealthcareAdherenceState();
}

class _HealthcareAdherenceState extends State<HealthcareAdherence> {
  String fullName = "Healthcare Provider";
  String? _selectedPatientEmail;
  String? _linkedMachineId;
  DateTime _currentWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  bool _isDataLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchProviderName();
  }

  void _fetchProviderName() {
    final user = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase(),
      orElse: () => {},
    );
    if (user.isNotEmpty) {
      setState(() => fullName = user['name'] ?? "Healthcare Provider");
    }
  }

  // --- DATABASE: LOOKUP PATIENT MACHINE ---
  Future<void> _fetchMachineId(String pEmail) async {
    setState(() => _isDataLoading = true);
    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isDataLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Adherence Fetch Error: $e");
      setState(() => _isDataLoading = false);
    }
  }

  // --- LOGIC: ADHERENCE STATUS CALCULATION ---
  String _calculateStatus(Map<String, dynamic> slot, DateTime date, String timeStr) {
    DateTime now = DateTime.now();
    DateTime checkDay = DateTime(date.year, date.month, date.day);
    String checkDayStr = DateFormat('yyyy-MM-dd').format(checkDay);

    if (slot['startDate'] == null || slot['endDate'] == null || slot['startDate'] == "") return "Inactive";
    DateTime start = DateTime.parse(slot['startDate']);
    DateTime end = DateTime.parse(slot['endDate']);
    
    if (checkDay.isBefore(DateTime(start.year, start.month, start.day)) || 
        checkDay.isAfter(DateTime(end.year, end.month, end.day))) return "Inactive";

    if (slot['lastTakenDate'] == checkDayStr) {
      String adj = slot['adherenceStatus'] ?? "Taken"; 
      return "$adj at ${slot['lastTakenTime'] ?? 'Unknown'}";
    }

    try {
      DateTime parsedTime = DateFormat("hh:mm a").parse(timeStr);
      DateTime fullScheduledTime = DateTime(date.year, date.month, date.day, parsedTime.hour, parsedTime.minute);
      DateTime graceLimit = fullScheduledTime.add(const Duration(minutes: 30));

      if (now.isAfter(graceLimit)) {
        if (slot['status'] == "Finished" && checkDay.isAfter(end)) return "Inactive";
        return "Missed";
      }
    } catch (e) {
      return "Upcoming";
    }
    return "Upcoming";
  }

  Color _getStatusColor(String status) {
    if (status.contains("Late")) return Colors.orange;
    if (status.contains("Taken")) return Colors.green;
    if (status == "Missed") return Colors.redAccent;
    return Colors.blueGrey;
  }

  // --- UI HELPERS ---
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
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A3B70)),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HealthcareDashboard(userEmail: widget.userEmail))),
        ),
        title: Text(fullName, style: const TextStyle(color: Color(0xFF1A3B70), fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPatientSelector(),
          _buildWeekNavigator(),
          Expanded(
            child: _selectedPatientEmail == null 
              ? _buildEmptyState("Select a patient to review adherence logs.")
              : (_linkedMachineId == null && !_isDataLoading
                  ? _buildEmptyState("No hardware linked to this patient.")
                  : _buildLogsList()),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 2, role: "Healthcare\nProvider", userEmail: widget.userEmail),
    );
  }

  Widget _buildPatientSelector() {
    // Note: Healthcare providers view connections where they are the assigned provider
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('connections').where('healthcareEmail', isEqualTo: widget.userEmail.trim().toLowerCase()).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        var connections = snapshot.data!.docs;
        return Container(
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: DropdownButtonFormField<String>(
            value: _selectedPatientEmail,
            hint: const Text("Select Patient to Audit"),
            decoration: InputDecoration(labelText: "Clinical Audit", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: connections.map((c) => DropdownMenuItem(value: c.get('patientEmail').toString(), child: Text(c.get('patientEmail')))).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() { _selectedPatientEmail = val; _linkedMachineId = null; });
                _fetchMachineId(val);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildWeekNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeWeek(-1)),
          Text(_getWeekRangeString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A3B70))),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeWeek(1)),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _isDataLoading) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("Hardware data unavailable.");

        var slots = List.from(snapshot.data!.get('slots') ?? []);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 7,
          itemBuilder: (context, dayIndex) {
            DateTime currentDay = _currentWeekStart.add(Duration(days: dayIndex));
            List<Map<String, dynamic>> dailyDoses = [];
            
            for (var slot in slots) {
              if (slot['patientEmail'] == _selectedPatientEmail?.trim().toLowerCase() && 
                  (slot['status'] == "Occupied" || slot['status'] == "Finished")) {
                List<String> timings = List<String>.from(slot['times'] ?? []);
                for (var time in timings) {
                  dailyDoses.add({"time": time, "details": slot['medDetails'], "slot": slot['slot'], "originalSlot": slot, "isFinished": slot['status'] == "Finished"});
                }
              }
            }

            dailyDoses.sort((a, b) => DateFormat("hh:mm a").parse(a['time']).compareTo(DateFormat("hh:mm a").parse(b['time'])));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(DateFormat('EEEE, MMM d').format(currentDay), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                ),
                ...dailyDoses.map((dose) {
                  String status = _calculateStatus(dose['originalSlot'], currentDay, dose['time']);
                  if (status == "Inactive") return const SizedBox.shrink();
                  return _buildAdherenceCard(dose, status);
                }),
                if (dailyDoses.isEmpty) const Text("No prescriptions for this day.", style: TextStyle(color: Colors.grey, fontSize: 11)),
                const Divider(height: 30),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAdherenceCard(Map<String, dynamic> dose, String status) {
    Color color = _getStatusColor(status);
    bool isFinished = dose['isFinished'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${dose['time']} - ${dose['details']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text("Slot ${dose['slot']} ${isFinished ? '• COMPLETED COURSE' : ''}", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
            child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Padding(padding: const EdgeInsets.all(40.0), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13))));
}