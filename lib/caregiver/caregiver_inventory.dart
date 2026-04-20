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

  Future<void> _fetchMachineId(String pEmail) async {
    if (!mounted) return;
    setState(() { _isLoading = true; _linkedMachineId = null; });
    try {
      var userSnap = await FirebaseFirestore.instance.collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase()).limit(1).get();
      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isLoading = false;
        });
      } else { if (mounted) setState(() => _isLoading = false); }
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _refillSlot(int index, List<dynamic> currentSlots) async {
    if (_linkedMachineId == null) return;
    setState(() => _isLoading = true);
    
    // RESET HARDWARE STATE
    currentSlots[index]['isDone'] = false;   // Bin is now full
    currentSlots[index]['isLocked'] = true;  // Solenoid engages
    currentSlots[index]['lastTakenDate'] = ""; 
    currentSlots[index]['lastTakenTime'] = "";
    currentSlots[index]['adherenceStatus'] = "Upcoming";

    try {
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).update({'slots': currentSlots});
      _showMsg("Bin ${currentSlots[index]['slot']} refilled and locked.", Colors.teal);
    } catch (e) {
      _showMsg("Refill update failed: $e", Colors.red);
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showMsg(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CaregiverDashboard(userEmail: widget.userEmail)))),
        title: const Text("Hardware Inventory", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPatientSelector(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _selectedPatientEmail == null 
                ? _buildEmptyState("Select a patient to manage bins.")
                : (_linkedMachineId == null ? _buildEmptyState("No hub linked.") : _buildInventoryGrid()),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 3, role: "Caregiver", userEmail: widget.userEmail),
    );
  }

  Widget _buildPatientSelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('connections').where('caregiverEmail', isEqualTo: widget.userEmail.trim().toLowerCase()).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Container(
          padding: const EdgeInsets.all(20), color: Colors.white,
          child: DropdownButtonFormField<String>(
            value: _selectedPatientEmail,
            hint: const Text("Select Patient"),
            decoration: InputDecoration(labelText: "Physical Bin Status", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: snapshot.data!.docs.map((c) => DropdownMenuItem(value: c.get('patientEmail').toString().toLowerCase().trim(), child: Text(c.get('patientEmail')))).toList(),
            onChanged: (val) { if (val != null) { setState(() => _selectedPatientEmail = val); _fetchMachineId(val); } },
          ),
        );
      },
    );
  }

  Widget _buildInventoryGrid() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator());
        var data = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> slots = List.from(data['slots'] ?? []);
        final String target = _selectedPatientEmail!.toLowerCase().trim();

        List<int> validIndices = [];
        for (int i = 0; i < slots.length; i++) {
          if (slots[i]['patientEmail'].toString().toLowerCase().trim() == target && slots[i]['status'] == "Occupied") {
            validIndices.add(i);
          }
        }

        if (validIndices.isEmpty) return _buildEmptyState("No active medications found.");

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: validIndices.length,
          itemBuilder: (context, idx) {
            int originalIdx = validIndices[idx];
            var slot = slots[originalIdx];
            
            // CRITICAL: Check isDone. true = bin is empty (needs refill)
            bool isBinEmpty = slot['isDone'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 15),
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: isBinEmpty ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(isBinEmpty ? Icons.inventory_2_outlined : Icons.lock_person_outlined, color: isBinEmpty ? Colors.orange : Colors.green, size: 24),
                    ),
                    const SizedBox(width: 15),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(slot['medDetails'] ?? "Medication", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text("Bin Slot: ${slot['slot']}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 8),
                      Text(isBinEmpty ? "AWAITING REFILL" : "LOCKED & SECURED", style: TextStyle(color: isBinEmpty ? Colors.orange : Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                    ])),
                    if (isBinEmpty)
                      ElevatedButton(
                        onPressed: () => _refillSlot(originalIdx, slots),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3B70)),
                        child: const Text("Refill & Lock", style: TextStyle(color: Colors.white, fontSize: 10)),
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

  Widget _buildEmptyState(String m) => Center(child: Text(m, style: const TextStyle(color: Colors.grey)));
}