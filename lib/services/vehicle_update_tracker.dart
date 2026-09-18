import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks whether a vehicle has an update from any of the four sources a
/// customer can hear from — the garage (regular service bookings), a
/// delivery partner (the pickup/drop stage tracker), a washer (subscription
/// service history), or an insurance claim — so the home screen can show a
/// notification bell that goes off once the customer has actually viewed
/// vehicle_bookings_screen.dart, where all four are shown.
///
/// Only the garage's chat has a real server-side "read" flag
/// (`booking_chats.is_read_by_consumer`, the same one
/// vehicle_bookings_screen.dart and booking_tracking_screen.dart already
/// use). Booking status, delivery stage, wash history, and claim updates
/// have no such column, so those are tracked locally: whenever the current
/// value differs from what was last snapshotted as "seen" for this device,
/// it counts as a fresh update.
class VehicleUpdateTracker {
  static const _prefix = 'vehicle_update_seen_';

  /// Every update source's current state for [vehicleId], keyed so each
  /// value can be compared (by [hasUpdate]) or recorded (by [markSeen])
  /// independently. Rebuilt fresh on every call rather than cached, since
  /// this is only ever called right before one of those two things.
  static Future<Map<String, String>> _currentSignature(String vehicleId) async {
    final supabase = Supabase.instance.client;
    final signature = <String, String>{};

    // Garage — booking status and (for pickup/drop bookings) delivery stage.
    try {
      final bookings = List<Map<String, dynamic>>.from(
        await supabase
            .from('bookings')
            .select('id, booking_status, delivery_stage')
            .eq('vehicle_id', vehicleId),
      );
      for (final b in bookings) {
        final id = b['id'].toString();
        final status = (b['booking_status'] ?? '').toString();
        if (status.isNotEmpty) signature['booking_status_$id'] = status;
        final stage = (b['delivery_stage'] ?? '').toString();
        if (stage.isNotEmpty) signature['delivery_stage_bookings_$id'] = stage;
      }
    } catch (_) {
      // Table/columns unreachable — leave this source out of the signature
      // rather than failing the whole check.
    }

    // Delivery guy — pollution/inspection pickup+drop stage tracker.
    for (final table in ['pollution_booking', 'inspection_booking']) {
      try {
        final rows = List<Map<String, dynamic>>.from(
          await supabase.from(table).select('id, delivery_stage').eq('vehicle_id', vehicleId),
        );
        for (final r in rows) {
          final stage = (r['delivery_stage'] ?? '').toString();
          if (stage.isNotEmpty) signature['delivery_stage_${table}_${r['id']}'] = stage;
        }
      } catch (_) {}
    }

    // Washer — a new completed-wash entry in service_history.
    try {
      final sub = await supabase
          .from('subscriptions')
          .select('id')
          .eq('vehicle_id', vehicleId)
          .maybeSingle();
      if (sub != null) {
        final subId = sub['id'].toString();
        final history = List<Map<String, dynamic>>.from(
          await supabase
              .from('service_history')
              .select('id')
              .eq('subscription_id', sub['id'])
              .order('created_at', ascending: false)
              .limit(1),
        );
        if (history.isNotEmpty) {
          signature['service_history_$subId'] = history.first['id'].toString();
        }
      }
    } catch (_) {}

    // Insurance — claim status plus the latest entry in its update feed.
    try {
      final claims = List<Map<String, dynamic>>.from(
        await supabase.from('insurance_claims').select('id, claim_status').eq('vehicle_id', vehicleId),
      );
      for (final c in claims) {
        final claimId = c['id'].toString();
        final status = (c['claim_status'] ?? '').toString();
        if (status.isNotEmpty) signature['claim_status_$claimId'] = status;
        final updates = List<Map<String, dynamic>>.from(
          await supabase
              .from('insurance_claims_updates')
              .select('id')
              .eq('claim_id', c['id'])
              .order('created_at', ascending: false)
              .limit(1),
        );
        if (updates.isNotEmpty) {
          signature['claim_update_$claimId'] = updates.first['id'].toString();
        }
      }
    } catch (_) {}

    return signature;
  }

  /// Whether [vehicleId] has anything new to show since it was last marked
  /// seen — an unread garage chat message, or any locally-tracked value
  /// that's changed. Drives the home-screen card's notification bell.
  static Future<bool> hasUpdate(String vehicleId) async {
    try {
      final supabase = Supabase.instance.client;

      final bookingIds = List<Map<String, dynamic>>.from(
        await supabase.from('bookings').select('id').eq('vehicle_id', vehicleId),
      ).map((b) => b['id'].toString()).toList();

      if (bookingIds.isNotEmpty) {
        final unread = List<Map<String, dynamic>>.from(
          await supabase
              .from('booking_chats')
              .select('id')
              .inFilter('booking_id', bookingIds)
              .eq('sender', 'admin')
              .eq('is_read_by_consumer', false)
              .limit(1),
        );
        if (unread.isNotEmpty) return true;
      }

      final signature = await _currentSignature(vehicleId);
      final prefs = await SharedPreferences.getInstance();
      for (final entry in signature.entries) {
        if (prefs.getString('$_prefix${vehicleId}_${entry.key}') != entry.value) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Snapshots every update source's current state as "seen" for
  /// [vehicleId] — call this once the customer has actually landed on that
  /// vehicle's bookings screen, so the bell clears there instead of staying
  /// stuck until some unrelated reload happens to notice nothing's new.
  static Future<void> markSeen(String vehicleId) async {
    try {
      final signature = await _currentSignature(vehicleId);
      final prefs = await SharedPreferences.getInstance();
      for (final entry in signature.entries) {
        await prefs.setString('$_prefix${vehicleId}_${entry.key}', entry.value);
      }
    } catch (_) {}
  }
}
