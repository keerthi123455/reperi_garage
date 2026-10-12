import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reperi_garage/screens/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/catalog_service.dart';
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

  // Package names and prices come from the Supabase `services` table —
  // start loading them now (from the on-device cache first, then the
  // network) so package screens open instantly.
  CatalogService.ensureLoaded().catchError((_) {});

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
        final media = MediaQuery.of(context);
        final clampedScaler =
            media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15);
        final app = MediaQuery(
          data: media.copyWith(textScaler: clampedScaler),
          child: child!,
        );
        return kIsWeb ? _WebFrame(child: app) : app;
      },
      home: const SplashScreen(),
    );
  }
}

/// On a desktop/laptop browser the app is shown as a phone-width column in
/// the middle of the screen. Every screen in this app is a hand-tuned
/// portrait phone layout, so stretching it across a 1920px window made
/// images and banners huge. Phones (and small windows) are untouched.
class _WebFrame extends StatelessWidget {
  const _WebFrame({required this.child});

  final Widget child;

  /// Wider than this and we frame the app.
  static const double _breakpoint = 700;

  /// Width of the framed app column.
  static const double _appWidth = 460;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= _breakpoint) return child;

    final height = media.size.height;
    final framedHeight = height > 980 ? 940.0 : height;
    final vertical = (height - framedHeight) / 2;

    return ColoredBox(
      color: const Color(0xFF07090D),
      child: Stack(
        children: [
          // Soft gold glow behind the app, matching the brand.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 0.9,
                  colors: [Color(0x26D4A017), Color(0x0007090D)],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: vertical),
              child: Container(
                width: _appWidth,
                height: framedHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(vertical > 0 ? 28 : 0),
                  border: Border.all(color: const Color(0x33D4A017)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 20)),
                  ],
                ),
                // Screens size themselves from MediaQuery, so tell them the
                // real space they have (the column), not the whole window.
                child: MediaQuery(
                  data: media.copyWith(
                    size: Size(_appWidth, framedHeight),
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
