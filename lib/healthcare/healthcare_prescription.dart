import 'package:flutter/material.dart';
import '../custom_bottom_nav.dart';
import 'healthcare_dashboard.dart';
import '../modals/user_modal.dart'; // To access registeredUsers for dynamic name display

class HealthcarePrescription extends StatefulWidget {
  final String userEmail; // Required to identify the provider
  const HealthcarePrescription({super.key, required this.userEmail});

  @override
  State<HealthcarePrescription> createState() => _HealthcarePrescriptionState();
}

class _HealthcarePrescriptionState extends State<HealthcarePrescription> {
  String fullName = "Healthcare Provider";

  @override
  void initState() {
    super.initState();
    _fetchProviderName();
  }

  // Look up the provider's registered name
  void _fetchProviderName() {
    final user = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase(),
      orElse: () => {},
    );
    if (user.isNotEmpty) {
      setState(() {
        fullName = user['name'] ?? "Healthcare Provider";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A3B70)),
          onPressed: () {
            // FIXED: Removed 'const' and passed the required userEmail
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HealthcareDashboard(userEmail: widget.userEmail),
              ),
            );
          },
        ),
        // Dynamic name from global list
        title: Text(
          fullName,
          style: const TextStyle(color: Color(0xFF1A3B70), fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF1A3B70), size: 28),
            onPressed: () {
              // Logic to save changes
            },
          ),
          const SizedBox(width: 10),
        ],
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Prescription Management",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A3B70),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Patient: John Doe",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 25),

            // --- PRESCRIPTION CARDS ---
            _buildPrescriptionCard("Aspirin", "100mg", "1x Daily (Morning)", "Feb 28"),
            const SizedBox(height: 20),
            _buildPrescriptionCard("Metformin", "500mg", "2x Daily (with meals)", "Mar 15"),
            
            const SizedBox(height: 30),

            // --- ADD NEW BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  "Add New Prescription",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E74B5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 1,
        role: "Healthcare\nProvider",
        userEmail: widget.userEmail, // Pass current user email
      ),
    );
  }

  // --- HELPERS ---
  Widget _buildPrescriptionCard(String name, String dosage, String freq, String refill) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(
                height: 30,
                child: TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("Edit", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow("Dosage", dosage),
          _buildInfoRow("Frequency", freq),
          _buildInfoRow("Next Refill", refill),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}