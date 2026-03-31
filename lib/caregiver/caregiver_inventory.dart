import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import 'caregiver_dashboard.dart';

class CaregiverInventory extends StatefulWidget {
  final String userEmail;
  const CaregiverInventory({super.key, required this.userEmail});

  @override
  State<CaregiverInventory> createState() => _CaregiverInventoryState();
}

class _CaregiverInventoryState extends State<CaregiverInventory> {
  String? _selectedPatientEmail;
  String? _linkedMachineId;
  bool _isLoading = false;

  // --- DATABASE: LOOKUP PATIENT HARDWARE ---
  Future<void> _fetchMachineId(String pEmail) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _linkedMachineId = null;
    });
    
    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Machine Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- LOGIC: REFILL AND LOCK SLOT ---
  Future<void> _refillSlot(int index, List<dynamic> currentSlots) async {
    if (_linkedMachineId == null) return;

    setState(() => _isLoading = true);
    
    // Mark the bin as physically full and engage the hardware lock
    currentSlots[index]['isDone'] = false; 
    currentSlots[index]['isLocked'] = true; 
    // Reset adherence markers for the new refill cycle
    currentSlots[index]['lastTakenDate'] = ""; 
    currentSlots[index]['adherenceStatus'] = "Upcoming";

    try {
      await FirebaseFirestore.instance
          .collection('machines')
          .doc(_linkedMachineId)
          .update({'slots': currentSlots});
      
      _showMsg("Slot ${index + 1} refilled and solenoid locked.", Colors.teal);
    } catch (e) {
      _showMsg("Refill failed: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
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
        title: const Text("Hardware Inventory", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPatientSelector(),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
              : _selectedPatientEmail == null 
                ? _buildEmptyState("Please select a patient to manage their physical bins.")
                : (_linkedMachineId == null 
                    ? _buildEmptyState("This patient has not connected a dispenser yet.")
                    : _buildInventoryGrid()),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 3, role: "Caregiver", userEmail: widget.userEmail),
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
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: DropdownButtonFormField<String>(
            value: _selectedPatientEmail,
            hint: const Text("Select Patient", style: TextStyle(fontSize: 14, color: Colors.grey)),
            decoration: InputDecoration(
              labelText: "Patient Hardware",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            ),
            items: connections.map((c) => DropdownMenuItem(value: c.get('patientEmail').toString(), child: Text(c.get('patientEmail')))).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedPatientEmail = val);
                _fetchMachineId(val);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildInventoryGrid() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("Error: Machine data not found.");

        var data = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> slots = List.from(data['slots'] ?? []);
        final String targetEmail = _selectedPatientEmail!.toLowerCase();
        final DateTime now = DateTime.now();
        bool needsSync = false;

        // --- CORE LOGIC: AUTO-CLEAR EXPIRED SLOTS ---
        for (int i = 0; i < slots.length; i++) {
          if (slots[i]['status'] == "Occupied" && slots[i]['endDate'] != "") {
            DateTime endDate = DateTime.parse(slots[i]['endDate']);
            // If today is past the end date, recycling the slot to Empty
            if (now.isAfter(endDate.add(const Duration(days: 1)))) {
              slots[i] = {
                "slot": slots[i]['slot'], "status": "Empty", "patientEmail": "", "medDetails": "",
                "times": [], "startDate": "", "endDate": "", "isLocked": false, "isDone": false,
                "lastTakenDate": "", "adherenceStatus": "Upcoming",
              };
              needsSync = true;
            }
          }
        }

        // Trigger the cleanup in Firestore if any slots were recycled
        if (needsSync) {
          FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).update({'slots': slots});
        }

        // Filter to only show relevant active bins for this caregiver's view
        List<int> validIndices = [];
        for (int i = 0; i < slots.length; i++) {
          if (slots[i]['patientEmail'] == targetEmail && slots[i]['status'] == "Occupied") {
            validIndices.add(i);
          }
        }

        if (validIndices.isEmpty) return _buildEmptyState("No active medications found in physical slots.");

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: validIndices.length,
          itemBuilder: (context, idx) {
            int originalIndex = validIndices[idx];
            var slot = slots[originalIndex];
            bool isBinEmpty = slot['isDone'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 15),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isBinEmpty ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(isBinEmpty ? Icons.shopping_basket_outlined : Icons.check_circle_outline, 
                          color: isBinEmpty ? Colors.red : Colors.green, size: 24),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(slot['medDetails'] ?? "Medication", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A3B70))),
                        Text("Physical Slot: ${slot['slot']}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: isBinEmpty ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(5)),
                          child: Text(isBinEmpty ? "STATUS: EMPTY" : "STATUS: REFILLED", 
                            style: TextStyle(color: isBinEmpty ? Colors.red : Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    ),
                    if (isBinEmpty)
                      ElevatedButton.icon(
                        onPressed: () => _refillSlot(originalIndex, slots),
                        icon: const Icon(Icons.lock_outline, size: 14, color: Colors.white),
                        label: const Text("Refill & Lock", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A3B70), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40.0), 
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 50, color: Colors.blue.withOpacity(0.2)),
          const SizedBox(height: 15),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
        ],
      )
    ));
  }
}