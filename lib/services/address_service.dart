import 'package:supabase_flutter/supabase_flutter.dart';

class AddressService {
  static final AddressService _instance = AddressService._internal();

  factory AddressService() {
    return _instance;
  }

  AddressService._internal();

  final supabase = Supabase.instance.client;

  // ── Get all addresses for current user ──
  Future<List<Map<String, dynamic>>> getUserAddresses() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return [];

      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', user.id)
          .order('is_default', ascending: false)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching addresses: $e');
      return [];
    }
  }

  // ── Get default address ──
  Future<Map<String, dynamic>?> getDefaultAddress() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', user.id)
          .eq('is_default', true)
          .limit(1);

      if (response.isEmpty) {
        // Return first address if no default set
        final allAddresses = await getUserAddresses();
        return allAddresses.isNotEmpty ? allAddresses.first : null;
      }

      return response[0];
    } catch (e) {
      print('Error fetching default address: $e');
      return null;
    }
  }

  // ── Add new address ──
  Future<bool> addAddress({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    bool isDefault = false,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      // If this is default, unset previous default
      if (isDefault) {
        await supabase
            .from('user_addresses')
            .update({'is_default': false})
            .eq('user_id', user.id)
            .eq('is_default', true);
      }

      await supabase.from('user_addresses').insert({
        'user_id': user.id,
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'is_default': isDefault,
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Error adding address: $e');
      return false;
    }
  }

  // ── Update address ──
  Future<bool> updateAddress({
    required String addressId,
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    bool? isDefault,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      // If setting as default, unset others
      if (isDefault == true) {
        await supabase
            .from('user_addresses')
            .update({'is_default': false})
            .eq('user_id', user.id)
            .eq('is_default', true);
      }

      final updateData = {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      };

      if (isDefault != null) {
        updateData['is_default'] = isDefault;
      }

      await supabase
          .from('user_addresses')
          .update(updateData)
          .eq('id', addressId)
          .eq('user_id', user.id);

      return true;
    } catch (e) {
      print('Error updating address: $e');
      return false;
    }
  }

  // ── Delete address ──
  Future<bool> deleteAddress(String addressId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      await supabase
          .from('user_addresses')
          .delete()
          .eq('id', addressId)
          .eq('user_id', user.id);

      return true;
    } catch (e) {
      print('Error deleting address: $e');
      return false;
    }
  }

  // ── Set address as default ──
  Future<bool> setAsDefault(String addressId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      // Unset current default
      await supabase
          .from('user_addresses')
          .update({'is_default': false})
          .eq('user_id', user.id)
          .eq('is_default', true);

      // Set new default
      await supabase
          .from('user_addresses')
          .update({'is_default': true})
          .eq('id', addressId)
          .eq('user_id', user.id);

      return true;
    } catch (e) {
      print('Error setting default address: $e');
      return false;
    }
  }

  // ── Save first location as default on first app launch ──
  Future<void> initializeDefaultAddress({
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Check if user already has addresses
      final existingAddresses = await getUserAddresses();
      if (existingAddresses.isNotEmpty) return; // Already has addresses

      // Add as first/default address
      await addAddress(
        name: 'Home',
        address: address,
        latitude: latitude,
        longitude: longitude,
        isDefault: true,
      );
    } catch (e) {
      print('Error initializing default address: $e');
    }
  }
}