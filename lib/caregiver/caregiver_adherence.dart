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
  DateTime _currentWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentWeekStart,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _currentWeekStart = picked.subtract(Duration(days: picked.weekday - 1));
      });
    }
  }

  void _changeWeek(int weeks) {
    setState(() {
      _currentWeekStart = _currentWeekStart.add(Duration(days: weeks * 7));
    });
  }

  String _getWeekRangeString() {
    DateTime end = _currentWeekStart.add(const Duration(days: 6));
    return "${DateFormat('MMM d').format(_currentWeekStart)} - ${DateFormat('MMM d, yyyy').format(end)}";
  }

  // --- UPDATED STATUS LOGIC: COMPARES SPECIFIC DOSE TIMES ---
  String _calculateStatus(Map<String, dynamic> slot, DateTime date, String timeStr) {
    DateTime now = DateTime.now();
    DateTime checkDay = DateTime(date.year, date.month, date.day);
    DateTime today = DateTime(now.year, now.month, now.day);

    if (slot['startDate'] == null || slot['endDate'] == null) return "Inactive";
    DateTime start = DateTime.parse(slot['startDate']);
    DateTime end = DateTime.parse(slot['endDate']);
    
    if (checkDay.isBefore(DateTime(start.year, start.month, start.day)) || 
        checkDay.isAfter(DateTime(end.year, end.month, end.day))) return "Inactive";

    bool isDone = slot['isDone'] ?? false;

    // Past Days logic
    if (checkDay.isBefore(today)) {
       return isDone ? "Taken" : "Missed";
    } 
    
    // Today logic: compare current time vs dose time
    if (checkDay.isAtSameMomentAs(today)) {
       if (isDone) return "Taken";
       
       // Parse the dose time string (e.g., "08:00 AM")
       try {
         DateTime doseTimeToday = DateFormat("hh:mm a").parse(timeStr);
         DateTime fullDoseDateTime = DateTime(now.year, now.month, now.day, doseTimeToday.hour, doseTimeToday.minute);
         
         return now.isAfter(fullDoseDateTime) ? "Missed" : "Upcoming";
       } catch (e) {
         return "Upcoming";
       }
    } 
    
    // Future Days logic
    return "Upcoming";
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Taken": return Colors.green;
      case "Missed": return Colors.redAccent;
      case "Upcoming": return Colors.blueGrey;
      default: return Colors.grey.shade300;
    }
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
                      const Text("View Week Of:", style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                      Text(_getWeekRangeString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeWeek(1)),
              ],
            ),
          ),

          Expanded(
            child: _selectedPatientEmail == null 
              ? _buildEmptyState("Please select a patient above to view adherence.")
              : _buildLogsList(),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 2, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  Widget _buildPatientSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('connections')
          .where('caregiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase())
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        var connections = snapshot.data!.docs;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: Colors.white,
          child: DropdownButtonFormField<String>(
            value: _selectedPatientEmail,
            hint: const Text("Select Patient"),
            decoration: InputDecoration(
              labelText: "Monitoring Patient",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: connections.map((c) {
              String email = c.get('patientEmail');
              return DropdownMenuItem(value: email, child: Text(email, style: const TextStyle(fontSize: 14)));
            }).toList(),
            onChanged: (val) => setState(() => _selectedPatientEmail = val),
          ),
        );
      },
    );
  }

  Widget _buildLogsList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('schedules').doc(_selectedPatientEmail!.toLowerCase()).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("No schedule found for this patient.");

        var data = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> slots = data['slots'] ?? [];

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: 7, 
          itemBuilder: (context, dayIndex) {
            DateTime currentDay = _currentWeekStart.add(Duration(days: dayIndex));
            
            // Extract all time-specific doses for this day
            List<Map<String, dynamic>> dailyDoses = [];
            for (var slot in slots) {
              if (slot['name'] != null && !slot['name'].toString().contains("Empty Slot")) {
                List<String> timings = List<String>.from(slot['times'] ?? []);
                for (var time in timings) {
                  dailyDoses.add({
                    "time": time,
                    "name": slot['name'],
                    "pills": slot['pills'],
                    "originalSlot": slot
                  });
                }
              }
            }

            // Sort doses by time (AM to PM)
            dailyDoses.sort((a, b) => DateFormat("hh:mm a").parse(a['time']).compareTo(DateFormat("hh:mm a").parse(b['time'])));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(DateFormat('EEEE, MMM d').format(currentDay), 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                ),
                ...dailyDoses.map((dose) {
                  String status = _calculateStatus(dose['originalSlot'], currentDay, dose['time']);
                  if (status == "Inactive") return const SizedBox.shrink();

                  // RENDER: [Time] - [Name] ([Pills])
                  return _buildAdherenceCard(
                    "${dose['time']} - ${dose['name']} (${dose['pills']} pill(s))", 
                    status, 
                    _getStatusColor(status)
                  );
                }),
                if (dailyDoses.isEmpty) const Text("No medication scheduled.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                const Divider(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAdherenceCard(String label, String status, Color color) {
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
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
            child: Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40.0),
      child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
    ));
  }
}