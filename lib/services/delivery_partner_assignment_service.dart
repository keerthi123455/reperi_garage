import 'package:supabase_flutter/supabase_flutter.dart';

/// Assigns each new booking to a delivery partner — hardcoded to exactly
/// three, split by booking type, rather than a dynamic pool, per how the
/// delivery partner program currently works:
///  - 'inspection_booking', 'pollution_booking' and 'claim_table'
///    always go to partner 3 (a dedicated partner for these doorstep
///    services with no vehicle-type rotation of their own).
///  - Everything else ('bookings') alternates between partners 1 and 2 —
///    1, 2, 1, 2, ... — based on how many rows already exist in that
///    table. Mirrors AdminAssignmentService's shape.
class DeliveryPartnerAssignmentService {
  static final _supabase = Supabase.instance.client;

  static const _dedicatedPartnerTables = {
    'inspection_booking',
    'pollution_booking',
    'claim_table',
  };
  static const _dedicatedPartnerId = 3;

  /// Returns the delivery_partners.id to assign for a new row in [table] —
  /// always 3 for inspection/pollution bookings, otherwise 1 or 2 in
  /// alternation — or null if the count lookup fails, so callers can fall
  /// back to leaving delivery_partner_id unset rather than guessing.
  static Future<int?> getNextDeliveryPartnerId(String table) async {
    if (_dedicatedPartnerTables.contains(table)) {
      return _dedicatedPartnerId;
    }

    try {
      final rows = await _supabase.from(table).select('id');
      final count = (rows as List).length;
      return (count % 2) + 1;
    } catch (e) {
      return null;
    }
  }
}
