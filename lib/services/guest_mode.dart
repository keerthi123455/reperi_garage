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

  static Future<void> enable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
