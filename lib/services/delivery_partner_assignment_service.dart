import 'package:supabase_flutter/supabase_flutter.dart';

/// Assigns each new booking to delivery partner 1 or 2, alternating every
/// time — 1, 2, 1, 2, ... — based on how many rows already exist in the
/// table being booked into. Mirrors AdminAssignmentService's shape, but
/// hardcoded to exactly two delivery partners rather than a dynamic pool,
/// per how the delivery partner program currently works.
class DeliveryPartnerAssignmentService {
  static final _supabase = Supabase.instance.client;

  /// Returns 1 or 2 — whichever comes next in the alternation for
  /// [table] — or null if the count lookup fails, so callers can fall
  /// back to leaving delivery_partner_id unset rather than guessing.
  static Future<int?> getNextDeliveryPartnerId(String table) async {
    try {
      final rows = await _supabase.from(table).select('id');
      final count = (rows as List).length;
      return (count % 2) + 1;
    } catch (e) {
      return null;
    }
  }
}
