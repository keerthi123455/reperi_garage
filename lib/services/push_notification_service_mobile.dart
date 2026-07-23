import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Mobile (Android/iOS) implementation, using the official OneSignal
/// Flutter SDK. Selected automatically for non-web builds by
/// push_notification_service.dart's conditional export.
class PushNotificationService {
  PushNotificationService._();

  static const String _appId = '6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6';

  static bool _initialized = false;

  /// Call once, early in main(), before runApp().
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(_appId);

    // Prompts the OS-level notification permission dialog (Android 13+,
    // iOS). Safe to call even on platforms/OS versions that don't need
    // it — it's a no-op there.
    await OneSignal.Notifications.requestPermission(true);
  }

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