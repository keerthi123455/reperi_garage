import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/emergency_status_banner.dart';
import '../widgets/error_display.dart';
import '../widgets/requirements.dart';

// Brand highlight yellow — a fixed accent, not a themed surface, used for
// the badges/CTAs on this screen.
const Color _highlightYellow = Color(0xFFFFD600);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.autoOpenAddVehicle = false,
    this.returnAddedVehicle = false,
  });

  /// When true, opens the "Add Vehicle" sheet as soon as this screen
  /// appears — used by the home screen's "+" tile at the end of the
  /// vehicle carousel, which should land straight in that flow instead of
  /// just the profile screen.
  final bool autoOpenAddVehicle;

  /// When true (opened from PaymentScreen's "ADD A VEHICLE" prompt), this
  /// screen closes itself right after a vehicle is added and returns the
  /// new vehicle's id, so the customer lands back on checkout.
  final bool returnAddedVehicle;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> vehicles = [];
  bool loading = true;
  bool _deletingAccount = false;

  /// The customer's profile row (name, email, phone, active vehicle).
  Map<String, dynamic>? _profile;

  String get _activeVehicleId => (_profile?['active_vehicle_id'] ?? '').toString();
  String get _profileName => (_profile?['name'] ?? '').toString().trim();

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
    if (user == null) {
      // Guest — nothing to load; show the empty "add your first car" state.
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      final response = await supabase
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);
      Map<String, dynamic>? profile;
      try {
        profile = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        vehicles = List<Map<String, dynamic>>.from(response);
        _profile = profile;
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
  // claim, or subscription is still in progress for this
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
      table: 'claim_table',
      statusColumn: 'claim_status',
      isActive: (s) => s != 'approved' && s != 'rejected',
    )) {
      return true;
    }

    // Wash plans have no cancel option in this app — a vehicle enrolled
    // in one is always "in use" until the plan itself ends, so its mere
    // existence blocks deletion.
    try {
      final subscriptionRows = await supabase
          .from('monthlywash_table')
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

  /// Guests sign up first (in place), then the add-car sheet opens.
  Future<void> openAddVehicleSheet() async {
    if (!await ensureReady(context, account: true)) return;
    if (!mounted) return;
    fetchVehicles();
    _openAddVehicleSheetNow();
  }

  void _openAddVehicleSheetNow() {
    // Name is asked only the first time — after that it's already saved.
    final needName = _profileName.isEmpty;
    final nameController = TextEditingController(text: _profileName);
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
            if (needName)
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
            // Car / Bike — one tap, no extra sheet.
            _typeToggle(
              selected: selectedVehicleType,
              onChanged: (t) => setSheetState(() {
                selectedVehicleType = t;
                selectedBrand = brandsByType[selectedVehicleType]!.first;
              }),
            ),
            // Brand — tap a chip directly.
            _brandChips(
              brands: brandsByType[selectedVehicleType]!,
              selected: selectedBrand,
              onPick: (b) => setSheetState(() => selectedBrand = b),
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
              allCaps: true,
              hasError: carNumberError,
              onChanged: (_) {
                if (carNumberError) setSheetState(() => carNumberError = false);
              },
            ),
          ];

          final saveButton = GestureDetector(
            onTap: saving ? null : () async {
              final nameEmpty = needName && nameController.text.trim().isEmpty;
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
                  'car_number': carNumberController.text.trim().toUpperCase(),
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

                if (ctx.mounted) setSheetState(() {
                  saving = false;
                  success = true;
                });

                // Let the checkmark register before the sheet closes.
                await Future.delayed(const Duration(milliseconds: 550));

                if (!mounted) return;
                // The sheet may have been swiped away during the save — popping
                // with its dead context would close this screen instead.
                if (ctx.mounted) Navigator.pop(ctx);
                await fetchVehicles();
                vehicleChangeBus.notifyVehicleUpdated();

                if (!mounted) return;
                if (widget.returnAddedVehicle) {
                  // Back to checkout with the new vehicle.
                  Navigator.pop(context, inserted['id']?.toString());
                  return;
                }
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
                if (ctx.mounted) setSheetState(() {
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
                          const SizedBox(height: 4),
                          Text(
                            'Takes about 20 seconds',
                            style: TextStyle(fontSize: 14, color: AppColors.mut),
                          ),
                          const SizedBox(height: 22),
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
    // Falls back to 'four_wheeler' for any value that isn't one of
    // brandsByType's own two keys too (not just null) — this column has no
    // DB-side enum/CHECK constraint, so a stray value from elsewhere would
    // otherwise null-check-crash every `brandsByType[selectedVehicleType]!`
    // below the moment this sheet opens.
    final rawVehicleType = (vehicle['vehicle_type'] as String?) ?? 'four_wheeler';
    String selectedVehicleType =
        brandsByType.containsKey(rawVehicleType) ? rawVehicleType : 'four_wheeler';
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
                if (picked != null && ctx.mounted) {
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
                if (picked != null && ctx.mounted) {
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
              allCaps: true,
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
                  'car_number': carNumberController.text.trim().toUpperCase(),
                }).eq('id', vehicle['id']);

                if (ctx.mounted) setSheetState(() {
                  saving = false;
                  success = true;
                });

                // Let the checkmark register before the sheet closes.
                await Future.delayed(const Duration(milliseconds: 550));

                if (!mounted) return;
                // The sheet may have been swiped away during the save — popping
                // with its dead context would close this screen instead.
                if (ctx.mounted) Navigator.pop(ctx);
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
                if (ctx.mounted) setSheetState(() {
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
  /// Car / Bike as two big tappable cards.
  Widget _typeToggle({required String selected, required ValueChanged<String> onChanged}) {
    Widget card(String key, IconData icon, String label) {
      final on = selected == key;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: 86,
            decoration: BoxDecoration(
              color: on ? AppColors.accent.withOpacity(0.14) : AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? AppColors.accent : AppColors.line, width: on ? 2 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: on ? 1.12 : 1,
                  duration: const Duration(milliseconds: 240),
                  child: Icon(icon, size: 32, color: on ? AppColors.accent : AppColors.mut),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: on ? AppColors.txt : AppColors.mut)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card('four_wheeler', Icons.directions_car_rounded, 'Car'),
        const SizedBox(width: 12),
        card('two_wheeler', Icons.two_wheeler_rounded, 'Bike / Scooter'),
      ],
    );
  }

  /// Brand as chips — one tap instead of opening a list.
  Widget _brandChips({
    required List<String> brands,
    required String selected,
    required ValueChanged<String> onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('Brand', style: TextStyle(color: AppColors.mut, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in brands)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPick(b);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: b == selected ? AppColors.accent : AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: b == selected ? AppColors.accent : AppColors.line),
                  ),
                  child: Text(
                    b,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: b == selected ? AppColors.onAccentDark : AppColors.txt,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

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
    bool allCaps = false,
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
            // Vehicle numbers: keyboard opens in caps, and anything typed
            // or pasted in lowercase is turned into capitals as it's entered.
            textCapitalization:
                allCaps ? TextCapitalization.characters : TextCapitalization.none,
            inputFormatters: allCaps ? [_UpperCaseTextFormatter()] : null,
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

  /// Edit your name in one small sheet.
  Future<void> _editName() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      openAddVehicleSheet(); // guests: sign up first
      return;
    }
    final ctrl = TextEditingController(text: _profileName);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Your name', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.txt)),
                const SizedBox(height: 16),
                _sheetField(ctrl, 'Your Name', Icons.person_outline),
                const SizedBox(height: 18),
                SizedBox(
                  height: 58,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _highlightYellow,
                      foregroundColor: AppColors.onAccentDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('SAVE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (saved != true || name.isEmpty || name == _profileName) return;
    try {
      await Supabase.instance.client.from('profiles').update({'name': name}).eq('id', user.id);
      if (!mounted) return;
      setState(() => _profile = {...?_profile, 'name': name});
      HapticFeedback.lightImpact();
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showErrorSnackBar(context, message: ErrorHandler.getUserMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: EmergencyBannerOverlay(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: RefreshIndicator(
                color: AppColors.accent,
                onRefresh: fetchVehicles,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 120 + bottomPad),
                  children: [
                    // ── Header ──
                    _Entrance(
                      index: 0,
                      child: Row(
                        children: [
                          _RoundIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            semantics: 'Back',
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('My Garage',
                                  maxLines: 1,
                                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.txt)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ── You ──
                    _Entrance(index: 1, child: _profileCard(user)),
                    const SizedBox(height: 28),

                    // ── Vehicles ──
                    _Entrance(
                      index: 2,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Your vehicles',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.txt)),
                          ),
                          if (vehicles.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${vehicles.length}',
                                  style: const TextStyle(
                                      color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w900)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _Entrance(
                      index: 2,
                      child: Text(
                        vehicles.length > 1 ? 'Tap a vehicle to make it your active one' : 'Your saved cars and bikes',
                        style: TextStyle(fontSize: 14.5, color: AppColors.mut),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                      )
                    else ...[
                      for (var i = 0; i < vehicles.length; i++)
                        _Entrance(
                          index: 3 + i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _vehicleCard(vehicles[i]),
                          ),
                        ),
                      _Entrance(index: 3 + vehicles.length, child: _addVehicleCard()),
                    ],

                    const SizedBox(height: 34),

                    // ── Account settings (theme, delete account) — tucked away ──
                    _Entrance(
                      index: 5 + vehicles.length,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: _settingRow(
                          icon: Icons.settings_rounded,
                          label: _deletingAccount ? 'Deleting account…' : 'Account settings',
                          trailing: _deletingAccount
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red.shade400),
                                )
                              : Icon(Icons.chevron_right_rounded, color: AppColors.mut),
                          onTap: _openAccountSettings,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

  /// Theme switch + (small, at the bottom) delete account.
  void _openAccountSettings() {
    HapticFeedback.selectionClick();
    final signedIn = Supabase.instance.client.auth.currentUser != null;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Account settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.txt)),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _settingRow(
                    icon: AppColors.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    label: AppColors.isDark ? 'Dark mode' : 'Light mode',
                    trailing: Switch.adaptive(
                      value: AppColors.isDark,
                      activeColor: AppColors.accent,
                      onChanged: (_) {
                        HapticFeedback.selectionClick();
                        themeController.toggle();
                        setSheet(() {});
                      },
                    ),
                    onTap: () {
                      themeController.toggle();
                      setSheet(() {});
                    },
                  ),
                ),
                if (signedIn) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: _deletingAccount
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _confirmDeleteAccount();
                            },
                      child: Text(
                        'Delete account',
                        style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────────

  Widget _profileCard(User? user) {
    final name = _profileName.isNotEmpty ? _profileName : (user == null ? 'Guest' : 'Add your name');
    final email = (user?.email ?? _profile?['email'] ?? '').toString();
    final phone = (_profile?['phone'] ?? user?.phone ?? '').toString();
    final initials = _profileName.isEmpty
        ? (user == null ? '?' : (email.isNotEmpty ? email[0].toUpperCase() : '?'))
        : _profileName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: _editName,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent.withOpacity(0.22), AppColors.surfaceRaised],
            ),
            border: Border.all(color: AppColors.accent.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [Color(0xFFF5C842), Color(0xFFD4A017)]),
                  boxShadow: [BoxShadow(color: Color(0x55D4A017), blurRadius: 16, offset: Offset(0, 6))],
                ),
                alignment: Alignment.center,
                child: Text(initials,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.onAccentDark)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.txt, height: 1.15)),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, color: AppColors.mut)),
                    ],
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(phone, style: TextStyle(fontSize: 14.5, color: AppColors.mut)),
                    ],
                    if (user == null) ...[
                      const SizedBox(height: 4),
                      Text('Tap to sign up', style: TextStyle(fontSize: 14.5, color: AppColors.accent, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_rounded, color: AppColors.accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vehicleCard(Map<String, dynamic> v) {
    final isBike = v['vehicle_type'] == 'two_wheeler';
    final active = _activeVehicleId.isNotEmpty
        ? '${v['id']}' == _activeVehicleId
        : identical(v, vehicles.first);
    final photo = (v['photo_url'] as String?) ?? '';
    final number = (v['car_number'] ?? '').toString().toUpperCase();

    return _PressScale(
      onTap: () {
        HapticFeedback.mediumImpact();
        setActiveVehicle(v);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: active ? AppColors.accent : AppColors.line, width: active ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: active ? AppColors.accent.withOpacity(0.18) : Colors.black.withOpacity(0.12),
              blurRadius: active ? 24 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photo.isNotEmpty
                      ? Image.network(photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                              isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
                              size: 36,
                              color: AppColors.accent))
                      : Icon(isBike ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
                          size: 36, color: AppColors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (active)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                          child: Text('ACTIVE',
                              style: TextStyle(
                                  color: AppColors.onAccentDark,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8)),
                        ),
                      Text((v['car_model'] ?? '').toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.txt, height: 1.15)),
                      const SizedBox(height: 3),
                      Text((v['car_brand'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, color: AppColors.mut, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (number.isNotEmpty)
                  Flexible(child: _PlateText(number))
                else
                  const Spacer(),
                const SizedBox(width: 10),
                if (number.isNotEmpty) const Spacer(),
                _RoundIconButton(
                  icon: Icons.edit_rounded,
                  semantics: 'Edit vehicle',
                  color: const Color(0xFF4D8DFF),
                  onTap: () => _editVehicleSheet(v),
                ),
                const SizedBox(width: 10),
                _RoundIconButton(
                  icon: Icons.delete_outline_rounded,
                  semantics: 'Delete vehicle',
                  color: Colors.red.shade400,
                  onTap: () => _confirmDeleteVehicle(v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _addVehicleCard() {
    return _PressScale(
      onTap: () {
        HapticFeedback.mediumImpact();
        openAddVehicleSheet();
      },
      child: CustomPaint(
        painter: _DashedBorderPainter(color: AppColors.accent.withOpacity(0.7), radius: 26),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              const _PulsingPlus(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicles.isEmpty ? 'Add your first vehicle' : 'Add another vehicle',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.txt)),
                    const SizedBox(height: 3),
                    Text('Car or bike · takes about 20 seconds',
                        style: TextStyle(fontSize: 14.5, color: AppColors.mut)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    VoidCallback? onTap,
    Color? color,
  }) {
    final c = color ?? AppColors.txt;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c)),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

// ── Small building blocks ─────────────────────────────────────────────────

/// Slides + fades each section in, one after another, when the screen opens.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + 70 * index.clamp(0, 8)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: child),
      ),
      child: child,
    );
  }
}

/// Shrinks a little while pressed — makes cards feel tappable.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, required this.semantics, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final String semantics;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.txt;
    return Semantics(
      button: true,
      label: semantics,
      child: Material(
        color: color == null ? AppColors.surfaceRaised : c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 22, color: c)),
        ),
      ),
    );
  }
}

/// Number plate look: white plate, dark border, bold spaced letters.
class _PlateText extends StatelessWidget {
  const _PlateText(this.number);
  final String number;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF111111), width: 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          number,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// Gold "+" that gently breathes, inviting the tap.
class _PulsingPlus extends StatefulWidget {
  const _PulsingPlus();

  @override
  State<_PulsingPlus> createState() => _PulsingPlusState();
}

class _PulsingPlusState extends State<_PulsingPlus> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = reduce ? 0.0 : Curves.easeInOut.transform(_c.value);
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
            boxShadow: [
              BoxShadow(color: AppColors.accent.withOpacity(0.25 + 0.25 * t), blurRadius: 10 + 12 * t, spreadRadius: 1 + 3 * t),
            ],
          ),
          child: Icon(Icons.add_rounded, size: 32, color: AppColors.onAccentDark),
        );
      },
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color || old.radius != radius;
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

/// Forces everything typed or pasted into a field to capitals, keeping the
/// cursor where it was — used for vehicle numbers (e.g. KA01AB1234).
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
