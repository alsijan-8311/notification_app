import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'home_page.dart';
import 'notification_service.dart';

/// Entry point of the notification_app.
void main() async {
  // 1. Ensure Flutter engine and widget bindings are ready
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Firebase Core
  try {
    // When google-services.json is present in android/app/,
    // Firebase.initializeApp() automatically reads Android native configuration.
    await Firebase.initializeApp();
    debugPrint('🔥 Firebase Core successfully initialized.');
  } catch (e) {
    debugPrint('⚠️ Firebase.initializeApp() error/note: $e');
    debugPrint('ℹ️ Please ensure google-services.json is placed in android/app/ folder.');
  }

  // 3. Register the top-level background message handler for FCM
  if (Firebase.apps.isNotEmpty) {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('⚠️ Error registering onBackgroundMessage: $e');
    }
  }

  // 4. Initialize NotificationService (Permissions, Token, Channels, Firestore sync)
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('⚠️ Error initializing NotificationService: $e');
  }

  // 5. Start the Flutter application
  runApp(const NotificationApp());
}

/// Root application widget.
class NotificationApp extends StatelessWidget {
  const NotificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1E40AF); // Royal Blue

    return MaterialApp(
      title: 'FCM Notification App',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      home: const HomePage(),
    );
  }
}
