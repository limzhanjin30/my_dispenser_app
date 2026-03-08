import 'package:flutter/material.dart';
import 'caregiver_dashboard.dart';
import '../custom_bottom_nav.dart';
import '../modals/user_modal.dart'; // To access registeredUsers for dynamic name display

class CaregiverAdherence extends StatefulWidget {
  final String userEmail; // Required parameter to maintain session
  const CaregiverAdherence({super.key, required this.userEmail});

  @override
  State<CaregiverAdherence> createState() => _CaregiverAdherenceState();
}

class _CaregiverAdherenceState extends State<CaregiverAdherence> {
  String caregiverName = "Caregiver";

  @override
  void initState() {
    super.initState();
    _fetchCaregiverName();
  }

  // Look up the caregiver's name for the header
  void _fetchCaregiverName() {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();
    final user = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == cleanEmail,
      orElse: () => {},
    );

    if (user.isNotEmpty) {
      setState(() {
        caregiverName = user['name'] ?? "Caregiver";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () {
            // FIXED: Removed 'const' and passed required userEmail
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => CaregiverDashboard(userEmail: widget.userEmail))
            );
          },
        ),
        title: Text("Adherence History - $caregiverName", 
          style: const TextStyle(color: Colors.black, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        automaticallyImplyLeading: false, 
      ),
      body: Column(
        children: [
          // --- WEEK SELECTOR ---
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () {}),
                const Text("This Week, Feb 9 - Feb 15", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () {}),
              ],
            ),
          ),
          
          // --- LOG LIST ---
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildDateHeader("Today, Feb 9"),
                _buildLogEntry("8:00 AM - Aspirin, 100mg - Missed", Colors.red, isAlert: true),
                _buildLogEntry("12:00 PM - Vitamin D - Upcoming", Colors.grey, isAlert: false),
                
                const SizedBox(height: 20),
                _buildDateHeader("Yesterday, Feb 8"),
                _buildLogEntry("8:00 AM - Taken", Colors.green, hasCheck: true),
                _buildLogEntry("12:00 PM - Taken", Colors.green, hasCheck: true),
                _buildLogEntry("6:00 PM - Taken", Colors.green, hasCheck: true),
                
                const SizedBox(height: 20),
                _buildDateHeader("Sunday, Feb 7"),
                _buildLogEntry("8:00 AM - Taken Late (8:45 AM)", Colors.orange, hasCheck: false),
              ],
            ),
          ),
        ],
      ),
      
      // --- BOTTOM NAVIGATION BAR ---
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 2,
        role: "Caregiver",
        userEmail: widget.userEmail, // Pass session email
      ),
    );
  }

  Widget _buildDateHeader(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(date, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildLogEntry(String text, Color color, {bool isAlert = false, bool hasCheck = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (hasCheck) const Icon(Icons.check_circle, color: Colors.white, size: 18),
              if (hasCheck) const SizedBox(width: 10),
              Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            ],
          ),
          if (isAlert) 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(5)),
              child: const Text("Notify Caregiver", style: TextStyle(color: Colors.white, fontSize: 10)),
            ),
        ],
      ),
    );
  }
}