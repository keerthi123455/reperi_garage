import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reperi_garage/screens/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/push_notification_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// Set to true the moment a password-recovery deep link is detected.
// SplashScreen's delayed Home/Login redirect checks this flag so it
// never overrides the reset-password navigation, even on a cold
// app start where this listener catches the event before SplashScreen
// itself has mounted.
bool isPasswordRecoveryInProgress = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every screen in this app is a fixed, hand-tuned portrait layout —
  // none of it was built to reflow for landscape — so lock rotation
  // instead of letting an accidental turn drop users into broken layouts
  // no screen was designed to handle.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: 'https://rmvxqjyoqfinbrpubsvp.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtdnhxanlvcWZpbmJycHVic3ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQyNDcsImV4cCI6MjA5MjgxMDI0N30.NAxb2XnicLSaBoA4kpTFmmutT68Z2ksu-T-P_NUxy5E',
  );

  await PushNotificationService.init();

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      isPasswordRecoveryInProgress = true;

      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const ResetPasswordScreen(),
        ),
        (route) => false,
      );
    }

    // Bind/unbind this device's OneSignal identity to whichever
    // customer is currently signed in via Supabase Auth. Covers a
    // fresh sign-in and an already-active session restored on cold
    // start, so the customer doesn't have to log out/in again just
    // to start receiving notifications.
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.initialSession) {
      final userId = data.session?.user.id;
      if (userId != null) {
        PushNotificationService.loginAsCustomer(userId);
      }
    } else if (data.event == AuthChangeEvent.signedOut) {
      PushNotificationService.logout();
    }
  });

  runApp(const GarageApp());
}

class GarageApp extends StatelessWidget {
  const GarageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          iconTheme: IconThemeData(color: Color(0xFFD4A017)),
          actionsIconTheme: IconThemeData(color: Color(0xFFD4A017)),
        ),
      ),
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      // Screens across the app use fixed-height tiles/cards sized for a
      // roughly 1.0 system text scale (see e.g. ServiceTile). Some
      // devices ship a larger default font size or a bumped-up
      // Settings > Display > Font size, which was overflowing those
      // fixed layouts — most visibly the "Our Services" grid — on
      // phones like the OnePlus 11 5G where the actual on-screen scale
      // ended up further from 1.0 than on phones this was tuned against.
      // Clamping keeps real accessibility scaling (larger text still
      // works, just capped) without letting it break layouts that were
      // never designed for arbitrary scale.
      builder: (context, child) {
        final clampedScaler =
            MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}