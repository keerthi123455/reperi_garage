import 'package:flutter/material.dart';
import 'package:hello_world_app/screens/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// Set to true the moment a password-recovery deep link is detected.
// SplashScreen's delayed Home/Login redirect checks this flag so it
// never overrides the reset-password navigation, even on a cold
// app start where this listener catches the event before SplashScreen
// itself has mounted.
bool isPasswordRecoveryInProgress = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rmvxqjyoqfinbrpubsvp.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtdnhxanlvcWZpbmJycHVic3ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQyNDcsImV4cCI6MjA5MjgxMDI0N30.NAxb2XnicLSaBoA4kpTFmmutT68Z2ksu-T-P_NUxy5E',
  );

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    print("MAIN AUTH EVENT: ${data.event}");

    if (data.event == AuthChangeEvent.passwordRecovery) {
      isPasswordRecoveryInProgress = true;

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ResetPasswordScreen(),
        ),
        (route) => false,
      );
    }
  });

  runApp(const GarageApp());
}

class GarageApp extends StatelessWidget {
  const GarageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}