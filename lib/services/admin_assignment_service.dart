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
  /// Returns:
  ///   - String ID of the assigned admin if successful
  ///   - null if no admins exist or on error
  static Future<String?> getNextAdminId() async {
    try {
      // STEP 1: Fetch all admins ordered by ID
      final adminsResponse = await _supabase
          .from('admin')
          .select('id')
          .order('id', ascending: true);
      
      if (adminsResponse.isEmpty) {
        return null;
      }
      
      final adminIds = (adminsResponse as List)
          .map((admin) => admin['id'] as String)
          .toList();
      
      // STEP 2: Count total bookings in the system
      final totalBookings = await _countTotalBookings();
      
      // STEP 3: Calculate which admin should get this booking
      // Each admin gets [bookingsPerAdmin] bookings before rotating
      final adminIndex = (totalBookings ~/ bookingsPerAdmin) % adminIds.length;
      final assignedAdminId = adminIds[adminIndex];
      
      return assignedAdminId;
      
    } catch (e) {
      return null;
    }
  }
  
  /// Counts total number of bookings in the system
  /// Uses simple, reliable select('id') approach
  static Future<int> _countTotalBookings() async {
    try {
      // Fetch all booking IDs - most reliable method
      final allBookings = await _supabase
          .from('bookings')
          .select('id');
      
      return (allBookings as List).length;
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