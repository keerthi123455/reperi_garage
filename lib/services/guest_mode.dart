import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Login as guest": browse the whole app without an account. Nothing is
/// created on the server for a guest — there is simply no Supabase session.
/// The flag only remembers the choice so the next app start opens Home
/// instead of the login screen.
///
/// The moment the guest books something (or adds a car / address), the
/// account sheet (see account_gate_sheet.dart) signs them up in place.
class GuestMode {
  GuestMode._();

  static const _key = 'guest_mode';

  /// True when nobody is signed in. Every screen already copes with a null
  /// `currentUser` (it shows empty lists), so "guest" just means that.
  static bool get isGuest => Supabase.instance.client.auth.currentUser == null;

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// [source] says where "Continue as Guest" was tapped — saved with the
  /// guest-login record ('login_button', 'signup_button', 'login_popup',
  /// 'signup_popup').
  static Future<void> enable({String source = 'unknown'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
    // Not awaited — never slow down or block the guest getting in.
    _recordGuestLogin(source);
  }

  // ── guest_logins table (see supabase/guest_logins.sql) ────────────────
  static const _deviceIdKey = 'guest_device_id';

  /// A random id made once per install / browser — nothing personal. It
  /// only lets the guest_logins table tell repeat visits from new devices.
  static Future<String?> _deviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id == null || id.isEmpty) {
        final r = Random.secure();
        id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await prefs.setString(_deviceIdKey, id);
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name;
    }
  }

  static Future<void> _recordGuestLogin(String source) async {
    try {
      await Supabase.instance.client.from('guest_logins').insert({
        'device_id': await _deviceId(),
        'platform': _platform,
        'source': source,
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Analytics only — never surface this to the guest.
      debugPrint('guest_logins insert failed: $e');
    }
  }

  static Future<void> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
