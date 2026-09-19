import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for load-balanced admin assignment.
/// 
/// Distribution: Each admin gets exactly 3 bookings before rotating to next admin.
/// Example with 3 admins (A, B, C):
///   Bookings 1-3   → Admin A
///   Bookings 4-6   → Admin B
///   Bookings 7-9   → Admin C
///   Bookings 10-12 → Admin A (cycles back)
///   
/// Formula: admin_index = (total_bookings ÷ 3) mod number_of_admins
class AdminAssignmentService {
  static final _supabase = Supabase.instance.client;
  
  /// Bookings per admin before rotating to the next one
  static const int bookingsPerAdmin = 3;
  
  /// Gets the next admin ID using load-balanced distribution.
  ///
  /// Distributes bookings equally among all available admins,
  /// giving each admin exactly [bookingsPerAdmin] bookings before
  /// rotating to the next admin.
  ///
  /// When [vehicleId] is given, only admins whose `admin.vehicle` matches
  /// that vehicle's type ("two wheeler"/"four wheeler") are eligible — a
  /// two-wheeler booking only ever rotates among two-wheeler admins, and
  /// likewise for four-wheeler. Left null (or the vehicle can't be looked
  /// up, e.g. Roadside Assistance has no single vehicle) for bookings that
  /// aren't tied to one vehicle type, which rotates among every admin as
  /// before.
  ///
  /// When [forcedAdminUsername] is given, it overrides all of the above —
  /// the booking always goes straight to that one admin (e.g. Roadside
  /// Assistance bookings always go to 'emergency_service'), no rotation,
  /// no vehicle-type filtering. Returns null (leaving the booking
  /// unassigned rather than silently handing it to some other admin) if no
  /// admin with that username exists.
  ///
  /// Returns:
  ///   - String ID of the assigned admin if successful
  ///   - null if no matching admins exist or on error
  static Future<String?> getNextAdminId({
    String? vehicleId,
    String? forcedAdminUsername,
  }) async {
    if (forcedAdminUsername != null) {
      return _resolveAdminIdByUsername(forcedAdminUsername);
    }

    try {
      final vehicleLabel = await _resolveAdminVehicleLabel(vehicleId);

      // STEP 1: Fetch eligible admins ordered by ID
      var query = _supabase.from('admin').select('id');
      if (vehicleLabel != null) {
        query = query.eq('vehicle', vehicleLabel);
      }
      final adminsResponse = await query.order('id', ascending: true);

      if (adminsResponse.isEmpty) {
        return null;
      }

      final adminIds = (adminsResponse as List)
          .map((admin) => admin['id'] as String)
          .toList();

      // STEP 2: Count bookings already assigned within this same admin
      // pool — scoping the counter this way keeps the "3 bookings then
      // rotate" rule correct within each vehicle type, regardless of how
      // much booking volume the other type has.
      final poolBookings = await _countBookingsForAdmins(adminIds);

      // STEP 3: Calculate which admin should get this booking
      // Each admin gets [bookingsPerAdmin] bookings before rotating
      final adminIndex = (poolBookings ~/ bookingsPerAdmin) % adminIds.length;
      final assignedAdminId = adminIds[adminIndex];

      return assignedAdminId;

    } catch (e) {
      return null;
    }
  }

  /// Looks up an admin's id by their exact `admin.username` — used for
  /// [forcedAdminUsername] assignment, bypassing rotation entirely.
  static Future<String?> _resolveAdminIdByUsername(String username) async {
    try {
      final row = await _supabase
          .from('admin')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Looks up the `admin.vehicle` label ("two wheeler"/"four wheeler") that
  /// matches [vehicleId]'s `vehicles.vehicle_type` ('two_wheeler'/
  /// 'four_wheeler'). Null when there's no vehicle to key off of, or it
  /// can't be found — callers then fall back to every admin.
  static Future<String?> _resolveAdminVehicleLabel(String? vehicleId) async {
    if (vehicleId == null || vehicleId.isEmpty) return null;
    try {
      final row = await _supabase
          .from('vehicles')
          .select('vehicle_type')
          .eq('id', vehicleId)
          .maybeSingle();
      return switch (row?['vehicle_type'] as String?) {
        'two_wheeler' => 'two wheeler',
        'four_wheeler' => 'four wheeler',
        _ => null,
      };
    } catch (e) {
      return null;
    }
  }

  /// Counts bookings already assigned to any admin in [adminIds].
  static Future<int> _countBookingsForAdmins(List<String> adminIds) async {
    if (adminIds.isEmpty) return 0;
    try {
      final bookings = await _supabase
          .from('bookings')
          .select('id')
          .inFilter('assigned_to_admin_id', adminIds);

      return (bookings as List).length;
    } catch (e) {
      // If query fails, default to 0 (will assign to first admin)
      return 0;
    }
  }
  
  /// Helper: Get count of bookings assigned to a specific admin
  /// Can be used for monitoring and debugging
  static Future<int> getAdminBookingCount(String adminId) async {
    try {
      final bookings = await _supabase
          .from('bookings')
          .select('id')
          .eq('assigned_to_admin_id', adminId);
      
      return (bookings as List).length;
    } catch (e) {
      return 0;
    }
  }
  
  /// Helper: Get all admins with their booking counts
  /// Useful for monitoring load distribution
  /// Returns map of admin_id -> booking_count
  static Future<Map<String, int>> getAdminDistribution() async {
    try {
      final distribution = <String, int>{};
      
      // Get all admins
      final adminsResponse = await _supabase
          .from('admin')
          .select('id');
      
      if (adminsResponse.isEmpty) {
        return distribution;
      }
      
      final adminIds = (adminsResponse as List)
          .map((admin) => admin['id'] as String)
          .toList();
      
      // Count bookings for each admin
      for (final adminId in adminIds) {
        final count = await getAdminBookingCount(adminId);
        distribution[adminId] = count;
      }
      
      return distribution;
    } catch (e) {
      return {};
    }
  }
}