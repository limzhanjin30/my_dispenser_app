import 'package:flutter/material.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import '../modals/user_modal.dart'; // To access registeredUsers for dynamic name display

class CaregiverDashboard extends StatefulWidget {
  final String userEmail; // Required parameter to identify the caregiver
  const CaregiverDashboard({super.key, required this.userEmail});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  String fullName = "Caregiver";

  @override
  void initState() {
    super.initState();
    _fetchCaregiverName();
  }

  // Look up the caregiver's name in the global list
  void _fetchCaregiverName() {
    final String cleanEmail = widget.userEmail.trim().toLowerCase();

    final user = registeredUsers.firstWhere(
      (u) => u['email']?.trim().toLowerCase() == cleanEmail,
      orElse: () => {},
    );

    if (user.isNotEmpty && user.containsKey('name')) {
      setState(() {
        fullName = user['name']!;
      });
    }
  }

  // Dynamic count of linked patients for this specific caregiver
  int get linkedPatientCount {
    return globalConnections
        .where(
          (conn) =>
              conn['caregiverEmail']?.trim().toLowerCase() ==
              widget.userEmail.trim().toLowerCase(),
        )
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
              (route) => false,
            );
          },
        ),
        backgroundColor: const Color(0xFF1A3B70), // Consistent theme
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.people_alt, color: Colors.white),
            const SizedBox(width: 10),
            const Text(
              "Smart Med",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Spacer(),
            const Icon(Icons.notifications_none, color: Colors.white),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fullName, // DISPLAY REGISTERED NAME
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Primary Caregiver",
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Caregiver Overview",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A3B70),
              ),
            ),
            const SizedBox(height: 25),

            // --- SUMMARY STATS ---
            _buildStatCard(
              "Linked Patients",
              linkedPatientCount.toString(),
              Icons.person_add,
              Colors.teal,
            ),
            const SizedBox(height: 15),
            _buildStatCard(
              "Missed Doses (Today)",
              "2",
              Icons.warning_amber_rounded,
              Colors.orange,
            ),

            const SizedBox(height: 35),
            const Text(
              "Recent Activity",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // --- MOCK ACTIVITY LIST ---
            _buildActivityTile(
              "John Doe took Morning Dose",
              "10 min ago",
              Icons.check_circle,
              Colors.green,
            ),
            _buildActivityTile(
              "Jane Smith missed Afternoon Dose",
              "1 hour ago",
              Icons.error,
              Colors.red,
            ),

            const SizedBox(height: 40),

            // --- ACTION BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A3B70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Manage Patient Access",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        role: "Caregiver",
        userEmail: widget.userEmail, // Pass session email
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Icon(icon, color: color, size: 35),
        ],
      ),
    );
  }

  Widget _buildActivityTile(
    String msg,
    String time,
    IconData icon,
    Color iconColor,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          msg,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(time, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
