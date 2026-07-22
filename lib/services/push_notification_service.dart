import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Centralizes all OneSignal setup and identity binding.
///
/// The app has three separate login systems (Supabase Auth for
/// customers, a plain `admin` table, and a plain `fleet_users` table),
/// so "who is this device logged in as" has to be told to OneSignal
/// explicitly at each of those three login points rather than relying
/// on any single shared session mechanism.
///
/// External ID scheme:
///   customer -> 'customer_<supabase_auth_user_id>'
///   fleet    -> 'fleet_<fleet_users.id>'
///   admin    -> 'admin' (fixed — the app currently has a single admin
///               account with no per-admin identity tracked anywhere;
///               revisit this if multi-admin login is ever added)
class PushNotificationService {
  PushNotificationService._();

  static const String _appId = '6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6';

  static bool _initialized = false;

  /// Call once, early in main(), before runApp().
  static Future<void> init() async {
    // The onesignal_flutter package does not support Flutter Web — calling
    // OneSignal.initialize() there throws and crashes app startup. Until
    // the dedicated web implementation (via OneSignal's JS SDK) is built,
    // this is a safe no-op on web so the app still loads normally there.
    if (kIsWeb) return;

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
    if (kIsWeb) return;
    OneSignal.login('customer_$supabaseUserId');
  }

  static void loginAsFleet(String fleetUserId) {
    if (kIsWeb) return;
    OneSignal.login('fleet_$fleetUserId');
  }

  static void loginAsAdmin() {
    if (kIsWeb) return;
    OneSignal.login('admin');
  }

  /// Call on logout for any of the three roles, so this device stops
  /// being targeted as that identity once they've signed out.
  static void logout() {
    if (kIsWeb) return;
    OneSignal.logout();
  }
}