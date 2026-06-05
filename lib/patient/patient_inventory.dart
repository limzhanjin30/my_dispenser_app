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
                  stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError) return _buildEmptyState("Error loading calibration records.");
                    if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("Hardware data unreachable.");

                    var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                    List<dynamic> allSlots = List.from(data['slots'] ?? []);
                    final String myEmail = widget.userEmail.trim().toLowerCase();

                    // Fetch real-time telemetry weights processed through Seeed Studio HX711 load cell channel bounds
                    double currentWeight = 0.0;
                    if (data['totalWeight'] != null) {
                      currentWeight = (data['totalWeight'] as num).toDouble();
                    }
                    String connectionStatus = data['hardwareCommand'] == "CALIBRATE_REFILL" ? "Recalibrating..." : "Online";

                    // Filter: Locate slots assigned to THIS patient
                    List<int> mySlotIndices = [];
                    for (int i = 0; i < allSlots.length; i++) {
                      var slotMap = allSlots[i] as Map<String, dynamic>? ?? {};
                      if (slotMap['status'] == "Occupied") {
                        mySlotIndices.add(i);
                      }
                    }

                    if (mySlotIndices.isEmpty) return _buildEmptyState("You have no active physical bins assigned.");

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- REAL-TIME HX711 LOAD CELL WEIGHT TELEMETRY DISPLAY CARD ---
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A3B70),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))]
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("DISPENSER SCALE MASS", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                      child: Text(connectionStatus, style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      currentWeight.toStringAsFixed(2),
                                      style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text("grams", style: TextStyle(color: Colors.white70, fontSize: 14)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                const Text("Total payload mass currently detected on load cell array", style: TextStyle(color: Colors.white54, fontSize: 10)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 25),
                          const Text("My Active Physical Bins", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70), fontSize: 13)),
                          const SizedBox(height: 12),

                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: mySlotIndices.length,
                            itemBuilder: (context, index) {
                              int slotIdx = mySlotIndices[index];
                              var slot = allSlots[slotIdx];

                              // Extract single dose weight delta set by the caregiver
                              double expectedDelta = 0.0;
                              if (slot['singleDoseWeight'] != null) {
                                  expectedDelta = (slot['singleDoseWeight'] as num).toDouble();
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 15),
                                child: InventoryCard(
                                  medName: slot['medDetails'] ?? "Medication",
                                  slotNumber: slot['slot'].toString(),
                                  singleDoseWeight: expectedDelta, // 👈 Successfully pass it down
                                ),
                              );
                            },
                          ),
                        ],
                      ),
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
  final double singleDoseWeight; // 👈 Add back property field

  const InventoryCard({
    super.key, 
    required this.medName, 
    required this.slotNumber, 
    required this.singleDoseWeight,
  });

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
                  color: const Color(0xFF1A3B70).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline, color: Color(0xFF1A3B70), size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(medName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A3B70))),
                  const SizedBox(height: 2),
                  Text("Dispenser Slot: $slotNumber", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 15),
          
          // 👇 RESTORED: Read-only visibility box for the dose weight configurations
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("EXPECTED DOSE PAYLOAD MASS", style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    singleDoseWeight > 0.0 ? "${singleDoseWeight.toStringAsFixed(2)} grams" : "Not Configured", 
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}