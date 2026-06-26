import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CaregiverBoxOpenClose extends StatefulWidget {
  final String userEmail;
  const CaregiverBoxOpenClose({super.key, required this.userEmail});

  @override
  State<CaregiverBoxOpenClose> createState() => _CaregiverBoxOpenCloseState();
}

class _CaregiverBoxOpenCloseState extends State<CaregiverBoxOpenClose> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _patientBinGroupedLogs = [];

  @override
  void initState() {
    super.initState();
    _forceTelemetrySyncAndLoad();
  }

  Future<void> _forceTelemetrySyncAndLoad() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> compiledGroups = [];
    final String cleanCaregiverEmail = widget.userEmail.trim().toLowerCase();
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // 1. Fetch all linked patient profiles
      var connectionSnap = await FirebaseFirestore.instance
          .collection('connections')
          .where('caregiverEmail', isEqualTo: cleanCaregiverEmail)
          .get();

      List<String> patientEmails = connectionSnap.docs
          .map((d) => d.get('patientEmail').toString().toLowerCase().trim())
          .toList();

      if (patientEmails.isNotEmpty) {
        // 2. Query target patient device hubs
        var machineSnap = await FirebaseFirestore.instance
            .collection('machines')
            .where('linkedPatientEmail', whereIn: patientEmails)
            .get();

        for (var doc in machineSnap.docs) {
          var mData = doc.data();
          String patientEmail = mData['linkedPatientEmail'] ?? "Unknown";
          List<dynamic> slots = List.from(mData['slots'] ?? []);

          var userSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: patientEmail)
              .limit(1)
              .get();
          String patientName = userSnap.docs.isNotEmpty ? (userSnap.docs.first.get('name') ?? patientEmail) : patientEmail;

          for (var slotMap in slots) {
            int slotNum = slotMap['slot'] ?? 0;

            // Extract open and close logs string/arrays safely
            dynamic rawOpen = slotMap['boxOpenTimes'] ?? slotMap['boxOpenTime'] ?? [];
            dynamic rawClose = slotMap['boxCloseTimes'] ?? slotMap['boxCloseTime'] ?? [];

            List<String> machineOpenTimes = rawOpen is List 
                ? List<String>.from(rawOpen.map((e) => e.toString())) 
                : (rawOpen is String && rawOpen.isNotEmpty ? rawOpen.split(',').map((e) => e.trim()).toList() : []);

            List<String> machineCloseTimes = rawClose is List 
                ? List<String>.from(rawClose.map((e) => e.toString())) 
                : (rawClose is String && rawClose.isNotEmpty ? rawClose.split(',').map((e) => e.trim()).toList() : []);

            // 🎯 EXECUTE EXPLICIT BACKGROUND SYNCHRONIZATION TO ADHERENCE LOGS
            try {
              var todayLogQuery = await FirebaseFirestore.instance
                  .collection('adherence_logs')
                  .where('patientEmail', isEqualTo: patientEmail)
                  .where('date', isEqualTo: todayStr)
                  .where('slot', isEqualTo: slotNum)
                  .get();

              if (todayLogQuery.docs.isNotEmpty) {
                WriteBatch logSyncBatch = FirebaseFirestore.instance.batch();
                bool updatesPending = false;

                for (var logDoc in todayLogQuery.docs) {
                  var logData = logDoc.data();
                  dynamic logOpenData = logData['boxOpenTime'] ?? [];
                  dynamic logCloseData = logData['boxCloseTime'] ?? [];

                  List<String> logOpenHistory = logOpenData is List 
                      ? List<String>.from(logOpenData.map((e) => e.toString())) 
                      : (logOpenData is String ? logOpenData.split(',').map((e) => e.trim()).toList() : []);

                  List<String> logCloseHistory = logCloseData is List 
                      ? List<String>.from(logCloseData.map((e) => e.toString())) 
                      : (logCloseData is String ? logCloseData.split(',').map((e) => e.trim()).toList() : []);

                  Map<String, dynamic> updatePayload = {};

                  if (machineOpenTimes.join(',') != logOpenHistory.join(',')) {
                    updatePayload['boxOpenTime'] = machineOpenTimes;
                    updatesPending = true;
                  }
                  if (machineCloseTimes.join(',') != logCloseHistory.join(',')) {
                    updatePayload['boxCloseTime'] = machineCloseTimes;
                    updatesPending = true;
                  }

                  if (updatesPending && updatePayload.isNotEmpty) {
                    logSyncBatch.update(logDoc.reference, updatePayload);
                  }
                }
                if (updatesPending) await logSyncBatch.commit();
              }
            } catch (e) {
              debugPrint("Background sync failure inside telemetry screen: $e");
            }

            // Only group the bin layout card block if there is a timestamp present inside the arrays
            if (machineOpenTimes.isNotEmpty || machineCloseTimes.isNotEmpty) {
              compiledGroups.add({
                "patientName": patientName,
                "slotNum": slotNum,
                "openTimes": machineOpenTimes,
                "closeTimes": machineCloseTimes,
              });
            }
          }
        }
      }

      // Sort groupings by patient name, then bin assignment channel order indices
      compiledGroups.sort((a, b) {
        int comp = a['patientName'].toString().compareTo(b['patientName'].toString());
        if (comp != 0) return comp;
        return (a['slotNum'] as int).compareTo(b['slotNum'] as int);
      });

      setState(() {
        _patientBinGroupedLogs = compiledGroups;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error grouping compilation task: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: const Color(0xFF1A3B70),
        title: const Text("Device Access Feed", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
            onPressed: _isLoading ? null : _forceTelemetrySyncAndLoad,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
          : _patientBinGroupedLogs.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _patientBinGroupedLogs.length,
                  itemBuilder: (context, index) {
                    final group = _patientBinGroupedLogs[index];
                    return _buildBinGroupCard(group);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gpp_good, size: 65, color: Colors.green.withOpacity(0.4)),
          const SizedBox(height: 15),
          const Text("No History Detected", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Text("All physical hardware channels are reporting closed records.", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildBinGroupCard(Map<String, dynamic> group) {
    List<String> opens = List<String>.from(group['openTimes']);
    List<String> closes = List<String>.from(group['closeTimes']);

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar containing Patient details + target slot ID tag block
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(group['patientName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A3B70))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF1A3B70).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text("Bin ${group['slotNum']}", style: const TextStyle(color: Color(0xFF1A3B70), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 15),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔓 LEFT COLUMN: OPEN TIME METRICS LIST
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_open, size: 14, color: Colors.orange),
                          SizedBox(width: 6),
                          Text("Open Log History", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      opens.isEmpty 
                        ? // 🎯 THE FIX:
                          const Text(
                            "No entries recorded", 
                            style: TextStyle(
                              fontSize: 11, 
                              color: Colors.grey, 
                              fontStyle: FontStyle.italic, // 👈 Changed parameter to fontStyle
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: opens.map((time) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(time, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                            )).toList(),
                          ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 10),
                
                // 🔒 RIGHT COLUMN: CLOSE TIME METRICS LIST
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock, size: 14, color: Colors.green),
                          SizedBox(width: 6),
                          Text("Close Log History", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      closes.isEmpty 
                        ? // 🎯 THE FIX:
                          const Text(
                            "No entries recorded", 
                            style: TextStyle(
                              fontSize: 11, 
                              color: Colors.grey, 
                              fontStyle: FontStyle.italic, // 👈 Changed parameter to fontStyle
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: closes.map((time) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(time, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                            )).toList(),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}