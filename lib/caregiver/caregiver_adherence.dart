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
  String? _linkedMachineId;
  DateTime _currentWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  // --- DATABASE: LOOKUP ---
  Future<void> _fetchMachineId(String pEmail) async {
    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
        });
      }
    } catch (e) {
      debugPrint("Adherence Init Error: $e");
    }
  }

  // --- LOGIC: PERSISTENT HISTORY CALCULATION ---
  String _calculateStatus(Map<String, dynamic> slot, DateTime date, String timeStr) {
    DateTime now = DateTime.now();
    DateTime checkDay = DateTime(date.year, date.month, date.day);
    DateTime today = DateTime(now.year, now.month, now.day);
    String checkDayStr = DateFormat('yyyy-MM-dd').format(checkDay);

    if (slot['startDate'] == null || slot['endDate'] == null || slot['startDate'] == "") return "Inactive";
    DateTime start = DateTime.parse(slot['startDate']);
    DateTime end = DateTime.parse(slot['endDate']);
    
    // Check if medication was active on this specific calendar day
    if (checkDay.isBefore(DateTime(start.year, start.month, start.day)) || 
        checkDay.isAfter(DateTime(end.year, end.month, end.day))) return "Inactive";

    // 1. DATA CHECK: Was it taken? (Works even if status is now "Finished")
    if (slot['lastTakenDate'] == checkDayStr) {
      String adj = slot['adherenceStatus'] ?? "Taken"; 
      return "$adj at ${slot['lastTakenTime'] ?? 'Unknown'}";
    }

    // 2. TIMING CHECK: If not taken, was it missed?
    try {
      DateTime parsedTime = DateFormat("hh:mm a").parse(timeStr);
      DateTime fullScheduledTime = DateTime(date.year, date.month, date.day, parsedTime.hour, parsedTime.minute);
      DateTime graceLimit = fullScheduledTime.add(const Duration(minutes: 30));

      if (now.isAfter(graceLimit)) {
        // If course is finished, we don't label future dates as "Missed"
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

  // --- CALENDAR HELPERS ---
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: _currentWeekStart, firstDate: DateTime(2024), lastDate: DateTime(2030));
    if (picked != null) setState(() => _currentWeekStart = picked.subtract(Duration(days: picked.weekday - 1)));
  }

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
        title: const Text("Adherence History", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPatientSelector(),
          
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeWeek(-1)),
                GestureDetector(
                  onTap: () => _selectDate(context),
                  child: Column(
                    children: [
                      const Text("Viewing History:", style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                      Text(_getWeekRangeString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeWeek(1)),
              ],
            ),
          ),

          Expanded(
            child: _selectedPatientEmail == null 
              ? _buildEmptyState("Select a patient to view their performance logs.")
              : (_linkedMachineId == null 
                  ? _buildEmptyState("No machine found for this patient.")
                  : _buildLogsList()),
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
            decoration: InputDecoration(labelText: "Adherence Monitoring", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
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

  Widget _buildLogsList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("Configuration not found.");

        var data = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> slots = data['slots'] ?? [];

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 7, 
          itemBuilder: (context, dayIndex) {
            DateTime currentDay = _currentWeekStart.add(Duration(days: dayIndex));
            List<Map<String, dynamic>> dailyDoses = [];
            
            for (var slot in slots) {
              // LOGIC: Show slots that are Occupied OR Finished (to keep records visible)
              if (slot['patientEmail'] == _selectedPatientEmail?.trim().toLowerCase() && 
                  (slot['status'] == "Occupied" || slot['status'] == "Finished")) {
                List<String> timings = List<String>.from(slot['times'] ?? []);
                for (var time in timings) {
                  dailyDoses.add({
                    "time": time, 
                    "details": slot['medDetails'] ?? "Med", 
                    "slot": slot['slot'], 
                    "originalSlot": slot,
                    "isFinished": slot['status'] == "Finished"
                  });
                }
              }
            }

            dailyDoses.sort((a, b) => DateFormat("hh:mm a").parse(a['time']).compareTo(DateFormat("hh:mm a").parse(b['time'])));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(DateFormat('EEEE, MMM d').format(currentDay), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700, fontSize: 13)),
                ),
                ...dailyDoses.map((dose) {
                  String status = _calculateStatus(dose['originalSlot'], currentDay, dose['time']);
                  if (status == "Inactive") return const SizedBox.shrink();
                  
                  return _buildAdherenceCard(
                    "${dose['time']} - ${dose['details']} (Bin ${dose['slot']})", 
                    status, 
                    _getStatusColor(status),
                    dose['isFinished']
                  );
                }),
                if (dailyDoses.isEmpty) const Padding(padding: EdgeInsets.only(left: 5, bottom: 5), child: Text("No schedule for this day.", style: TextStyle(color: Colors.grey, fontSize: 11))),
                const Divider(height: 30),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAdherenceCard(String label, String status, Color color, bool isFinished) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color, 
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              if (isFinished) const Text("COMPLETED COURSE", style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
            child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Padding(padding: const EdgeInsets.all(40.0), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13))));
}