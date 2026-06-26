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

  // --- CALIBRATION STATE VECTORS ---
  final Map<int, int> _calibrationSteps = {}; // 0: Idle, 1: Sampling Baseline, 2: Locked/Adding Pills
  final Map<int, double> _weightsBefore = {}; 
  final Map<int, TextEditingController> _daysControllers = {}; 

  @override
  void dispose() {
    for (var controller in _daysControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchMachineId(String pEmail) async {
    if (!mounted) return;
    setState(() { 
      _isProcessing = true; 
      _linkedMachineId = null; 
      _calibrationSteps.clear();
      _weightsBefore.clear();
      _daysControllers.clear();
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

  // --- STEP 1: TRIGGER HIGH-FREQUENCY SAMPLING FOR A SPECIFIC SLOT ---
  Future<void> _startSamplingBaseline(int index) async {
    if (_linkedMachineId == null) return;
    setState(() => _isProcessing = true);

    try {
      // 🎯 MODIFIED: Command string now includes the explicit target slot identifier channel
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
        'hardwareCommand': "TARE_SAMPLING",
        'lastRefilledSlot': index + 1,
      });

      setState(() {
        _calibrationSteps[index] = 1;
      });
      _showMsg("ESP32 is reading live baseline for Slot ${index + 1}...", Colors.blueGrey);
    } catch (e) {
      _showMsg("Failed to signal hardware: $e", Colors.red);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // --- STEP 2: LOCK STABLE BASELINE & FREEZE SLOT TELEMETRY ---
  Future<void> _lockBaselineWeight(int index, double currentWeight) async {
    if (_linkedMachineId == null) return;
    setState(() => _isProcessing = true);

    try {
      // 🎯 MODIFIED: Frozen command pattern scoped explicitly down to individual target index
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
        'hardwareCommand': "HOLD_SAMPLING",
      });

      setState(() {
        _weightsBefore[index] = currentWeight;
        _calibrationSteps[index] = 2;
      });
      _showMsg("Baseline locked at ${currentWeight.toStringAsFixed(2)}g. Add pills to Slot ${index + 1} now.", Colors.blue);
    } catch (e) {
      _showMsg("Failed to freeze telemetry: $e", Colors.red);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // --- STEP 3: SUBMIT CALIBRATION, COMMAND REFILL & COOLDOWN WAIT ---
  Future<void> _completeCalibration(int index, List<dynamic> currentSlots, double currentWeight) async {
    if (_linkedMachineId == null) return;

    var slot = currentSlots[index];
    final controller = _daysControllers[index];
    int days = int.tryParse(controller?.text.trim() ?? "") ?? 0;

    if (days <= 0) {
      _showMsg("Please input a valid positive quantity for days.", Colors.orange);
      return;
    }

    // DYNAMIC VALIDATION: Calculate Maximum Days from Today Until End Date
    int maxRemainingDays = 999; 
    if (slot['endDate'] != null && slot['endDate'] != "") {
      try {
        DateTime now = DateTime.now();
        DateTime todayMidnight = DateTime(now.year, now.month, now.day);
        DateTime end = DateTime.parse(slot['endDate']);
        DateTime endDateMidnight = DateTime(end.year, end.month, end.day);

        if (todayMidnight.isAfter(endDateMidnight)) {
          _showMsg("Error: Prescription course timeline has already ended.", Colors.red);
          return;
        }

        maxRemainingDays = endDateMidnight.difference(todayMidnight).inDays + 1;
      } catch (e) {
        debugPrint("Timeline parsing safety exception: $e");
      }
    }

    if (days > maxRemainingDays) {
      _showMsg("Error: Days entered ($days) cannot exceed remaining course timeframe ($maxRemainingDays days left).", Colors.red);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. 🔓 UNFREEZE SPECIFIC CHANNEL: Signal ESP32 to push final load metrics for this bin
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
        'hardwareCommand': "CALIBRATE_REFILL", 
        'lastRefilledSlot': index + 1,
      });

      // 2. ⏳ HOLD WINDOW: Cooldown buffer for scale string packets to transit networks
      await Future.delayed(const Duration(milliseconds: 5000));

      // 3. 🎯 FORCE SERVER FETCH: Bypass client caching layers entirely
      var freshSnapshot = await FirebaseFirestore.instance
          .collection('machines')
          .doc(_linkedMachineId!)
          .get(const GetOptions(source: Source.server));

      var freshData = freshSnapshot.data() as Map<String, dynamic>? ?? {};
      double wAfter = (freshData['totalWeight'] ?? currentWeight).toDouble();
      double wBefore = _weightsBefore[index] ?? 0.0;

      double totalAddedWeight = wAfter - wBefore;

      debugPrint("DEBUG CALIBRATION SLOT ${index + 1}: W_Before: $wBefore | W_After: $wAfter | Delta: $totalAddedWeight");

      // 4. Validate delta parameters
      if (totalAddedWeight <= 0.05) {
        _showMsg("Calibration Error: No mass delta detected on Slot ${index + 1}.", Colors.red);
        
        await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
          'hardwareCommand': "Online",
        });
        
        setState(() {
          _calibrationSteps[index] = 0;
        });
        return;
      }

      // 5. Compute the final single dose baseline weight metric
      double calculatedDoseWeight = totalAddedWeight / days;
      slot['singleDoseWeight'] = double.parse(calculatedDoseWeight.toStringAsFixed(2));

      // Save the physical count entry parameter securely into the database matrix
      slot['remainingDays'] = days; // 👈 Set it directly to the number from the TextField controller (e.g., 3)

      // 6. Push finalized calibrated setup back to the database
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
        'slots': currentSlots,
        'hardwareCommand': "Online", 
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() {
        _calibrationSteps[index] = 0;
        _daysControllers[index]?.clear();
      });

      _showMsg("Slot ${index + 1} calibrated independently! Dose weight: ${calculatedDoseWeight.toStringAsFixed(2)}g.", Colors.teal);
    } catch (e) {
      _showMsg("Sync failed: $e", Colors.red);
    } finally { 
      if (mounted) setState(() => _isProcessing = false); 
    }
  }

  Future<void> _cancelCalibration(int index) async {
    if (_linkedMachineId == null) return;
    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance.collection('machines').doc(_linkedMachineId!).update({
        'hardwareCommand': "Online",
      });
      setState(() {
        _calibrationSteps[index] = 0;
      });
    } catch (e) {
      _showMsg("Error resetting hardware state: $e", Colors.red);
    } finally {
      setState(() => _isProcessing = false);
    }
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
        
        String currentCommand = data['hardwareCommand'] ?? "Online";
        
        // Dynamic string parsing checks if the global machine state belongs to an isolated tare loop
        bool isAnySlotSampling = currentCommand.startsWith("TARE_SAMPLING_SLOT_");
        bool isAnySlotHolding = currentCommand.startsWith("HOLD_SAMPLING_SLOT_");
        
        String connectionStatus = isAnySlotSampling ? "Sampling Channel..." : (isAnySlotHolding ? "Channel Frozen" : "Online");

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
                          decoration: BoxDecoration(
                            color: isAnySlotHolding ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2), 
                            borderRadius: BorderRadius.circular(6)
                          ),
                          child: Text(
                            connectionStatus, 
                            style: TextStyle(
                              color: isAnySlotHolding ? Colors.orangeAccent : Colors.greenAccent, 
                              fontSize: 9, 
                              fontWeight: FontWeight.bold
                            )
                          ),
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
                    Text(
                      isAnySlotHolding 
                        ? "⚠️ Isolated scale freeze active for target bin modification." 
                        : "Total payload weight detected inside dispenser array terminal", 
                      style: TextStyle(color: isAnySlotHolding ? Colors.orangeAccent.withOpacity(0.8) : Colors.white54, fontSize: 10)
                    ),
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
                    
                    int currentStep = _calibrationSteps[originalIdx] ?? 0;
                    double weightBefore = _weightsBefore[originalIdx] ?? 0.0;

                    _daysControllers.putIfAbsent(originalIdx, () => TextEditingController());

                    int displayRemainingDays = 0;
                    if (slot['endDate'] != null && slot['endDate'] != "") {
                      try {
                        DateTime now = DateTime.now();
                        DateTime todayMidnight = DateTime(now.year, now.month, now.day);
                        DateTime end = DateTime.parse(slot['endDate']);
                        DateTime endMidnight = DateTime(end.year, end.month, end.day);
                        
                        if (!todayMidnight.isAfter(endMidnight)) {
                          displayRemainingDays = endMidnight.difference(todayMidnight).inDays + 1;
                        }
                      } catch(_) {}
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),
                      elevation: 0, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                      if (slot['singleDoseWeight'] != null && slot['singleDoseWeight'] > 0)
                                        Text("Current: ${slot['singleDoseWeight']}g / dose", style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 11)),
                                    ]
                                  )
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 15),
                            const Divider(height: 1, thickness: 0.5),
                            const SizedBox(height: 15),
                            
                            // --- EXPLICITLY SEPARATED ISOLATED CALIBRATION INTERACTIVE STEPS ---
                            if (currentStep == 0) ...[
                              Text("SLOT ${slot['slot']} INITIAL TARE PROCESS", style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text("Clear this slot container specifically to register the channel empty sensor tare baseline.", style: TextStyle(color: Colors.black54, fontSize: 11)),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _startSamplingBaseline(originalIdx),
                                  icon: const Icon(Icons.sensors, size: 16),
                                  label: Text("Start Calibrating Slot ${slot['slot']}"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1A3B70),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              )
                            ] else if (currentStep == 1) ...[
                              Text("SLOT ${slot['slot']} LOCK BASELINE DATA PROFILE", style: const TextStyle(color: Colors.teal, fontSize: 9, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text("Live Streaming Scale Mass: ${currentWeight.toStringAsFixed(2)}g", style: const TextStyle(color: Colors.teal, fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _lockBaselineWeight(originalIdx, currentWeight),
                                  icon: const Icon(Icons.lock_clock, size: 16),
                                  label: const Text("Lock Empty Weight (Tare)"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              )
                            ] else ...[
                              Text("SLOT ${slot['slot']} REFILL COMPARTMENT & COMPILE MATH DELTA", style: const TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text("Tare Baseline: ${weightBefore.toStringAsFixed(2)}g (Telemetry Updates Paused)", style: const TextStyle(color: Colors.black54, fontSize: 11)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _daysControllers[originalIdx],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                      decoration: InputDecoration(
                                        labelText: "Days of Pills Loaded",
                                        hintText: "Max: $displayRemainingDays days", 
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton(
                                      onPressed: () => _completeCalibration(originalIdx, slots, currentWeight),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                      child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () => _cancelCalibration(originalIdx),
                                child: const Text("Cancel Calibration Flow", style: TextStyle(color: Colors.red, fontSize: 11)),
                              )
                            ]
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