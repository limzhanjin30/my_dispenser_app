import 'package:flutter/material.dart';
import 'healthcare_dashboard.dart';
import '../custom_bottom_nav.dart';
import '../modals/user_modal.dart'; // To access registeredUsers for dynamic name display

class HealthcareAdherence extends StatefulWidget {
  final String userEmail; // Ensure email is passed here
  const HealthcareAdherence({super.key, required this.userEmail});

  @override
  State<HealthcareAdherence> createState() => _HealthcareAdherenceState();
}

class _HealthcareAdherenceState extends State<HealthcareAdherence> {
  String fullName = "Healthcare Provider";

  @override
  void initState() {
    super.initState();
    _fetchProviderName();
  }

  // Fetch registered name for the title
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
            // FIXED: Removed 'const' and added required userEmail
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HealthcareDashboard(userEmail: widget.userEmail),
              ),
            );
          },
        ),
        automaticallyImplyLeading: false, 
        title: Text(
          fullName, // Dynamic name from global list
          style: const TextStyle(color: Color(0xFF1A3B70), fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF1A3B70), size: 28),
            onPressed: () {},
          ),
          const SizedBox(width: 10),
        ],
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Adherence Log",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A3B70),
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // --- PATIENT SELECTOR DROPDOWN ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: "John Doe",
                        isExpanded: true,
                        items: ["John Doe", "Mary Smith", "Jane Williams"]
                            .map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text("Patient: $value"),
                          );
                        }).toList(),
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  _buildDateHeader("Today, Feb 9"),
                  _buildStatusLog(
                    "8:00 AM - Aspirin, 100mg - Missed", 
                    const Color(0xFFD9534F), 
                    showButton: true, 
                    buttonText: "Alert Caregiver"
                  ),
                  _buildStatusLog(
                    "12:00 PM - Vitamin D - Upcoming", 
                    Colors.grey.shade400, 
                    showButton: false
                  ),
                  
                  const SizedBox(height: 25),
                  _buildDateHeader("Yesterday, Feb 8"),
                  _buildStatusLog("Taken", Colors.green.shade600, showButton: false),
                  _buildStatusLog("Taken", Colors.green.shade600, showButton: false),
                  _buildStatusLog("Taken", Colors.green.shade600, showButton: false),
                  
                  const SizedBox(height: 25),
                  _buildDateHeader("Sunday, Feb 7"),
                  _buildStatusLog(
                    "8:00 AM - Taken Late (8:45 AM)", 
                    const Color(0xFFF0AD4E), 
                    showButton: true, 
                    buttonText: "Alert Caregiver"
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 2,
        role: "Healthcare\nProvider",
        userEmail: widget.userEmail, // Pass current user email
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _buildDateHeader(String date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        date,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildStatusLog(String label, Color color, {required bool showButton, String? buttonText}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          if (showButton) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: color,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  buttonText ?? "",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}