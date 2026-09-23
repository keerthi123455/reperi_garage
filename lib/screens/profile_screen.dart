import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'login_screen.dart';
import '../services/ai_chat_session.dart';
import '../services/error_handler.dart';
import '../services/vehicle_change_bus.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/bottom_nav_actions.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/error_display.dart';

// Brand highlight yellow — a fixed accent, not a themed surface, used for
// the badges/CTAs on this screen.
const Color _highlightYellow = Color(0xFFFFD600);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.autoOpenAddVehicle = false});

  /// When true, opens the "Add Vehicle" sheet as soon as this screen
  /// appears — used by the home screen's "+" tile at the end of the
  /// vehicle carousel, which should land straight in that flow instead of
  /// just the profile screen.
  final bool autoOpenAddVehicle;

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
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete your account?', style: TextStyle(color: AppColors.txt)),
        content: Text(
          'This will permanently delete your profile, vehicles, and booking history. This action cannot be undone.',
          style: TextStyle(color: AppColors.mut),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.mut)),
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
      AiChatSession.clear();

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
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
    // Fired whenever a vehicle is edited from elsewhere (e.g. the vehicle
    // dashboard's own pencil icon) — re-pulls the list so this screen's
    // tiles reflect the change immediately too.
    vehicleChangeBus.addListener(fetchVehicles);
    if (widget.autoOpenAddVehicle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openAddVehicleSheet();
      });
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    vehicleChangeBus.removeListener(fetchVehicles);
    super.dispose();
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

  // ── Check if vehicle has any active/ongoing engagement ──
  // Blocks deletion while a service booking, pollution/inspection pickup,
  // insurance claim, or subscription is still in progress for this
  // vehicle — losing the vehicle mid-service would orphan whatever's
  // already underway.
  Future<bool> _checkActiveService(String vehicleId) async {
    final supabase = Supabase.instance.client;

    // Looks only at the most recent row per table, matching how the
    // bookings check already worked — an old row that never got marked
    // done shouldn't permanently block deletion once newer ones have.
    Future<bool> latestRowIsActive({
      required String table,
      required String statusColumn,
      required bool Function(String status) isActive,
    }) async {
      try {
        final rows = await supabase
            .from(table)
            .select(statusColumn)
            .eq('vehicle_id', vehicleId)
            .order('created_at', ascending: false)
            .limit(1);
        if (rows.isEmpty) return false;
        final value = (rows.first[statusColumn] ?? '').toString().toLowerCase();
        return isActive(value);
      } catch (e) {
        return false;
      }
    }

    // Same as latestRowIsActive, but also treats a verified return OTP as
    // "done" in its own right — vehicle_bookings_screen.dart's
    // _ReturnOtpVerification._verify() flips booking_status to 'Delivered'
    // on the 'bookings' table the moment it succeeds, but
    // pollution_booking/inspection_booking only reach delivery_stage ==
    // 'delivered' once the delivery partner separately taps their own
    // "Vehicle Delivered" button afterwards. Checking
    // return_otp_verified_at directly means the customer isn't stuck
    // unable to delete the vehicle just because that second tap hasn't
    // happened yet — the OTP handover is what actually matters.
    Future<bool> latestRowIsActiveUnlessReturned({
      required String table,
      required String statusColumn,
    }) async {
      try {
        final rows = await supabase
            .from(table)
            .select('$statusColumn, return_otp_verified_at')
            .eq('vehicle_id', vehicleId)
            .order('created_at', ascending: false)
            .limit(1);
        if (rows.isEmpty) return false;
        final row = rows.first;
        if (row['return_otp_verified_at'] != null) return false;
        final value = (row[statusColumn] ?? '').toString().toLowerCase();
        return value != 'delivered';
      } catch (e) {
        return false;
      }
    }

    // General service bookings go through the stages set in
    // booking_details_screen.dart ('Pending', 'Car Picked Up', 'Inspection
    // In Progress', 'Inspection Completed', 'Service In Progress', 'Billing
    // Process', 'Delivered') — 'Delivered' is the only terminal one, so
    // anything else (including a still-null/'pending' status right after
    // booking) blocks deletion.
    if (await latestRowIsActiveUnlessReturned(
      table: 'bookings',
      statusColumn: 'booking_status',
    )) {
      return true;
    }

    // Pollution/inspection are doorstep pickup+drop bookings — active for
    // as long as the vehicle hasn't actually been delivered back yet.
    if (await latestRowIsActiveUnlessReturned(
      table: 'pollution_booking',
      statusColumn: 'delivery_stage',
    )) {
      return true;
    }

    if (await latestRowIsActiveUnlessReturned(
      table: 'inspection_booking',
      statusColumn: 'delivery_stage',
    )) {
      return true;
    }

    // A claim is only "done" once approved or rejected.
    if (await latestRowIsActive(
      table: 'insurance_claims',
      statusColumn: 'claim_status',
      isActive: (s) => s != 'approved' && s != 'rejected',
    )) {
      return true;
    }

    // Subscriptions have no cancel option in this app — a subscribed
    // vehicle is always "in use" until the subscription itself ends, so
    // its mere existence blocks deletion.
    try {
      final subscriptionRows = await supabase
          .from('subscriptions')
          .select('id')
          .eq('vehicle_id', vehicleId)
          .limit(1);
      if (subscriptionRows.isNotEmpty) return true;
    } catch (e) {
      // Ignore — treated as no active subscription.
    }

    return false;
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
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
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
              Text(
                'Vehicle has active service and cannot be deleted',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.txt,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'I UNDERSTAND',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
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
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Delete Vehicle?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.txt),
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
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.txt,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Are you sure you want to delete this vehicle? All the service history and progress will be lost.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.mut,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'No',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.mut,
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
    final nameFocus = FocusNode();
    final carModelFocus = FocusNode();
    final carNumberFocus = FocusNode();
    String selectedVehicleType = 'four_wheeler';
    String selectedBrand = brandsByType[selectedVehicleType]!.first;
    bool saving = false;
    bool success = false;
    String? errorText;
    bool nameError = false;
    bool carModelError = false;
    bool carNumberError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Bounds the sheet so the Column below can give its fields area a
      // Flexible/scrollable region while pinning the Save button (and any
      // inline error) in a fixed footer that's never pushed off-screen by
      // the keyboard — see the comment on the outer Padding further down.
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final isTwoWheeler = selectedVehicleType == 'two_wheeler';

          final fields = <Widget>[
            _sheetField(
              nameController,
              'Your Name',
              Icons.person_outline,
              focusNode: nameFocus,
              hasError: nameError,
              onChanged: (_) {
                if (nameError) setSheetState(() => nameError = false);
              },
            ),
            // Vehicle Type picker — was a DropdownButton, but its popup
            // menu positions itself once, from the button's on-screen
            // location at the moment it opens. Inside this modal sheet,
            // that location shifts whenever the keyboard opens/closes
            // (the sheet's own bottom padding tracks MediaQuery's
            // viewInsets), so the already-open menu was left stranded
            // near the top of the screen — its position never got
            // recalculated after the shift. A fresh bottom sheet always
            // positions itself against the current screen, so it can't
            // go stale like that.
            _sheetPickerField(
              label: vehicleTypeLabels[selectedVehicleType]!,
              onTap: () async {
                final picked = await _showPickerSheet(
                  title: 'Vehicle Type',
                  options: vehicleTypeLabels.entries
                      .map((e) => MapEntry(e.key, e.value))
                      .toList(),
                  selectedKey: selectedVehicleType,
                );
                if (picked != null) {
                  setSheetState(() {
                    selectedVehicleType = picked;
                    selectedBrand = brandsByType[selectedVehicleType]!.first;
                  });
                }
              },
            ),
            // Brand picker — same fix as Vehicle Type above.
            _sheetPickerField(
              label: selectedBrand,
              onTap: () async {
                final picked = await _showPickerSheet(
                  title: 'Brand',
                  options: brandsByType[selectedVehicleType]!
                      .map((b) => MapEntry(b, b))
                      .toList(),
                  selectedKey: selectedBrand,
                );
                if (picked != null) {
                  setSheetState(() => selectedBrand = picked);
                }
              },
            ),
            // Hint text (and icon) follows the selected vehicle type —
            // "Car Model"/"Car Number" for a four-wheeler, "Two Wheeler
            // Model"/"Two Wheeler Number" for a two-wheeler.
            _sheetField(
              carModelController,
              isTwoWheeler ? 'Two Wheeler Model' : 'Car Model',
              isTwoWheeler ? Icons.two_wheeler_outlined : Icons.directions_car_outlined,
              focusNode: carModelFocus,
              hasError: carModelError,
              onChanged: (_) {
                if (carModelError) setSheetState(() => carModelError = false);
              },
            ),
            _sheetField(
              carNumberController,
              isTwoWheeler ? 'Two Wheeler Number' : 'Car Number',
              Icons.badge_outlined,
              focusNode: carNumberFocus,
              hasError: carNumberError,
              onChanged: (_) {
                if (carNumberError) setSheetState(() => carNumberError = false);
              },
            ),
          ];

          final saveButton = GestureDetector(
            onTap: saving ? null : () async {
              final nameEmpty = nameController.text.trim().isEmpty;
              final modelEmpty = carModelController.text.trim().isEmpty;
              final numberEmpty = carNumberController.text.trim().isEmpty;

              if (nameEmpty || modelEmpty || numberEmpty) {
                setSheetState(() {
                  nameError = nameEmpty;
                  carModelError = modelEmpty;
                  carNumberError = numberEmpty;
                });
                // Focus lands on the first empty field, in field order.
                if (nameEmpty) {
                  nameFocus.requestFocus();
                } else if (modelEmpty) {
                  carModelFocus.requestFocus();
                } else {
                  carNumberFocus.requestFocus();
                }
                return;
              }

              final supabase = Supabase.instance.client;
              final user = supabase.auth.currentUser;
              if (user == null) return;

              setSheetState(() {
                saving = true;
                errorText = null;
              });

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
                  // The "Your Name" field is shown (and required) on every
                  // vehicle add, not just the first — it needs to actually
                  // save here too, or re-entering it after the first
                  // vehicle silently does nothing and the drawer keeps
                  // showing whatever (or nothing) was saved originally.
                  await supabase.from('profiles').update({
                    'name': nameController.text.trim(),
                    'active_vehicle_id': inserted['id'],
                  }).eq('id', user.id);
                }

                setSheetState(() {
                  saving = false;
                  success = true;
                });

                // Let the checkmark register before the sheet closes.
                await Future.delayed(const Duration(milliseconds: 550));

                if (!mounted) return;
                Navigator.pop(ctx);
                await fetchVehicles();
                vehicleChangeBus.notifyVehicleUpdated();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: Colors.white),
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
                final errorMessage = ErrorHandler.getUserMessage(e);
                setSheetState(() {
                  saving = false;
                  errorText = errorMessage;
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: success
                    ? Colors.green.shade600
                    : (saving ? _highlightYellow.withOpacity(0.6) : _highlightYellow),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: success
                      ? const Icon(Icons.check_rounded, key: ValueKey('check'), color: Colors.white, size: 28)
                      : saving
                          ? SizedBox(
                              key: const ValueKey('spinner'),
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: AppColors.onAccentDark, strokeWidth: 2.5),
                            )
                          : Text(
                              'SAVE VEHICLE',
                              key: const ValueKey('label'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onAccentDark),
                            ),
                ),
              ),
            ),
          );

          // The keyboard shrinks the sheet's available height from the
          // bottom, not the top — pushing this whole Padding up by
          // viewInsets.bottom (rather than padding *inside* a scroll
          // view) keeps the fixed footer glued just above the keyboard
          // instead of being carried off past the bottom of the visible
          // area.
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 44, height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Vehicle',
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.txt),
                          ),
                          const SizedBox(height: 24),
                          for (int i = 0; i < fields.length; i++) ...[
                            _StaggerFadeIn(index: i, child: fields[i]),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: Column(
                      children: [
                        // Shown right inside the sheet — a SnackBar tied
                        // to the page underneath would render behind this
                        // still-open modal and never actually be seen.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: errorText == null
                              ? const SizedBox.shrink(key: ValueKey('no-error'))
                              : Padding(
                                  key: const ValueKey('error'),
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.red.withOpacity(0.35)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            errorText ?? '',
                                            style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        saveButton,
                      ],
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

  /// Mirrors [openAddVehicleSheet]'s sheet/field structure, pre-filled with
  /// [vehicle]'s current values, and UPDATEs the existing row instead of
  /// inserting a new one. Reachable via the pencil icon on each vehicle
  /// tile below.
  void _editVehicleSheet(Map<String, dynamic> vehicle) {
    final carModelController =
        TextEditingController(text: (vehicle['car_model'] ?? '').toString());
    final carNumberController =
        TextEditingController(text: (vehicle['car_number'] ?? '').toString());
    String selectedVehicleType =
        (vehicle['vehicle_type'] as String?) ?? 'four_wheeler';
    String selectedBrand =
        (vehicle['car_brand'] as String?) ?? brandsByType[selectedVehicleType]!.first;
    final carModelFocus = FocusNode();
    final carNumberFocus = FocusNode();
    bool saving = false;
    bool success = false;
    String? errorText;
    bool carModelError = false;
    bool carNumberError = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Bounds the sheet so the Column below can give its fields area a
      // Flexible/scrollable region while pinning the Save button in a
      // fixed footer that's never pushed off-screen by the keyboard (see
      // the comment on the outer Padding further down).
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final isTwoWheeler = selectedVehicleType == 'two_wheeler';

          final fields = <Widget>[
            _sheetPickerField(
              label: vehicleTypeLabels[selectedVehicleType]!,
              onTap: () async {
                final picked = await _showPickerSheet(
                  title: 'Vehicle Type',
                  options: vehicleTypeLabels.entries
                      .map((e) => MapEntry(e.key, e.value))
                      .toList(),
                  selectedKey: selectedVehicleType,
                );
                if (picked != null) {
                  setSheetState(() {
                    selectedVehicleType = picked;
                    if (!brandsByType[selectedVehicleType]!.contains(selectedBrand)) {
                      selectedBrand = brandsByType[selectedVehicleType]!.first;
                    }
                  });
                }
              },
            ),
            _sheetPickerField(
              label: selectedBrand,
              onTap: () async {
                final picked = await _showPickerSheet(
                  title: 'Brand',
                  options: brandsByType[selectedVehicleType]!
                      .map((b) => MapEntry(b, b))
                      .toList(),
                  selectedKey: selectedBrand,
                );
                if (picked != null) {
                  setSheetState(() => selectedBrand = picked);
                }
              },
            ),
            _sheetField(
              carModelController,
              isTwoWheeler ? 'Two Wheeler Model' : 'Car Model',
              isTwoWheeler ? Icons.two_wheeler_outlined : Icons.directions_car_outlined,
              focusNode: carModelFocus,
              hasError: carModelError,
              onChanged: (_) {
                if (carModelError) setSheetState(() => carModelError = false);
              },
            ),
            _sheetField(
              carNumberController,
              isTwoWheeler ? 'Two Wheeler Number' : 'Car Number',
              Icons.badge_outlined,
              focusNode: carNumberFocus,
              hasError: carNumberError,
              onChanged: (_) {
                if (carNumberError) setSheetState(() => carNumberError = false);
              },
            ),
          ];

          final saveButton = GestureDetector(
            onTap: saving ? null : () async {
              final modelEmpty = carModelController.text.trim().isEmpty;
              final numberEmpty = carNumberController.text.trim().isEmpty;

              if (modelEmpty || numberEmpty) {
                setSheetState(() {
                  carModelError = modelEmpty;
                  carNumberError = numberEmpty;
                });
                if (modelEmpty) {
                  carModelFocus.requestFocus();
                } else {
                  carNumberFocus.requestFocus();
                }
                return;
              }

              setSheetState(() {
                saving = true;
                errorText = null;
              });

              try {
                await Supabase.instance.client.from('vehicles').update({
                  'vehicle_type': selectedVehicleType,
                  'car_brand': selectedBrand,
                  'car_model': carModelController.text.trim(),
                  'car_number': carNumberController.text.trim(),
                }).eq('id', vehicle['id']);

                setSheetState(() {
                  saving = false;
                  success = true;
                });

                // Let the checkmark register before the sheet closes.
                await Future.delayed(const Duration(milliseconds: 550));

                if (!mounted) return;
                Navigator.pop(ctx);
                await fetchVehicles();
                vehicleChangeBus.notifyVehicleUpdated();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Vehicle updated successfully!',
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
                final errorMessage = ErrorHandler.getUserMessage(e);
                setSheetState(() {
                  saving = false;
                  errorText = errorMessage;
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: success
                    ? Colors.green.shade600
                    : (saving ? _highlightYellow.withOpacity(0.6) : _highlightYellow),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: success
                      ? const Icon(Icons.check_rounded, key: ValueKey('check'), color: Colors.white, size: 28)
                      : saving
                          ? SizedBox(
                              key: const ValueKey('spinner'),
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: AppColors.onAccentDark, strokeWidth: 2.5),
                            )
                          : Text(
                              'SAVE CHANGES',
                              key: const ValueKey('label'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onAccentDark),
                            ),
                ),
              ),
            ),
          );

          // The keyboard shrinks the sheet's available height from the
          // bottom, not the top — pushing this whole Padding up by
          // viewInsets.bottom (rather than padding *inside* a scroll view)
          // keeps the fixed footer glued just above the keyboard instead
          // of being carried off past the bottom of the visible area.
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 44, height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.edit_rounded, color: Colors.blue.shade600, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Edit Vehicle',
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.txt),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          for (int i = 0; i < fields.length; i++) ...[
                            _StaggerFadeIn(index: i, child: fields[i]),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: Column(
                      children: [
                        // Shown right inside the sheet — a SnackBar tied to
                        // the page underneath would render behind this
                        // still-open modal and never actually be seen.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: errorText == null
                              ? const SizedBox.shrink(key: ValueKey('no-error'))
                              : Padding(
                                  key: const ValueKey('error'),
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.red.withOpacity(0.35)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            errorText ?? '',
                                            style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        saveButton,
                      ],
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

  /// Styled to match [_sheetField] so it reads as the same kind of form
  /// row, but tappable instead of a text field — opens [_showPickerSheet]
  /// instead of a DropdownButton menu (see the comment where this is used
  /// for why).
  Widget _sheetPickerField({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: AppColors.txt)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.txt),
          ],
        ),
      ),
    );
  }

  /// A plain bottom sheet listing [options] (key, display label) with the
  /// current [selectedKey] checked — returns the picked key, or null if
  /// dismissed without choosing. Used in place of DropdownButton for the
  /// Add Vehicle sheet's pickers.
  Future<String?> _showPickerSheet({
    required String title,
    required List<MapEntry<String, String>> options,
    required String selectedKey,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // Brand lists run to 20 entries — without a height cap the sheet just
      // kept growing past the screen and overflowed instead of scrolling.
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44, height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.txt),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: options.map((opt) => ListTile(
                          title: Text(opt.value, style: TextStyle(color: AppColors.txt)),
                          trailing: opt.key == selectedKey
                              ? const Icon(Icons.check_rounded, color: _highlightYellow)
                              : null,
                          onTap: () => Navigator.pop(ctx, opt.key),
                        )).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    FocusNode? focusNode,
    bool hasError = false,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasError ? Colors.red.shade400 : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: ctrl,
            focusNode: focusNode,
            onChanged: onChanged,
            style: TextStyle(color: AppColors.txt),
            decoration: InputDecoration(
              icon: Icon(icon, size: 22, color: hasError ? Colors.red.shade400 : AppColors.mut),
              hintText: hint,
              hintStyle: TextStyle(color: AppColors.mut),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 18, top: 6),
            child: Text(
              'Please fill this field',
              style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
      ],
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
      backgroundColor: AppColors.ink,
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
                      Semantics(
                        button: true,
                        label: 'Back',
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.07),
                                  blurRadius: 12, offset: const Offset(4, 4),
                                ),
                              ],
                            ),
                            child: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.txt),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text('My Garage',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.txt)),
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
                                      size: 80, color: AppColors.mut),
                                  const SizedBox(height: 16),
                                  Text('No vehicles yet',
                                    style: TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w700,
                                      color: AppColors.mut,
                                    )),
                                  const SizedBox(height: 8),
                                  Text('Tap the button below to add your first car',
                                    style: TextStyle(color: AppColors.mut)),
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
                                      color: AppColors.surfaceRaised,
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
                                            color: _highlightYellow,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Center(
                                            child: Text('${i + 1}',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                                color: AppColors.onAccentDark,
                                              )),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Car photo (or icon placeholder)
                                        Container(
                                          width: 56, height: 56,
                                          decoration: BoxDecoration(
                                            color: _highlightYellow.withOpacity(0.15),
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
                                                    color: AppColors.mut,
                                                  ),
                                                )
                                              : Icon(
                                                  v['vehicle_type'] == 'two_wheeler'
                                                      ? Icons.two_wheeler_rounded
                                                      : Icons.directions_car_rounded,
                                                  size: 30,
                                                  color: AppColors.mut,
                                                ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text((v['car_model'] ?? '').toString().toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.txt)),
                                              const SizedBox(height: 4),
                                              Text((v['car_brand'] ?? '').toString().toUpperCase(),
                                                style: TextStyle(
                                                  color: AppColors.mut, fontSize: 14)),
                                              const SizedBox(height: 2),
                                              Text((v['car_number'] ?? '').toString().toUpperCase(),
                                                style: TextStyle(
                                                  color: AppColors.mut, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        // Edit / delete — stacked so both
                                        // fit without widening the tile.
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => _editVehicleSheet(v),
                                                borderRadius: BorderRadius.circular(10),
                                                child: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Icon(
                                                    Icons.edit_outlined,
                                                    color: Colors.blue.shade600,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
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
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ],
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
                        color: _highlightYellow,
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
                        children: [
                          Icon(Icons.add_rounded, size: 28, color: AppColors.onAccentDark),
                          const SizedBox(width: 10),
                          Text('ADD VEHICLE',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.onAccentDark)),
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
      bottomNavigationBar: BottomNavBar(
        currentIndex: 4,
        onSelect: (i) => handleBottomNavSelect(
          context,
          i,
          currentIndex: 4,
          activeVehicle: vehicles.isNotEmpty ? vehicles.first : null,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AskAiButton(
        onTap: () => openAiAdvisor(
          context,
          vehicles.isNotEmpty ? vehicles.first : null,
        ),
      ),
    );
  }
}

/// Fades + rises a field into place. Each successive [index] takes slightly
/// longer to finish, so a column of these started at once reads as a gentle
/// top-to-bottom cascade rather than everything popping in together.
class _StaggerFadeIn extends StatelessWidget {
  const _StaggerFadeIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: child,
        ),
      ),
      child: child,
    );
  }
}