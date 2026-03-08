import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../custom_bottom_nav.dart';
import '../login.dart';
import '../modals/user_modal.dart';

class PatientDashboard extends StatefulWidget {
  // Pass the email from LoginPage to identify the user
  final String userEmail;
  const PatientDashboard({super.key, required this.userEmail});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  String fullName = "Patient";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // Locates the registered name in the global list based on email
  void _fetchUserData() {
    try {
      final user = registeredUsers.firstWhere(
        (u) => u['email'] == widget.userEmail,
        orElse: () => {},
      );
      if (user.isNotEmpty && user.containsKey('name')) {
        setState(() {
          fullName = user['name']!;
        });
      }
    } catch (e) {
      fullName = "User"; // Fallback name
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic Date and Day generation
    String currentDay = DateFormat('EEEE').format(DateTime.now());
    String currentDate = DateFormat('MMMM d, y').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () {
            // Secure logout clearing the navigation stack
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
              (route) => false,
            );
          },
        ),
        title: const Text(
          "Patient Dashboard",
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- UPDATED DYNAMIC HEADER ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Personalized greeting using registered name
                    Text(
                      "Hi, $fullName",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Live Day and Date
                    Text(
                      "$currentDay, $currentDate",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const Column(
                  children: [
                    Icon(Icons.wifi, color: Colors.green),
                    Text(
                      "Connected",
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 30),

            // --- CENTRAL PROGRESS CARD ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    "75%",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "Daily Adherence",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),

                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 180,
                        width: 180,
                        child: CircularProgressIndicator(
                          value: 0.75,
                          strokeWidth: 12,
                          backgroundColor: Colors.grey[200],
                          color: Colors.blue[400],
                        ),
                      ),
                      const Column(
                        children: [
                          Text(
                            "NEXT DOSE IN:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            "02:45:30",
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Aspirin - 1 Pill",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // --- TODAY'S SCHEDULE SECTION ---
            const Text(
              "Today's Schedule",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  ScheduleItem(time: "8:00 AM", status: "Taken", isTaken: true),
                  Divider(),
                  ScheduleItem(
                    time: "12:00 PM",
                    status: "Upcoming",
                    isTaken: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        role: "Patient",
        userEmail: widget.userEmail,
      ),
    );
  }
}

class ScheduleItem extends StatelessWidget {
  final String time;
  final String status;
  final bool isTaken;

  const ScheduleItem({
    super.key,
    required this.time,
    required this.status,
    required this.isTaken,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(time, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            status,
            style: TextStyle(
              color: isTaken ? Colors.green : Colors.blueGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
