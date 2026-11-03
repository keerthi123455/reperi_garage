import 'package:supabase_flutter/supabase_flutter.dart';

/// Reperi's customer contact numbers — set in the CRM ("Contact numbers"
/// tab), stored in the Supabase `app_settings` table:
///   contact_phone      number customers CALL         (e.g. "+919180605225")
///   contact_whatsapp   number customers WHATSAPP     (e.g. "919180605225")
///
/// Every Call / WhatsApp button in the app reads from here instead of a
/// hard-coded number. Loaded once at start-up (main.dart); until it loads,
/// or if it can't (offline), the fallbacks below are used.
class ContactSettings {
  ContactSettings._();

  static const String _fallbackPhone = '+919180605225';
  static const String _fallbackWhatsApp = '919353094672';

  static String _phone = _fallbackPhone;
  static String _whatsapp = _fallbackWhatsApp;
  static Future<void>? _loading;

  /// Number to call, e.g. "+919180605225".
  static String get phone => _phone;

  /// WhatsApp number in wa.me form: digits only, with country code.
  static String get whatsapp => _whatsapp;

  /// "9180605225" — 10-digit Indian number (same length the app always
  /// showed, so no layout changes). Dialable as-is in India.
  static String get phoneLocal {
    final d = _phone.replaceAll(RegExp(r'\D'), '');
    return d.length == 12 && d.startsWith('91') ? d.substring(2) : d;
  }

  /// "+91 91806 05225" — for showing on screen.
  static String get phoneDisplay {
    final d = _phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 12 && d.startsWith('91')) {
      return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
    }
    return _phone;
  }

  static Uri telUri() => Uri(scheme: 'tel', path: _phone);

  /// https://wa.me/<number>?text=<message>
  static String whatsappUrl([String? message]) {
    final base = 'https://wa.me/$_whatsapp';
    if (message == null || message.isEmpty) return base;
    return '$base?text=${Uri.encodeComponent(message)}';
  }

  static Uri whatsappUri([String? message]) => Uri.parse(whatsappUrl(message));

  /// Safe to call many times; loads once. Never throws.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('app_settings')
          .select('key,value')
          .inFilter('key', ['contact_phone', 'contact_whatsapp']);
      for (final r in rows as List) {
        final raw = r['value'];
        final v = (raw is String ? raw : raw?.toString() ?? '').trim();
        final digits = v.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 10) continue;
        if (r['key'] == 'contact_phone') {
          _phone = v.startsWith('+') ? '+$digits' : (digits.length == 10 ? '+91$digits' : '+$digits');
        } else if (r['key'] == 'contact_whatsapp') {
          _whatsapp = digits.length == 10 ? '91$digits' : digits;
        }
      }
    } catch (_) {
      // Offline / not set yet → keep the fallbacks, try again next time.
      _loading = null;
    }
  }
}
