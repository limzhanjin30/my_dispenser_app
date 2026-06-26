import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'patient_dashboard.dart';
import 'patient_overall_schedule.dart'; 
import '../custom_bottom_nav.dart';

class PatientSchedule extends StatefulWidget {
  final String userEmail;
  final DateTime? initialDate; 

  const PatientSchedule({super.key, required this.userEmail, this.initialDate});

  @override
  State<PatientSchedule> createState() => _PatientScheduleState();
}

class _PatientScheduleState extends State<PatientSchedule> {
  late DateTime _selectedDate;
  String? _linkedMachineId;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _fetchMachineId();
  }

  // --- DATABASE: LOOKUP LINKED HARDWARE SERIAL ID ---
  Future<void> _fetchMachineId() async {
    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isInitializing = false;
        });
      } else {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint("Error fetching machine ID: $e");
      setState(() => _isInitializing = false);
    }
  }

  // --- LOGIC: CHRONOLOGICAL RANGE VALIDATION ---
  bool _isMedActiveOnDate(Map<String, dynamic> med, DateTime date) {
    if (med['startDate'] == null || med['endDate'] == null || med['startDate'] == "") return false;

    DateTime start = DateTime.parse(med['startDate']);
    DateTime end = DateTime.parse(med['endDate']);
    
    DateTime checkDate = DateTime(date.year, date.month, date.day);
    DateTime startDate = DateTime(start.year, start.month, start.day);
    DateTime endDate = DateTime(end.year, end.month, end.day);

    if (checkDate.isBefore(startDate) || checkDate.isAfter(endDate)) return false;

    String freq = med['frequency'] ?? "Everyday";
    if (freq == "Everyday") return true;
    
    if (freq.contains("Every") && freq.contains("Days")) {
      try {
        int days = int.parse(freq.split(' ')[1]);
        int difference = checkDate.difference(startDate).inDays;
        return difference % days == 0;
      } catch (e) { return true; }
    }
    return true;
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    final String cleanUserEmail = widget.userEmail.trim().toLowerCase();
    final String currentSelectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail))),
        ),
        title: const Text("Daily Medication", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined, color: Color(0xFF1A3B70)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PatientOverallSchedule(userEmail: widget.userEmail))),
          ),
        ],
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: _isInitializing 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
          : Column(
        children: [
          // --- DATE SELECTOR BAR COMPONENT ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeDate(-1)),
                Column(
                  children: [
                    Text(DateFormat('EEEE').format(_selectedDate).toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
                    Text(DateFormat('MMM d, yyyy').format(_selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeDate(1)),
              ],
            ),
          ),

          // --- REAL-TIME COMBINED HARDWARE/LOG ENGINE STREAM ---
          Expanded(
            child: _linkedMachineId == null 
              ? _buildEmptyState("Please link your machine in settings.")
              : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
              builder: (context, machineSnapshot) {
                if (machineSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!machineSnapshot.hasData || !machineSnapshot.data!.exists) return _buildEmptyState("No machine data found.");
                
                var machineData = machineSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                
                String rootMachineOwner = (machineData['linkedPatientEmail'] ?? "").toString().toLowerCase().trim();
                if (rootMachineOwner != cleanUserEmail) {
                  return _buildEmptyState("This hardware array terminal is currently linked to another user.");
                }

                List<dynamic> allSlots = machineData['slots'] ?? [];

                // Filter slots active on this selected day
                List<dynamic> activeSlotsToday = allSlots.where((slot) {
                  var slotMap = slot as Map<String, dynamic>? ?? {};
                  String status = slotMap['status'] ?? "";
                  bool isValidStatus = (status == "Occupied" || status == "Finished");
                  
                  return isValidStatus && _isMedActiveOnDate(slotMap, _selectedDate);
                }).toList();

                if (activeSlotsToday.isEmpty) return _buildEmptyState("No medication scheduled for this date.");

                // Nesting a StreamBuilder directly targeting the specific calendar date logs
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('adherence_logs')
                      .where('patientEmail', isEqualTo: cleanUserEmail)
                      .where('date', isEqualTo: currentSelectedDateStr)
                      .snapshots(),
                  builder: (context, logSnapshot) {
                    if (logSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    
                    // Create an easily queryable map from logs targeting today's date context
                    Map<int, List<DocumentSnapshot>> dailyLogsBySlot = {};
                    if (logSnapshot.hasData) {
                      for (var doc in logSnapshot.data!.docs) {
                        int slotNum = (doc.get('slot') as num).toInt();
                        dailyLogsBySlot.putIfAbsent(slotNum, () => []).add(doc);
                      }
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: activeSlotsToday.length,
                      itemBuilder: (context, index) {
                        final med = activeSlotsToday[index];
                        int slotNum = (med['slot'] as num).toInt();
                        
                        // Extract adherence history entries for this specific box allocation mapping
                        List<DocumentSnapshot> slotLogsToday = dailyLogsBySlot[slotNum] ?? [];

                        // Migration processing check for time field string format conversion
                        String singleTimeStr = "00:00 AM";
                        if (med['times'] != null) {
                          if (med['times'] is String) {
                            singleTimeStr = med['times'];
                          } else if (med['times'] is List && (med['times'] as List).isNotEmpty) {
                            singleTimeStr = med['times'][0].toString();
                          }
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: ScheduleCard(
                            slotNumber: slotNum.toString(),
                            time: singleTimeStr,
                            medDetails: med['medDetails'] ?? "Medication",
                            mealCondition: med['mealCondition'] ?? "Anytime",
                            status: med['status'] ?? "Occupied", 
                            selectedDate: _selectedDate, 
                            dateSpecificLogs: slotLogsToday, 
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 1, role: "Patient", userEmail: widget.userEmail),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.event_note, size: 60, color: Colors.blue.withOpacity(0.1)),
        const SizedBox(height: 15),
        Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
      ]),
    ));
  }
}

class ScheduleCard extends StatelessWidget {
  final String slotNumber;
  final String time;
  final String medDetails;
  final String mealCondition;
  final String status;
  final DateTime selectedDate;
  final List<DocumentSnapshot> dateSpecificLogs; 

  const ScheduleCard({
    super.key, 
    required this.slotNumber, 
    required this.time, 
    required this.medDetails, 
    required this.mealCondition, 
    required this.status,
    required this.selectedDate,
    required this.dateSpecificLogs,
  });

  // --- 🎯 HISTORIC LOG TELEMETRY DATA TIME SLOT BADGE EVALUATOR ---
  Map<String, dynamic> _getTimeSlotStatus(String timeStr) {
    try {
      if (status == "Finished") {
        return {"label": "COMPLETED", "color": Colors.blue, "bgColor": Colors.blue.withOpacity(0.1), "isChecked": true};
      }

      // Check if there is an explicit log document generated matching this exact time string
      DocumentSnapshot? specificTimeLog;
      for (var log in dateSpecificLogs) {
        String logTime = "00:00 AM";
        var rawTimesField = log.get('times');
        
        if (rawTimesField is String) {
          logTime = rawTimesField;
        } else if (rawTimesField is List && rawTimesField.isNotEmpty) {
          logTime = rawTimesField[0].toString();
        }

        if (logTime.trim() == timeStr.trim()) {
          specificTimeLog = log;
          break;
        }
      }

      // Parse scheduled alarm metrics matching active viewport target values
      DateTime scheduledTime = DateFormat("yyyy-MM-dd hh:mm a").parse(
        "${DateFormat('yyyy-MM-dd').format(selectedDate)} $timeStr"
      );
      DateTime now = DateTime.now();

      // If a log document is found, determine status from its localized fields
      if (specificTimeLog != null) {
        bool logIsDone = specificTimeLog.get('isDone') == true;
        String logAdherenceStatus = specificTimeLog.get('adherenceStatus') ?? "Upcoming";
        String actualTakenTime = specificTimeLog.get('lastTakenTime') ?? "";

        if (logIsDone || logAdherenceStatus == "Taken") {
          if (actualTakenTime.isNotEmpty) {
            try {
              DateTime actualTakenDateTime = DateFormat("yyyy-MM-dd hh:mm a").parse(
                "${DateFormat('yyyy-MM-dd').format(selectedDate)} $actualTakenTime"
              );
              if (actualTakenDateTime.isAfter(scheduledTime.add(const Duration(minutes: 30)))) {
                return {"label": "LATE INTAKE", "color": Colors.purple, "bgColor": Colors.purple.withOpacity(0.1), "isChecked": true};
              }
            } catch (_) {}
          }
          return {"label": "TAKEN", "color": Colors.green, "bgColor": Colors.green.withOpacity(0.1), "isChecked": true};
        }
        
        if (logAdherenceStatus == "Missed") {
          return {"label": "MISSED", "color": Colors.red, "bgColor": Colors.red.withOpacity(0.1), "isChecked": false};
        }
      }

      // Fallback manual delta evaluation bounds if an individual explicit log reference tree is missing
      if (now.isAfter(scheduledTime.add(const Duration(hours: 1)))) {
        return {"label": "MISSED", "color": Colors.red, "bgColor": Colors.red.withOpacity(0.1), "isChecked": false};
      } else if (now.isAfter(scheduledTime)) {
        return {"label": "DUE NOW", "color": Colors.orange, "bgColor": Colors.orange.withOpacity(0.1), "isChecked": false};
      } else {
        return {"label": "UPCOMING", "color": Colors.grey.shade600, "bgColor": Colors.grey.withOpacity(0.1), "isChecked": false};
      }
    } catch (e) {
      return {"label": "PENDING", "color": Colors.grey, "bgColor": Colors.grey.withOpacity(0.1), "isChecked": false};
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isFinished = status == "Finished";
    final statusData = _getTimeSlotStatus(time);
    bool isEntireCardChecked = isFinished || statusData['isChecked'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isFinished ? const Color(0xFFF0F7FF) : Colors.white, 
        borderRadius: BorderRadius.circular(15), 
        border: isFinished ? Border.all(color: Colors.blue.shade100) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFinished ? Colors.blue.shade100 : const Color(0xFF1A3B70).withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Text(
                  isFinished ? "COURSE COMPLETED" : "BIN SLOT $slotNumber", 
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isFinished ? Colors.blue.shade800 : const Color(0xFF1A3B70))
                ),
              ),
              Icon(
                isEntireCardChecked ? Icons.check_circle : Icons.radio_button_unchecked, 
                color: isEntireCardChecked ? Colors.green : Colors.grey.shade300
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            medDetails, 
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.bold, 
              color: isFinished ? Colors.blueGrey : const Color(0xFF1A3B70),
            )
          ),
          const SizedBox(height: 5),
          Text(mealCondition, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isFinished ? Colors.grey : Colors.orange[800])),
          const Divider(height: 30),
          const Text("SCHEDULED TIME & REAL-TIME STATUS:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          
          // --- REAL-TIME TELEMETRY TRACKING CHIP ---
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100)
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, size: 14, color: const Color(0xFF1A3B70).withOpacity(0.6)),
                const SizedBox(width: 6),
                Text(
                  time, 
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusData['bgColor'],
                    borderRadius: BorderRadius.circular(6)
                  ),
                  child: Text(
                    statusData['label'],
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusData['color']),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}