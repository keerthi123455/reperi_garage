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

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(_appId);
  }

  /// Prompts the OS-level notification permission dialog (Android 13+,
  /// iOS). Safe to call even on platforms/OS versions that don't need
  /// it — it's a no-op there.
  static Future<void> requestPermission() async {
    await OneSignal.Notifications.requestPermission(true);
  }

  /// Whether the OS has actually granted notification permission right
  /// now. The "soft ask" primer checks this — not a one-time "have we
  /// shown it" flag — so declining once doesn't permanently block every
  /// future notification for the life of the install.
  static bool hasPermission() => OneSignal.Notifications.permission;

  static void loginAsCustomer(String supabaseUserId) {
    OneSignal.login('customer_$supabaseUserId');
  }

  static void loginAsFleet(String fleetUserId) {
    OneSignal.login('fleet_$fleetUserId');
  }

  static void loginAsAdmin() {
    OneSignal.login('admin');
  }

  /// Call on logout for any of the three roles, so this device stops
  /// being targeted as that identity once they've signed out.
  static void logout() {
    OneSignal.logout();
  }
}