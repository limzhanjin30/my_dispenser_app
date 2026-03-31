import 'dart:convert';
import 'package:flutter/services.dart';

// --- GLOBAL VARIABLES (Now mirroring Firestore Collections) ---
List<Map<String, dynamic>> registeredUsers = [];
List<Map<String, dynamic>> globalMachines = []; 

class UserModel {
  /// Loads mock data for development. 
  /// In the live app, this logic is replaced by real-time Firestore listeners.
  static Future<void> loadMockData() async {
    try {
      final String response = await rootBundle.loadString('assets/mock_data.json');
      final Map<String, dynamic> data = json.decode(response);

      // 1. Populate Registered Users (Now including linkedMachineId)
      if (data['registeredUsers'] != null) {
        registeredUsers = (data['registeredUsers'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }

      // 2. Populate Virtual Machines (The 10-slot shared hardware)
      if (data['machines'] != null) {
        globalMachines = (data['machines'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      
    } catch (e) {
      print("Error loading local model data: $e");
    }
  }
}

// --- PROJECT DOCUMENTATION: SHARED MACHINE SCHEMA ---
/*
  The following structures define how your machine-centric system 
  scales to support unlimited shared dispensers.

  1. Collection: 'users'
  {
    "name": "Richard",
    "email": "richard@gmail.com",
    "role": "Patient",
    "linkedMachineId": "SMART-MED-001" // Found on physical hardware sticker
  }

  2. Collection: 'machines'
  {
    "machineId": "SMART-MED-001",
    "slots": [
      {
        "slot": 1,
        "status": "Occupied", // 'Empty' or 'Occupied'
        "patientEmail": "richard@gmail.com",
        "medDetails": "1x Panadol, 1x Aspirin",
        "times": ["08:00 AM"],
        "startDate": "2026-03-10",
        "endDate": "2026-03-17",
        "frequency": "Everyday",
        "mealCondition": "After Meal",
        "isLocked": true, // Triggers solenoid lock
        "isDone": false  // Reset daily for adherence tracking
      },
      ... indexes 1 through 9 for a total of 10 slots
    ]
  }
*/