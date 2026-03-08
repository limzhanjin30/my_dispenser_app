import 'dart:convert';
import 'package:flutter/services.dart';

// --- GLOBAL VARIABLES MOVED HERE ---
Map<String, List<Map<String, dynamic>>> globalPatientSchedules = {};
List<Map<String, String>> globalPendingRequests = [];
List<Map<String, String>> globalConnections = [];
List<Map<String, String>> registeredUsers = [];

class UserModel {
  // This function loads the JSON from assets and populates the globals
  static Future<void> loadMockData() async {
    try {
      // 1. Read the JSON file
      final String response = await rootBundle.loadString(
        'assets/mock_data.json',
      );
      final Map<String, dynamic> data = json.decode(response);

      // 2. Populate Registered Users
      if (data['registeredUsers'] != null) {
        registeredUsers = (data['registeredUsers'] as List)
            .map((item) => Map<String, String>.from(item as Map))
            .toList();
      }

      // 3. Populate Patient Schedules
      if (data['globalPatientSchedules'] != null) {
        Map<String, dynamic> schedules = data['globalPatientSchedules'];
        globalPatientSchedules = schedules.map((key, value) {
          return MapEntry(
            key,
            (value as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(),
          );
        });
      }

      // 4. Populate Requests and Connections
      if (data['globalPendingRequests'] != null) {
        globalPendingRequests = (data['globalPendingRequests'] as List)
            .map((item) => Map<String, String>.from(item as Map))
            .toList();
      }

      if (data['globalConnections'] != null) {
        globalConnections = (data['globalConnections'] as List)
            .map((item) => Map<String, String>.from(item as Map))
            .toList();
      }
    } catch (e) {
      print("Error loading mock data: $e");
    }
  }
}
