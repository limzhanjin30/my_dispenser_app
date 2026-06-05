import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'caregiver_dashboard.dart';
import '../custom_bottom_nav.dart';

class CaregiverInventory extends StatefulWidget {
  final String userEmail;
  const CaregiverInventory({super.key, required this.userEmail});

  @override
  State<CaregiverInventory> createState() => _CaregiverInventoryState();
}

class _CaregiverInventoryState extends State<CaregiverInventory> {
  String? _selectedPatientEmail;
  String? _linkedMachineId;
  bool _isProcessing = false;
  
  // Track individual numerical inputs dynamically for active device channels
  final Map<int, TextEditingController> _doseWeightControllers = {};

  @override
  void dispose() {
    for (var controller in _doseWeightControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchMachineId(String pEmail) async {
    if (!mounted) return;
    setState(() { 
      _isProcessing = true; 
      _linkedMachineId = null; 
      _doseWeightControllers.clear(); 
    });
    try {
      var userSnap = await FirebaseFirestore.instance.collection('users')
          .where('email', isEqualTo: pEmail.trim().toLowerCase()).limit(1).get();
      if (userSnap.docs.isNotEmpty) {
        setState(() {
          _linkedMachineId = userSnap.docs.first.get('linkedMachineId');
          _isProcessing = false;
        });
      } else { 
        if (mounted) setState(() => _isProcessing = false); 
      }
    } catch (e) { 
      if (mounted) setState(() => _isProcessing = false); 
    }
  }

  // --- HARDWARE CONFIGURATION LAYER: SAVES ONE-TIME DOSAGE DELTA BASES ---
  Future<void> _saveDoseDelta(int index, List<dynamic> currentSlots) async {
    if (_linkedMachineId == null) return;
    
    final controller = _doseWeightControllers[index];
    double customDoseWeight = 0.0;
    if (controller != null && controller.text.trim().isNotEmpty) {
      customDoseWeight = double.tryParse(controller.text.trim()) ?? 0.0;
    }

    if (customDoseWeight <= 0.0) {
      _showMsg("Please set a valid target weight reduction baseline.", Colors.orange);
      return;
    }

    setState(() => _isProcessing = true);
    
    // Append target single configuration dosage weight down to memory map
    currentSlots[index]['singleDoseWeight'] = customDoseWeight;

    try {
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
        'slots': currentSlots,
        'hardwareCommand': "CALIBRATE_REFILL",
        'lastRefilledSlot': index + 1,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _showMsg("Slot ${index + 1} synchronized. Dose baseline configured to ${customDoseWeight}g.", Colors.teal);
    } catch (e) {
      _showMsg("Load Cell tracking configuration failed: $e", Colors.red);
    } finally { if (mounted) setState(() => _isProcessing = false); }
  }

  void _showMsg(String m, Color c) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF1A3B70), size: 20), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CaregiverDashboard(userEmail: widget.userEmail)))
        ),
        title: const Text("Hardware Hub & Load Cell", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
        backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
      ),
      body: Column(
        children: [
          _buildPatientSelector(),
          Expanded(
            child: _isProcessing 
              ? const Center(child: CircularProgressIndicator())
              : _selectedPatientEmail == null 
                ? _buildEmptyState("Select a patient registry terminal to audit dispenser telemetry.")
                : (_linkedMachineId == null ? _buildEmptyState("No active hardware hub linked.") : _buildInventoryView()),
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
            hint: const Text("Select Patient Terminal"),
            decoration: InputDecoration(labelText: "ESP32-C3 Device Oversight", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: snapshot.data!.docs.map((c) => DropdownMenuItem(value: c.get('patientEmail').toString().toLowerCase().trim(), child: Text(c.get('patientEmail')))).toList(),
            onChanged: (val) { if (val != null) { setState(() => _selectedPatientEmail = val); _fetchMachineId(val); } },
          ),
        );
      },
    );
  }

  Widget _buildInventoryView() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildEmptyState("Error loading data.");
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState("Awaiting machine initialization parameters...");
        
        var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        List<dynamic> slots = List.from(data['slots'] ?? []);
        
        double currentWeight = 0.0;
        if (data['totalWeight'] != null) {
          currentWeight = (data['totalWeight'] as num).toDouble();
        }
        
        String connectionStatus = data['hardwareCommand'] == "CALIBRATE_REFILL" ? "Recalibrating..." : "Online";

        // Filter: Locate active slots bound inside the system array grid allocations
        List<int> validIndices = [];
        for (int i = 0; i < slots.length; i++) {
          var slotMap = slots[i] as Map<String, dynamic>? ?? {};
          if (slotMap['status'] == "Occupied") {
            validIndices.add(i);
          }
        }

        return SingleChildScrollView(
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
                        const Text("HX711 LOAD CELL READINGS", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
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
                    const Text("Total current payload weight detected inside dispenser array terminal", style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              const Text("Active Physical Slots Configuration", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3B70), fontSize: 13)),
              const SizedBox(height: 12),
              
              if (validIndices.isEmpty) 
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Center(child: Text("No active medication assigned inside slot grid allocations.", style: TextStyle(color: Colors.grey.shade400, fontSize: 12))),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: validIndices.length,
                  itemBuilder: (context, idx) {
                    int originalIdx = validIndices[idx];
                    var slot = slots[originalIdx];

                    // Initialize inputs controller cleanly
                    _doseWeightControllers.putIfAbsent(
                      originalIdx, 
                      () => TextEditingController(
                        text: slot['singleDoseWeight'] != null ? slot['singleDoseWeight'].toString() : ""
                      )
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      elevation: 0, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: const Color(0xFF1A3B70).withOpacity(0.1), shape: BoxShape.circle),
                                  child: const Icon(Icons.medication_outlined, color: Color(0xFF1A3B70), size: 22),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, 
                                    children: [
                                      Text(slot['medDetails'] ?? "Medication", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text("Hardware Bin Assignment: Slot ${slot['slot']}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ]
                                  )
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 15),
                            const Divider(height: 1, thickness: 0.5),
                            const SizedBox(height: 15),
                            
                            // --- SINGLE INTENDED DOSE TARGET WEIGHT REDUCTION FORM ---
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("ONE TIME MEDICATION MASS DELTA", style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        height: 40,
                                        child: TextField(
                                          controller: _doseWeightControllers[originalIdx],
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          decoration: InputDecoration(
                                            hintText: "E.g. 2.5",
                                            suffixText: "grams",
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            filled: true,
                                            fillColor: Colors.grey.shade50
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Padding(
                                  padding: const EdgeInsets.only(top: 15),
                                  child: ElevatedButton(
                                    onPressed: () => _saveDoseDelta(originalIdx, slots),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1A3B70),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                                    ),
                                    child: const Text(
                                      "Save Delta", 
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)
                                    ),
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String m) => Center(child: Padding(padding: const EdgeInsets.all(30.0), child: Text(m, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12))));
}