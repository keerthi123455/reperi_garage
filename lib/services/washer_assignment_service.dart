import 'package:supabase_flutter/supabase_flutter.dart';
import 'apple_review_assignment_override.dart';

/// Assigns a washer to a one-time wash-package booking (the ₹299/₹599
/// tiers on washing_package_screen.dart) — alternates between washer 1
/// and washer 2 based on how many [table] rows already have a washer_id
/// set, mirroring DeliveryPartnerAssignmentService's exact alternation
/// shape. Separate from Monthly Wash's own washer_id, which
/// monthly_wash_screen.dart sets directly since it has no alternation
/// (every real subscription is left unassigned until a human assigns one
/// by hand today).
class WasherAssignmentService {
  static final _supabase = Supabase.instance.client;

  /// Returns the washers.id to assign for a new row in [table] — the
  /// Apple review washer while review routing applies to [customerEmail]
  /// (see AppleReviewAssignmentOverride), otherwise 1 or 2 in alternation.
  /// Null if the count lookup fails, so callers can fall back to leaving
  /// washer_id unset rather than guessing.
  static Future<int?> getNextWasherId(
    String table, {
    required String? customerEmail,
  }) async {
    final reviewWasherId = await AppleReviewAssignmentOverride.resolveWasherId(
      customerEmail: customerEmail,
    );
    if (reviewWasherId != null) return reviewWasherId;

    try {
      final rows = await _supabase
          .from(table)
          .select('id')
          .not('washer_id', 'is', null);
      final count = (rows as List).length;
      return (count % 2) + 1;
    } catch (e) {
      return null;
    }
  }
}
