import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PatientOverallSchedule extends StatefulWidget {
  final String userEmail;
  const PatientOverallSchedule({super.key, required this.userEmail});

  @override
  State<PatientOverallSchedule> createState() => _PatientOverallScheduleState();
}

class _PatientOverallScheduleState extends State<PatientOverallSchedule> {
  String? _linkedMachineId;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _fetchMachineId();
  }

  // --- STEP 1: FIND LINKED HARDWARE ---
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
      debugPrint("Machine ID Fetch Error: $e");
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        title: const Text("Prescription Master List", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0.5,
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
          : _linkedMachineId == null
              ? _buildEmptyState("No hardware dispenser linked to your account.")
              : StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('machines')
                      .doc(_linkedMachineId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return _buildEmptyState("Machine configuration not found.");
                    }

                    var data = snapshot.data!.data() as Map<String, dynamic>;
                    List<dynamic> allSlots = data['slots'] ?? [];

                    // --- STEP 2: FILTER BY EMAIL + STATUS (Occupied OR Finished) ---
                    final String myEmail = widget.userEmail.trim().toLowerCase();
                    List<dynamic> myMeds = allSlots.where((slot) {
                      bool belongsToMe = slot['patientEmail'] == myEmail;
                      String status = slot['status'] ?? "";
                      return belongsToMe && (status == "Occupied" || status == "Finished");
                    }).toList();

                    if (myMeds.isEmpty) {
                      return _buildEmptyState("You currently have no active or completed medications in this machine.");
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: myMeds.length,
                      itemBuilder: (context, index) {
                        final med = myMeds[index];
                        return _buildPrescriptionCard(med);
                      },
                    );
                  },
                ),
    );
  }

  Widget _buildPrescriptionCard(Map<String, dynamic> med) {
    bool isFinished = med['status'] == "Finished";

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: isFinished ? Colors.blue.shade100 : Colors.grey.shade200),
      ),
      color: isFinished ? const Color(0xFFF0F7FF) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    med['medDetails'] ?? "Unknown Medication", 
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold, 
                      color: isFinished ? Colors.blueGrey : const Color(0xFF1A3B70)
                    )
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isFinished ? Colors.blue.shade100 : Colors.blue.shade50, 
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Text(
                    isFinished ? "COMPLETED" : "Slot ${med['slot']}", 
                    style: TextStyle(
                      fontSize: 10, 
                      fontWeight: FontWeight.bold, 
                      color: isFinished ? Colors.blue.shade800 : Colors.blue
                    )
                  ),
                )
              ],
            ),
            const SizedBox(height: 15),
            const Divider(),
            const SizedBox(height: 10),
            _infoRow(Icons.repeat, "Frequency", med['frequency'] ?? "Daily", isFinished),
            _infoRow(Icons.date_range, "Course Period", "${med['startDate']} to ${med['endDate']}", isFinished),
            _infoRow(Icons.access_time, "Alarm Schedule", (med['times'] as List).join(', '), isFinished),
            _infoRow(Icons.restaurant, "Instructions", med['mealCondition'] ?? "After Meal", isFinished),
            
            // Physical Lock/Finish Status
            const SizedBox(height: 15),
            Row(
              children: [
                Icon(
                  isFinished ? Icons.verified : Icons.lock, 
                  size: 14, 
                  color: isFinished ? Colors.blue : (med['isLocked'] == true ? Colors.green : Colors.grey)
                ),
                const SizedBox(width: 8),
                Text(
                  isFinished ? "Course Finished & Bin Released" : (med['isLocked'] == true ? "Physical Bin Locked" : "Bin Unlocked"),
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.bold, 
                    color: isFinished ? Colors.blue : (med['isLocked'] == true ? Colors.green : Colors.grey)
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, bool isFinished) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: isFinished ? Colors.blueGrey.withOpacity(0.5) : Colors.grey.shade600),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isFinished ? Colors.blueGrey : Colors.black87)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 60, color: Colors.blue.withOpacity(0.1)),
            const SizedBox(height: 15),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}