import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Mobile (Android/iOS) implementation, using the official OneSignal
/// Flutter SDK. Selected automatically for non-web builds by
/// push_notification_service.dart's conditional export.
class PushNotificationService {
  PushNotificationService._();

  static const String _appId = '6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6';

  static bool _initialized = false;

  /// Call once, early in main(), before runApp(). Does NOT request the
  /// OS-level notification permission — that's a separate step
  /// (requestPermission below), fired later from a "soft ask" screen so
  /// the user sees why the app wants to notify them before the native
  /// system prompt appears, instead of getting hit with an unexplained
  /// permission dialog the instant the app cold-launches.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Swallow failures here: main() awaits this before runApp() is
    // ever called, so an uncaught exception (e.g. the native OneSignal
    // SDK missing/misconfigured in a particular build, or thrown before
    // the platform channel is ready) would stop the whole app from
    // launching. A push-notification setup failure should never take
    // down app startup with it.
    try {
      if (kDebugMode) {
        OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      }

      OneSignal.initialize(_appId);
    } catch (_) {}
  }

  /// Prompts the OS-level notification permission dialog (Android 13+,
  /// iOS). Safe to call even on platforms/OS versions that don't need
  /// it — it's a no-op there.
  static Future<void> requestPermission() async {
    try {
      await OneSignal.Notifications.requestPermission(true);
    } catch (_) {
      // Platform channel/SDK failure — leave permission unchanged rather
      // than crashing whichever screen triggered the "soft ask".
    }
  }

  /// Whether the OS has actually granted notification permission right
  /// now. The "soft ask" primer checks this — not a one-time "have we
  /// shown it" flag — so declining once doesn't permanently block every
  /// future notification for the life of the install.
  static bool hasPermission() {
    try {
      return OneSignal.Notifications.permission;
    } catch (_) {
      return false;
    }
  }

  static void loginAsCustomer(String supabaseUserId) {
    _safeLogin('customer_$supabaseUserId');
  }

  static void loginAsFleet(String fleetUserId) {
    _safeLogin('fleet_$fleetUserId');
  }

  static void loginAsAdmin() {
    _safeLogin('admin');
  }

  static void _safeLogin(String externalId) {
    // Called directly from screens' initState()/auth callbacks with no
    // surrounding try/catch of their own — an unguarded platform-channel
    // throw here (e.g. OneSignal not finished initializing yet) would
    // crash whichever screen or auth listener called it.
    try {
      OneSignal.login(externalId);
    } catch (_) {}
  }

  /// Call on logout for any of the three roles, so this device stops
  /// being targeted as that identity once they've signed out.
  static void logout() {
    try {
      OneSignal.logout();
    } catch (_) {}
  }
}