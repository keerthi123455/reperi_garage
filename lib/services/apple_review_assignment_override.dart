import 'package:supabase_flutter/supabase_flutter.dart';

/// App Store review accounts, as seen by the GARAGE dashboard.
///
/// Who a booking is ASSIGNED to (review garage / delivery partner / washer)
/// is decided on the server now — see the `review_overrides` table and the
/// `review_override_enabled` setting in `app_settings`, used by the
/// booking-api Edge Function. Turn review routing off there after approval;
/// no app update needed.
///
/// What's left here only controls what the review garage account SEES on
/// its dashboard (its own fleet requests and claims), so set [enabled] to
/// false in a later release once review is over.
class AppleReviewAssignmentOverride {
  static const bool enabled = true;

  /// The garage (admin) login Apple reviews with.
  static const String adminUsername = 'appreview@gmail.com';

  /// The fleet login (fleet_pickup_requests.username) Apple reviews with.
  /// Only this account's fleet requests show on the review garage; every
  /// real fleet company's requests stay with haya_autogears.
  static const String reviewFleetUsername = 'appreview@gmail.com';

  static final _supabase = Supabase.instance.client;
  static String? _cachedAdminId;

  /// The review admin's admin.id (a uuid), or null if that account
  /// doesn't exist yet / [enabled] is false.
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
}
