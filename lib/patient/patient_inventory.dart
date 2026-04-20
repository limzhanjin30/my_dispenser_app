import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../custom_bottom_nav.dart';
import 'patient_dashboard.dart';

class PatientInventory extends StatefulWidget {
  final String userEmail;
  const PatientInventory({super.key, required this.userEmail});

  @override
  State<PatientInventory> createState() => _PatientInventoryState();
}

class _PatientInventoryState extends State<PatientInventory> {
  String? _linkedMachineId;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _fetchMachineId();
  }

  // --- DATABASE: FIND THE HARDWARE LINKED TO THIS ACCOUNT ---
  Future<void> _fetchMachineId() async {
    try {
      var userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail.trim().toLowerCase())
          .limit(1)
          .get();

      if (userSnap.docs.isNotEmpty && mounted) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isInitializing = false;
        });
      } else {
        if (mounted) setState(() => _isInitializing = false);
      }
    } catch (e) {
      debugPrint("Inventory Fetch Error: $e");
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  // --- HARDWARE LOGIC: RE-LOCK BIN AFTER MANUAL REFILL ---
  Future<void> _handleRefill(int index, List<dynamic> allSlots) async {
    if (_linkedMachineId == null) return;

    try {
      // Logic: Mark bin as NOT DONE (meaning it is now full) and engage solenoid lock
      allSlots[index]['isDone'] = false;   // The "Done/Empty" state is reset
      allSlots[index]['isLocked'] = true;  // The physical hardware is locked
      
      // Update the specific slot in the machines collection
      await FirebaseFirestore.instance
          .collection('machines')
          .doc(_linkedMachineId)
          .update({'slots': allSlots});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${allSlots[index]['medDetails']} bin refilled and secured."),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      debugPrint("Refill update error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PatientDashboard(userEmail: widget.userEmail))),
        ),
        title: const Text("My Medication Bins", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3B70)))
          : _linkedMachineId == null
              ? _buildEmptyState("Please link your dispenser hub in Settings.")
              : StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("Hardware data unreachable.");

                    var data = snapshot.data!.data() as Map<String, dynamic>;
                    List<dynamic> allSlots = List.from(data['slots'] ?? []);
                    final String myEmail = widget.userEmail.trim().toLowerCase();

                    // Filter: Locate slots assigned to THIS patient
                    List<int> mySlotIndices = [];
                    for (int i = 0; i < allSlots.length; i++) {
                      if (allSlots[i]['patientEmail'].toString().toLowerCase().trim() == myEmail && allSlots[i]['status'] == "Occupied") {
                        mySlotIndices.add(i);
                      }
                    }

                    if (mySlotIndices.isEmpty) return _buildEmptyState("You have no active physical bins assigned.");

                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: mySlotIndices.length,
                      itemBuilder: (context, index) {
                        int slotIdx = mySlotIndices[index];
                        var slot = allSlots[slotIdx];
                        
                        // KEY LOGIC: isDone == true means the pill was taken (Bin is Empty)
                        bool needsRefill = (slot['isDone'] == true);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: InventoryCard(
                            medName: slot['medDetails'] ?? "Medication",
                            slotNumber: slot['slot'].toString(),
                            isBinEmpty: needsRefill, // Passing the "needs refill" state
                            onRefill: () => _handleRefill(slotIdx, allSlots),
                          ),
                        );
                      },
                    );
                  },
                ),
      bottomNavigationBar: CustomBottomNavBar(currentIndex: 2, role: "Patient", userEmail: widget.userEmail),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40), 
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 50, color: Colors.blue.withOpacity(0.2)),
            const SizedBox(height: 15),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
          ],
        )
      )
    );
  }
}

class InventoryCard extends StatelessWidget {
  final String medName;
  final String slotNumber;
  final bool isBinEmpty;
  final VoidCallback onRefill;

  const InventoryCard({super.key, required this.medName, required this.slotNumber, required this.isBinEmpty, required this.onRefill});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isBinEmpty ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(isBinEmpty ? Icons.shopping_basket_outlined : Icons.lock_clock_outlined, 
                    color: isBinEmpty ? Colors.orange : Colors.green, size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(medName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A3B70))),
                  Text("Dispenser Slot: $slotNumber", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("HARDWARE STATUS", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(isBinEmpty ? "AWAITING REFILL" : "LOCKED & SECURED", 
                      style: TextStyle(fontWeight: FontWeight.bold, color: isBinEmpty ? Colors.orange : Colors.green, fontSize: 12)),
                ],
              ),
              // ONLY show the refill button if the bin is empty (isDone == true)
              if (isBinEmpty)
                ElevatedButton.icon(
                  onPressed: onRefill,
                  icon: const Icon(Icons.refresh, size: 14, color: Colors.white),
                  label: const Text("Mark as Refilled", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A3B70), 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10)
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}