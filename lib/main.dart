import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'modals/user_modal.dart'; 
import 'login.dart';

// 1. Declare the High Importance Channel parameters globally for heads-up top banners
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'caregiver_alerts_channel', 
  'Urgent Caregiver Alerts', 
  description: 'This channel displays heads-up banners for missed patient doses.',
  importance: Importance.max, // 🎯 CRITICAL: Forces the notification to drop down from the top of the screen
  playSound: true,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// 2. This background handler executes system-level alerts when the app is completely CLOSED or KILLED
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("LOG: Received a push notification while app was closed: ${message.messageId}");
}

void main() async {
  // Ensure Flutter bindings are initialized before calling native code (Firebase and Asset Loading)
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using the generated configuration
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background messaging handler loop early
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 3. Setup the local notification plugin to link with the high-importance native system channel
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // 4. Request hardware system messaging display permissions from the mobile phone OS
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
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