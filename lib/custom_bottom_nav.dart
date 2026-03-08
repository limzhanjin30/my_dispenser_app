import 'package:flutter/material.dart';
import 'patient/patient_dashboard.dart';
import 'patient/patient_schedule.dart';
import 'patient/patient_inventory.dart';
import 'patient/patient_setting.dart';
import 'caregiver/caregiver_dashboard.dart';
import 'caregiver/caregiver_adherence.dart'; 
import 'caregiver/caregiver_inventory.dart'; 
import 'caregiver/caregiver_schedule_editor.dart'; 
import 'caregiver/caregiver_setting.dart';
import 'healthcare/healthcare_dashboard.dart';
import 'healthcare/healthcare_prescription.dart';
import 'healthcare/healthcare_adherence.dart';
import 'healthcare/healthcare_setting.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final String role; 
  final String userEmail;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.role,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      selectedItemColor: const Color(0xFF1A3B70),
      unselectedItemColor: Colors.grey,
      onTap: (index) => _onTap(context, index),
      items: _getNavItems(),
    );
  }

  List<BottomNavigationBarItem> _getNavItems() {
    if (role == "Healthcare\nProvider") {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
        BottomNavigationBarItem(icon: Icon(Icons.people), label: "Patients"),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: "Adherence"),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
      ];
    } else if (role == "Caregiver") {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: "Schedule"),
        BottomNavigationBarItem(icon: Icon(Icons.analytics), label: "Adherence"),
        BottomNavigationBarItem(icon: Icon(Icons.medication), label: "Inventory"),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
      ];
    } else {
      return const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: "Schedule"),
        BottomNavigationBarItem(icon: Icon(Icons.medication), label: "Inventory"),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
      ];
    }
  }

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    Widget nextScreen;

    if (role == "Healthcare\nProvider") {
      switch (index) {
        // FIXED: Passing userEmail to all Healthcare screens
        case 0: nextScreen = HealthcareDashboard(userEmail: userEmail); break;
        case 1: nextScreen = HealthcarePrescription(userEmail: userEmail); break;
        case 2: nextScreen = HealthcareAdherence(userEmail: userEmail); break;
        default: nextScreen = HealthcareSetting(userEmail: userEmail);
      }
    } else if (role == "Caregiver") {
      switch (index) {
        // FIXED: Passing userEmail to all Caregiver screens
        case 0: nextScreen = CaregiverDashboard(userEmail: userEmail); break;
        case 1: nextScreen = CaregiverScheduleEditor(userEmail: userEmail); break;
        case 2: nextScreen = CaregiverAdherence(userEmail: userEmail); break;
        case 3: nextScreen = CaregiverInventory(userEmail: userEmail); break;
        case 4: nextScreen = CaregiverSetting(userEmail: userEmail); break;
        default: nextScreen = CaregiverDashboard(userEmail: userEmail);
      }
    } else {
      switch (index) {
        case 0: nextScreen = PatientDashboard(userEmail: userEmail); break;
        case 1: nextScreen = PatientSchedule(userEmail: userEmail); break;
        case 2: nextScreen = PatientInventory(userEmail: userEmail); break;
        case 3: nextScreen = PatientSetting(userEmail: userEmail); break;
        default: nextScreen = PatientDashboard(userEmail: userEmail);
      }
    }

    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => nextScreen));
  }
}