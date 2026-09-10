import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Mobile (Android/iOS) implementation, using the official OneSignal
/// Flutter SDK. Selected automatically for non-web builds by
/// push_notification_service.dart's conditional export.
class PushNotificationService {
  PushNotificationService._();

  static const String _appId = '6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6';

  static bool _initialized = false;

  /// Call once, early in main(), before runApp(). Only sets up the SDK —
  /// does NOT prompt for notification permission, so it's safe to call
  /// before the user has seen any screen. Call [requestPermission]
  /// separately once there's actual context for why (e.g. right after
  /// login), per Play Store guidance to request permissions only when a
  /// feature that needs them is about to be used.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    }

    OneSignal.initialize(_appId);
  }

  /// Prompts the OS-level notification permission dialog (Android 13+,
  /// iOS). Safe to call multiple times or on platforms/OS versions that
  /// don't need it — the OS only ever shows the dialog once per install
  /// (until the user resets permissions), so this is a no-op if the user
  /// already granted or denied it.
  static Future<void> requestPermission() async {
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