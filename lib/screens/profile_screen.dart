import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_colors.dart';
import 'login_screen.dart';
import '../services/error_handler.dart';
import '../widgets/error_display.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> vehicles = [];
  bool loading = true;
  bool _deletingAccount = false;

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This will permanently delete your profile, vehicles, and booking history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    setState(() => _deletingAccount = true);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'delete-account',
      );

      if (response.status != 200) {
        throw Exception('Failed to delete account');
      }

      await Supabase.instance.client.auth.signOut();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      
      ErrorDisplay.showErrorDialog(
        context,
        title: 'Failed to Delete Account',
        message: 'We could not delete your account. Please try again or contact support if the problem persists.',
        actionLabel: 'OK',
        onRetry: _deleteAccount,
      );
    }
  }

  final Map<String, List<String>> brandsByType = {
    'four_wheeler': [
      'Hyundai', 'Tata', 'Maruti Suzuki', 'Mahindra', 'Honda',
      'Toyota', 'Kia', 'MG', 'Volkswagen', 'Skoda', 'Renault',
      'Nissan', 'Ford', 'BMW', 'Mercedes', 'Audi', 'Jeep',
      'Volvo', 'Lexus', 'Porsche',
    ],
    'two_wheeler': [
      'Honda', 'Hero', 'Bajaj', 'TVS', 'Royal Enfield', 'Yamaha',
      'Suzuki', 'KTM', 'Ather', 'Ola Electric', 'Vespa', 'Jawa',
    ],
  };

  final vehicleTypeLabels = {
    'four_wheeler': 'Four Wheeler',
    'two_wheeler': 'Two Wheeler',
  };

  @override
  void initState() {
    super.initState();
    fetchVehicles();
  }

  Future<void> fetchVehicles() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await supabase
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        vehicles = List<Map<String, dynamic>>.from(response);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      
      final errorMessage = ErrorHandler.getUserMessage(e);
      ErrorDisplay.showErrorSnackBar(
        context,
        message: errorMessage,
        onRetry: fetchVehicles,
      );
    }
  }

  // ── Check if vehicle has active service ──
  Future<bool> _checkActiveService(String vehicleId) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('bookings')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isEmpty) return false;
      
      final booking = response[0];
      final status = booking['booking_status'] as String?;
      
      // Cannot delete if there's any booking that is NOT Delivered
      // Allowed to delete only if:
      // 1. No bookings exist, OR
      // 2. Latest booking status is "Delivered"
      if (status == null) return false;
      
      final statusLower = status.toLowerCase();
      
      // Check if booking has active status (service in progress)
      // Do not allow deletion if status is any of these (except Delivered)
      return statusLower != 'delivered' && 
             (statusLower == 'confirmed' || 
              statusLower == 'in_progress' ||
              statusLower == 'accepted' ||
              statusLower == 'scheduled');
    } catch (e) {
      return false;
    }
  }

  // ── Show delete confirmation dialog ──
  Future<void> _confirmDeleteVehicle(Map<String, dynamic> vehicle) async {
    // First check if there's an active service
    final hasActiveService = await _checkActiveService(vehicle['id'] as String);

    if (!mounted) return;

    if (hasActiveService) {
      // Show "Cannot delete" dialog with warning
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.error_rounded, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cannot Delete Vehicle',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.red),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
              ),
              const SizedBox(height: 24),
              const Text(
                'Vehicle Cannot Be Deleted',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This vehicle has a service in progress. Please wait until the service is delivered before attempting to delete.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                  height: 1.6,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Understood',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Show delete confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete Vehicle?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, 
                color: Colors.orange, size: 40),
            ),
            const SizedBox(height: 20),
            Text(
              '${vehicle['car_brand']} ${vehicle['car_model']}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Are you sure you want to delete this vehicle? All the service history and progress will be lost.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'No',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Yes, I understand',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteVehicle(vehicle['id'] as String);
    }
  }

  // ── Delete vehicle from database ──
  Future<void> _deleteVehicle(String vehicleId) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Delete the vehicle
      await supabase
          .from('vehicles')
          .delete()
          .eq('id', vehicleId);

      if (!mounted) return;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle deleted successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Refresh the vehicle list
      await fetchVehicles();
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete vehicle: ${ErrorHandler.getUserMessage(e)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void openAddVehicleSheet() {
    final nameController = TextEditingController();
    final carModelController = TextEditingController();
    final carNumberController = TextEditingController();
    String selectedVehicleType = 'four_wheeler';
    String selectedBrand = brandsByType[selectedVehicleType]!.first;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 28,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44, height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Add Vehicle',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 24),
                   _sheetField(nameController, 'Your Name', Icons.person_outline),
                  const SizedBox(height: 16),
                  // Vehicle Type Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedVehicleType,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: vehicleTypeLabels.entries.map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value),
                        )).toList(),
                        onChanged: (v) => setSheetState(() {
                          selectedVehicleType = v!;
                          selectedBrand = brandsByType[selectedVehicleType]!.first;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Brand Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedBrand,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        items: brandsByType[selectedVehicleType]!.map((b) => DropdownMenuItem(
                          value: b, child: Text(b),
                        )).toList(),
                        onChanged: (v) => setSheetState(() => selectedBrand = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetField(carModelController, 'Car Model', Icons.directions_car_outlined),
                  const SizedBox(height: 16),
                  _sheetField(carNumberController, 'Car Number', Icons.badge_outlined),
                  const SizedBox(height: 28),
                  GestureDetector(
                    onTap: saving ? null : () async {
                      if (nameController.text.trim().isEmpty ||
                          carModelController.text.trim().isEmpty ||
                          carNumberController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please fill all fields.')),
                        );
                        return;
                      }

                      setSheetState(() => saving = true);

                      final supabase = Supabase.instance.client;
                      final user = supabase.auth.currentUser;
                      if (user == null) return;

                      try {
                         final inserted = await supabase.from('vehicles').insert({
                          'user_id': user.id,
                          'vehicle_type': selectedVehicleType,
                          'car_brand': selectedBrand,
                          'car_model': carModelController.text.trim(),
                          'car_number': carNumberController.text.trim(),
                        }).select().single();

                        final existing = await supabase
                            .from('profiles')
                            .select()
                            .eq('id', user.id)
                            .maybeSingle();

                        if (existing == null) {
                          await supabase.from('profiles').insert({
                            'id': user.id,
                            'name': nameController.text.trim(),
                            'email': user.email,
                            'active_vehicle_id': inserted['id'],
                          });
                        } else {
                          await supabase.from('profiles').update({
                            'active_vehicle_id': inserted['id'],
                          }).eq('id', user.id);
                        }

                        if (!mounted) return;
                        Navigator.pop(ctx);
                        fetchVehicles();
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Vehicle added successfully!',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.green.shade700,
                            elevation: 6,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            margin: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setSheetState(() => saving = false);
                        
                        final errorMessage = ErrorHandler.getUserMessage(e);
                        ErrorDisplay.showErrorSnackBar(
                          context,
                          message: errorMessage,
                        );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        color: saving ? AppColors.yellow.withOpacity(0.6) : AppColors.yellow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: saving
                            ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5)
                            : const Text('SAVE VEHICLE',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _sheetField(TextEditingController ctrl, String hint, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          icon: Icon(icon, size: 22),
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Future<void> setActiveVehicle(Map<String, dynamic> vehicle) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('profiles')
          .update({'active_vehicle_id': vehicle['id']})
          .eq('id', user.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      
      final errorMessage = ErrorHandler.getUserMessage(e);
      ErrorDisplay.showErrorSnackBar(
        context,
        message: errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.07),
                                blurRadius: 12, offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text('My Garage',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Vehicle list
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : vehicles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_car_outlined,
                                      size: 80, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text('No vehicles yet',
                                    style: TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade400,
                                    )),
                                  const SizedBox(height: 8),
                                  Text('Tap the button below to add your first car',
                                    style: TextStyle(color: Colors.grey.shade400)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 22),
                              itemCount: vehicles.length,
                              itemBuilder: (_, i) {
                                final v = vehicles[i];
                                return GestureDetector(
                                  onTap: () => setActiveVehicle(v),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(26),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 16, offset: const Offset(4, 6),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        // Serial badge
                                        Container(
                                          width: 44, height: 44,
                                          decoration: BoxDecoration(
                                            color: AppColors.yellow,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Center(
                                            child: Text('${i + 1}',
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                              )),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Car photo (or icon placeholder)
                                        Container(
                                          width: 56, height: 56,
                                          decoration: BoxDecoration(
                                            color: AppColors.yellow.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(18),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: (v['photo_url'] as String?)
                                                      ?.isNotEmpty ==
                                                  true
                                              ? Image.network(
                                                  v['photo_url'] as String,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => Icon(
                                                    v['vehicle_type'] ==
                                                            'two_wheeler'
                                                        ? Icons.two_wheeler_rounded
                                                        : Icons.directions_car_rounded,
                                                    size: 30,
                                                  ),
                                                )
                                              : Icon(
                                                  v['vehicle_type'] == 'two_wheeler'
                                                      ? Icons.two_wheeler_rounded
                                                      : Icons.directions_car_rounded,
                                                  size: 30,
                                                ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text((v['car_model'] ?? '').toString().toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 18, fontWeight: FontWeight.w800)),
                                              const SizedBox(height: 4),
                                              Text((v['car_brand'] ?? '').toString().toUpperCase(),
                                                style: TextStyle(
                                                  color: Colors.grey.shade500, fontSize: 14)),
                                              const SizedBox(height: 2),
                                              Text((v['car_number'] ?? '').toString().toUpperCase(),
                                                style: TextStyle(
                                                  color: Colors.grey.shade400, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        // Delete button
                                        GestureDetector(
                                          onTap: () => _confirmDeleteVehicle(v),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              color: Colors.red.shade600,
                                              size: 22,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                // ADD VEHICLE button
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                  child: GestureDetector(
                    onTap: openAddVehicleSheet,
                    child: Container(
                      width: double.infinity,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.3),
                            blurRadius: 20, offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_rounded, size: 28),
                          SizedBox(width: 10),
                          Text('ADD VEHICLE',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                ),

                // DELETE ACCOUNT — danger zone, deliberately understated
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                  child: TextButton(
                    onPressed: _deletingAccount ? null : _confirmDeleteAccount,
                    child: _deletingAccount
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                          )
                        : const Text(
                            'Delete Account',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}