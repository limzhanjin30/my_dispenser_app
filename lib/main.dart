import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'modals/user_modal.dart'; 
import 'login.dart';

void main() async {
  // Ensure Flutter bindings are initialized before calling native code (Firebase and Asset Loading)
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using the generated configuration
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Load the mock data from the JSON asset into the global variables
  await UserModel.loadMockData();

  runApp(const SmartDispenserApp());
}

class SmartDispenserApp extends StatelessWidget {
  const SmartDispenserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}