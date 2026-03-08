import 'package:flutter/material.dart';
import '../modals/user_modal.dart'; // To access registeredUsers, globalPendingRequests, and globalConnections

class HealthcareLinked extends StatefulWidget {
  final String userEmail; 
  const HealthcareLinked({super.key, required this.userEmail});

  @override
  State<HealthcareLinked> createState() => _HealthcareLinkedState();
}

class _HealthcareLinkedState extends State<HealthcareLinked> {
  
  List<Map<String, String>> get connectedPatients {
    // 1. Find all connection emails where THIS provider is the caregiver/healthcare
    final myPatientEmails = globalConnections
        .where((conn) => 
            conn['caregiverEmail']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase())
        .map((conn) => conn['patientEmail']?.trim().toLowerCase())
        .toList();

    // 2. Map those emails to their full user profiles from registeredUsers
    return registeredUsers
        .where((user) => 
            myPatientEmails.contains(user['email']?.trim().toLowerCase()))
        .map((user) => {
              "name": user['name'] ?? "Unknown Patient",
              "role": user['role'] ?? "Patient",
              "email": user['email'] ?? "",
            })
        .toList();
  }

  void _unlinkPatient(String email, String name) {
    setState(() {
      globalConnections.removeWhere((conn) => 
        conn['caregiverEmail']?.trim().toLowerCase() == widget.userEmail.trim().toLowerCase() && 
        conn['patientEmail']?.trim().toLowerCase() == email.trim().toLowerCase());
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Access revoked for $name"), backgroundColor: Colors.orange),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patients = connectedPatients;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.blue, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Clinical Patient Panel", 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: patients.isEmpty 
      ? _buildEmptyState() 
      : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Managed Patients",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A3B70)),
            ),
            const SizedBox(height: 8),
            const Text(
              "Below are the patients who have authorized you to monitor their dispenser activity.",
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 25),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: patients.length,
              itemBuilder: (context, index) {
                return _buildPatientCard(patients[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, String> patient) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE0F2F1),
                child: Icon(Icons.person, color: Colors.teal),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient['name']!, 
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Text("Active Clinical Connection", 
                      style: TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(),
          const SizedBox(height: 10),
          Text("Email: ${patient['email']}", style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _unlinkPatient(patient['email']!, patient['name']!),
                  icon: const Icon(Icons.person_remove_outlined, size: 18),
                  label: const Text("Revoke My Access"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Text("No clinical patients assigned.", style: TextStyle(color: Colors.grey)),
    );
  }
}