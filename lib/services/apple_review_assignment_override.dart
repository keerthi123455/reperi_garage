import 'package:supabase_flutter/supabase_flutter.dart';

/// Review-only routing override.
///
/// While [enabled] is true, every booking that would normally
/// load-balance across real admins/delivery partners instead routes to
/// one fixed test account per role — so an App Store reviewer testing the
/// app end-to-end (customer booking -> garage/delivery dashboard) always
/// lands on the exact demo credentials given in the App Review notes,
/// regardless of how many real admins/partners already exist or how the
/// normal rotation would have split things up.
///
/// Set [enabled] back to false once the app is approved, to restore
/// normal load-balanced assignment for real business use.
class AppleReviewAssignmentOverride {
  static const bool enabled = true;

  static const String adminUsername = 'appreview@gmail.com';
  static const String deliveryPartnerEmail = 'delivery_apple@gmail.com';
  static const String washerEmail = 'washer_apple@gmail.com';

  /// The one customer account this specific override is scoped to —
  /// unlike the admin/delivery overrides above (which apply to every
  /// booking while [enabled] is true, since nothing else naturally
  /// assigns a washer at all), resolveWasherId only ever fires for
  /// bookings made by this exact customer. Any other customer's
  /// subscription is left with no washer_id, exactly like today.
  static const String reviewCustomerEmail = 'appreview@gmail.com';

  static final _supabase = Supabase.instance.client;
  static String? _cachedAdminId;
  static int? _cachedDeliveryPartnerId;
  static int? _cachedWasherId;

  /// The review admin's admin.id (a uuid), or null if that account
  /// doesn't exist yet / [enabled] is false — callers fall back to their
  /// normal assignment logic in that case rather than breaking.
  static Future<String?> resolveAdminId() async {
    if (!enabled) return null;
    if (_cachedAdminId != null) return _cachedAdminId;
    try {
      final row = await _supabase
          .from('admin')
          .select('id')
          .eq('username', adminUsername)
          .maybeSingle();
      _cachedAdminId = row?['id'] as String?;
      return _cachedAdminId;
    } catch (e) {
      return null;
    }
  }

  /// The review delivery partner's delivery_partners.id (an int), or null
  /// if that account doesn't exist yet / [enabled] is false.
  static Future<int?> resolveDeliveryPartnerId() async {
    if (!enabled) return null;
    if (_cachedDeliveryPartnerId != null) return _cachedDeliveryPartnerId;
    try {
      final row = await _supabase
          .from('delivery_partners')
          .select('id')
          .eq('email', deliveryPartnerEmail)
          .maybeSingle();
      _cachedDeliveryPartnerId = row?['id'] as int?;
      return _cachedDeliveryPartnerId;
    } catch (e) {
      return null;
    }
  }

  /// The review washer's washers.id (an int) — but only when [customerEmail]
  /// (the customer actually placing this subscription) is
  /// [reviewCustomerEmail]. Any other customer gets null even while
  /// [enabled] is true, so a real customer's subscription is never
  /// misrouted to the test washer just because review mode happens to be
  /// on — unlike the admin/delivery overrides, nothing else assigns a
  /// washer at all today, so there's no "normal" behavior this could
  /// silently override for a real customer regardless, but scoping it
  /// this way means you don't have to remember to flip [enabled] off
  /// immediately after approval purely for this one case.
  static Future<int?> resolveWasherId({required String? customerEmail}) async {
    if (!enabled) return null;
    if (customerEmail != reviewCustomerEmail) return null;
    if (_cachedWasherId != null) return _cachedWasherId;
    try {
      final row = await _supabase
          .from('washers')
          .select('id')
          .eq('email', washerEmail)
          .maybeSingle();
      _cachedWasherId = row?['id'] as int?;
      return _cachedWasherId;
    } catch (e) {
      return null;
    }
  }
}
