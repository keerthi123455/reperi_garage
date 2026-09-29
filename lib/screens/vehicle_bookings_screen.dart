import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/error_handler.dart';
import '../services/vehicle_change_bus.dart';
import '../services/vehicle_update_tracker.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/bottom_nav_actions.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/emergency_status_banner.dart';
import '../widgets/error_display.dart';
import 'booking_tracking_screen.dart';

// Same brand catalog as profile_screen.dart's "Add/Edit Vehicle" sheet —
// duplicated here (rather than imported) because it's just plain data with
// no shared owner, and this screen's edit sheet needs it too.
const Map<String, List<String>> _kBrandsByType = {
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

const Map<String, String> _kVehicleTypeLabels = {
  'four_wheeler': 'Four Wheeler',
  'two_wheeler': 'Two Wheeler',
};

class VehicleBookingsScreen extends StatefulWidget {
  final String vehicleId;
  final String carModel;
  final String carBrand;
  final String carNumber;

  /// Set only right after a fresh booking to scroll straight to it once
  /// this screen loads — 'bookings' | 'pollution' | 'inspection' | 'claim'
  /// | 'subscription'. The newest row of that section (index 0, since
  /// every list here is fetched newest-first) is the one scrolled to.
  /// Null for a normal visit to this screen (no scroll, no highlight).
  final String? highlightSection;

  const VehicleBookingsScreen({
    super.key,
    required this.vehicleId,
    required this.carModel,
    required this.carBrand,
    required this.carNumber,
    this.highlightSection,
  });

  @override
  State<VehicleBookingsScreen> createState() =>
      _VehicleBookingsScreenState();
}

class _VehicleBookingsScreenState extends State<VehicleBookingsScreen> {
  // Editable copies of the vehicle's display fields — widget.carModel etc.
  // are fixed constructor params from whoever navigated here, so an edit
  // made via the pencil icon below updates these local copies (and the DB)
  // rather than the immutable widget fields.
  late String _carModel = widget.carModel;
  late String _carBrand = widget.carBrand;
  late String _carNumber = widget.carNumber;

  List bookings = [];
  Set<String> unreadBookingIds = {};
  List claimUpdates = [];
  List claims = [];
  List washHistory = [];
  List pollutionBookings = [];
  List inspectionBookings = [];
  bool loading = true;
  // Set when fetchBookings() itself fails (not the secondary fetches below
  // it, which already degrade silently) — drives a retry screen instead of
  // leaving the loading spinner stuck forever.
  bool _loadError = false;
  bool _claimsExpanded = false;
  bool _subscriptionExpanded = false;
  Map subscription = {};

  // ── Scroll-to-new-booking ────────────────────────────────────────────
  // Set by PaymentScreen right after a successful booking so the customer
  // lands here already scrolled to the package they just paid for, instead
  // of having to hunt for it. Only ever fires once per screen visit — after
  // that the key stays attached (harmless) but _didScrollToHighlight blocks
  // a second jump on every 15s auto-refresh.
  final GlobalKey _highlightKey = GlobalKey();
  bool _didScrollToHighlight = false;

  void _maybeScrollToHighlight(String section) {
    if (_didScrollToHighlight || widget.highlightSection != section) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didScrollToHighlight) return;
      final ctx = _highlightKey.currentContext;
      // FIX: claims/pollution/inspection/subscription usually finish loading
      // BEFORE fetchBookings turns the page's loading spinner off — the card
      // isn't on screen yet at that point, so there's nothing to scroll to.
      // This used to mark the scroll as done anyway and never try again.
      // Now it only counts as done once it actually scrolls; fetchBookings
      // retries it the moment the spinner goes away (see
      // _retryHighlightAfterLoad).
      if (ctx == null) return;
      _didScrollToHighlight = true;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    });
  }

  /// The page's list only appears once `loading` turns false — if the
  /// highlighted section's own data arrived before that, its scroll found
  /// nothing on screen. Try again now that the list is actually built.
  void _retryHighlightAfterLoad() {
    final section = widget.highlightSection;
    if (section != null) _maybeScrollToHighlight(section);
  }

  // ── "NEW SERVICE UPDATE" badge, per booking ─────────────────────────
  // booking_status has no server-side "read" flag (unlike the admin chat's
  // is_read_by_consumer), so whether a booking's current status counts as
  // "new" is tracked locally: the last status the customer actually opened
  // this booking's tracking screen at, keyed by booking id. Loaded once
  // after each fetchBookings() so the tile list below can check it
  // synchronously, and updated the moment a tile is tapped.
  Map<String, String> _seenBookingStatuses = {};
  static const _seenStatusPrefix = 'booking_status_seen_';

  Future<void> _loadSeenBookingStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String, String>{};
    for (final b in bookings) {
      final id = b['id'].toString();
      final value = prefs.getString('$_seenStatusPrefix$id');
      if (value != null) seen[id] = value;
    }
    if (mounted) setState(() => _seenBookingStatuses = seen);
  }

  Future<void> _markBookingStatusSeen(String bookingId, String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_seenStatusPrefix$bookingId', status);
    if (mounted) setState(() => _seenBookingStatuses[bookingId] = status);
  }

  // ── Cancel window ──────────────────────────────────────────────────
  // Services, pollution, and inspection bookings can all
  // be cancelled for _cancelWindow after they're placed — cancelling
  // deletes the record outright (see _showCancelFlow) rather than just
  // flagging it, so there's no "already cancelled" state to check for
  // here; once gone, it simply stops appearing in these lists.
  // Subscriptions and claims deliberately have no cancel option at all —
  // see _anyCancellable and the claim card, which never call
  // _isCancellable/_buildCancelWindow.
  static const Duration _cancelWindow = Duration(minutes: 2);
  Timer? _cancelTicker;

  // ── Auto-refresh ─────────────────────────────────────────────────────
  // The delivery-stage tracker, OTP boxes, and "Ready for Pickup"/cash
  // reminders above all depend on live delivery_stage/booking_status/
  // return_otp_verified_at columns, but nothing pushes those changes into
  // this screen on its own — Supabase Realtime isn't wired up here, so a
  // push notification landing while this screen is already open wouldn't
  // otherwise be reflected until the customer manually backed out and
  // back in. Polling every 15s picks those up without needing Realtime.
  Timer? _autoRefreshTimer;

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      fetchBookings();
      fetchPollutionBookings();
      fetchInspectionBookings();
      fetchClaims();
    });
  }

  bool _isCancellable(Map record) {
    final createdAt = DateTime.tryParse((record['created_at'] ?? '').toString());
    if (createdAt == null) return false;
    return DateTime.now().toUtc().difference(createdAt.toUtc()) < _cancelWindow;
  }

  Duration _cancelTimeRemaining(Map record) {
    final createdAt = DateTime.parse(record['created_at'].toString());
    final elapsed = DateTime.now().toUtc().difference(createdAt.toUtc());
    final remaining = _cancelWindow - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _anyCancellable =>
      bookings.any((b) => _isCancellable(b)) ||
      pollutionBookings.any((b) => _isCancellable(b)) ||
      inspectionBookings.any((b) => _isCancellable(b));

  void _syncCancelTicker() {
    if (_anyCancellable && _cancelTicker == null) {
      _cancelTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (!_anyCancellable) {
          _cancelTicker?.cancel();
          _cancelTicker = null;
        }
        setState(() {});
      });
    } else if (!_anyCancellable) {
      _cancelTicker?.cancel();
      _cancelTicker = null;
    }
  }

  @override
  void initState() {
    super.initState();
    fetchBookings();
    fetchClaimUpdates();
    fetchClaims();
    fetchSubscription();
    fetchWashHistory();
    fetchPollutionBookings();
    fetchInspectionBookings();
    // Landing here IS "viewing" every update source shown below — snapshot
    // them all as seen so the home-screen bell for this vehicle clears.
    // Re-derives straight from Supabase rather than waiting on the fetches
    // above, so it isn't blocked by (or racing) their own completion.
    VehicleUpdateTracker.markSeen(widget.vehicleId);
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
    // Fired whenever this vehicle is edited from elsewhere (e.g. My Garage)
    // — re-pulls just this vehicle's row so the header above reflects the
    // change immediately too.
    vehicleChangeBus.addListener(_refreshVehicleInfo);
    _startAutoRefresh();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshVehicleInfo() async {
    try {
      final response = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('id', widget.vehicleId)
          .single();
      if (!mounted) return;
      setState(() {
        _carModel = (response['car_model'] ?? _carModel).toString();
        _carBrand = (response['car_brand'] ?? _carBrand).toString();
        _carNumber = (response['car_number'] ?? _carNumber).toString();
      });
    } catch (e) {
      debugPrint('Error refreshing vehicle info: $e');
    }
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    vehicleChangeBus.removeListener(_refreshVehicleInfo);
    _cancelTicker?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // ── Delete vehicle (bin icon on the header above) ───────────────────
  // Mirrors profile_screen.dart's delete flow — same block-check across
  // bookings/pollution/inspection/claims/subscriptions, same "Vehicle has
  // active service" dialog copy and "I UNDERSTAND" button.
  Future<bool> _checkActiveService(String vehicleId) async {
    final supabase = Supabase.instance.client;

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
    // "done" in its own right — _ReturnOtpVerification._verify() flips
    // booking_status to 'Delivered' on the 'bookings' table the moment it
    // succeeds, but pollution_booking/inspection_booking only reach
    // delivery_stage == 'delivered' once the delivery partner separately
    // taps their own "Vehicle Delivered" button afterwards. Checking
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

    // Same shape as 'bookings' — claim_status is what MARK AS DONE
    // (claim_details_screen.dart) and the return OTP verify
    // above both drive, independent of delivery_stage.
    if (await latestRowIsActiveUnlessReturned(
      table: 'claim_table',
      statusColumn: 'claim_status',
    )) {
      return true;
    }

    if (await latestRowIsActive(
      table: 'claim_table',
      statusColumn: 'claim_status',
      isActive: (s) => s != 'approved' && s != 'rejected',
    )) {
      return true;
    }

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

  Future<void> _confirmDeleteVehicle() async {
    final hasActiveService = await _checkActiveService(widget.vehicleId);

    if (!mounted) return;

    if (hasActiveService) {
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
              '$_carBrand $_carModel',
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
      await _deleteVehicle();
    }
  }

  // Unlike profile_screen.dart (which stays put and refreshes its vehicle
  // list), this screen IS the deleted vehicle's own detail page — once
  // gone, there's nothing left here to show, so it pops back after
  // notifying the rest of the app the vehicle list changed.
  Future<void> _deleteVehicle() async {
    try {
      await Supabase.instance.client
          .from('vehicles')
          .delete()
          .eq('id', widget.vehicleId);

      vehicleChangeBus.notifyVehicleUpdated();

      if (!mounted) return;
      // Grab the messenger BEFORE popping — this screen's context is on
      // its way out once Navigator.pop runs.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Vehicle deleted successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
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

  // ── Edit vehicle (pencil icon on the header above) ──────────────────
  // Mirrors profile_screen.dart's edit sheet, but this screen isn't handed
  // vehicle_type by its constructor, so it fetches the current row fresh
  // right before showing the sheet rather than caching a possibly-stale
  // copy in state.
  Future<void> _editVehicleSheet() async {
    Map<String, dynamic> vehicle;
    try {
      final response = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('id', widget.vehicleId)
          .single();
      vehicle = Map<String, dynamic>.from(response);
    } catch (e) {
      vehicle = {
        'vehicle_type': 'four_wheeler',
        'car_brand': _carBrand,
        'car_model': _carModel,
        'car_number': _carNumber,
      };
    }

    if (!mounted) return;

    final carModelController =
        TextEditingController(text: (vehicle['car_model'] ?? _carModel).toString());
    final carNumberController =
        TextEditingController(text: (vehicle['car_number'] ?? _carNumber).toString());
    // Falls back to 'four_wheeler' for any value that isn't one of
    // _kBrandsByType's own two keys too (not just null) — this column has
    // no DB-side enum/CHECK constraint, so a stray value from elsewhere
    // would otherwise null-check-crash every `_kBrandsByType[...]!` below
    // the moment this sheet opens.
    final rawVehicleType = (vehicle['vehicle_type'] as String?) ?? 'four_wheeler';
    String selectedVehicleType =
        _kBrandsByType.containsKey(rawVehicleType) ? rawVehicleType : 'four_wheeler';
    String selectedBrand = (vehicle['car_brand'] as String?) ??
        _kBrandsByType[selectedVehicleType]!.first;
    final carModelFocus = FocusNode();
    final carNumberFocus = FocusNode();
    bool saving = false;
    bool success = false;
    String? errorText;
    bool carModelError = false;
    bool carNumberError = false;

    await showModalBottomSheet(
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
              label: _kVehicleTypeLabels[selectedVehicleType]!,
              onTap: () async {
                final picked = await _showPickerSheet(
                  title: 'Vehicle Type',
                  options: _kVehicleTypeLabels.entries
                      .map((e) => MapEntry(e.key, e.value))
                      .toList(),
                  selectedKey: selectedVehicleType,
                );
                if (picked != null && ctx.mounted) {
                  setSheetState(() {
                    selectedVehicleType = picked;
                    if (!_kBrandsByType[selectedVehicleType]!.contains(selectedBrand)) {
                      selectedBrand = _kBrandsByType[selectedVehicleType]!.first;
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
                  options: _kBrandsByType[selectedVehicleType]!
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
                }).eq('id', widget.vehicleId);

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
                setState(() {
                  _carModel = carModelController.text.trim();
                  _carBrand = selectedBrand;
                  _carNumber = carNumberController.text.trim().toUpperCase();
                });
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
                if (ctx.mounted) setSheetState(() {
                  saving = false;
                  errorText = 'Could not update vehicle: $e';
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
                    : const Color(0xFFD4A017).withOpacity(saving ? 0.6 : 1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: success
                      ? const Icon(Icons.check_rounded, key: ValueKey('check'), color: Colors.white, size: 28)
                      : saving
                          ? const SizedBox(
                              key: ValueKey('spinner'),
                              width: 24, height: 24,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                            )
                          : const Text(
                              'SAVE CHANGES',
                              key: ValueKey('label'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
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
                                  color: const Color(0xFFD4A017).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.edit_rounded, color: Color(0xFFD4A017), size: 20),
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
                            _VehicleEditFadeIn(index: i, child: fields[i]),
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
                              ? const Icon(Icons.check_rounded, color: Color(0xFFD4A017))
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

  Future<void> fetchSubscription() async {
    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('monthlywash_table')
          .select('*')
          .eq('vehicle_id', widget.vehicleId)
          .single();

      if (mounted) {
        setState(() {
          subscription = response;
        });
        if (subscription.isNotEmpty) _maybeScrollToHighlight('subscription');
      }
    } catch (e) {
      debugPrint('Error fetching subscription: $e');
    }
  }

  Future<void> fetchWashHistory() async {
    try {
      final supabase = Supabase.instance.client;

      final subResponse = await supabase
          .from('monthlywash_table')
          .select('id')
          .eq('vehicle_id', widget.vehicleId)
          .single();

      final subscriptionId = subResponse['id'];

      final response = await supabase
          .from('service_history')
          .select('*')
          .eq('subscription_id', subscriptionId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          washHistory = response as List;
        });
      }
    } catch (e) {
      debugPrint('Error fetching wash history: $e');
    }
  }

  Future<void> fetchClaimUpdates() async {
    try {
      final supabase = Supabase.instance.client;

      // Get all claims for this vehicle
      final claimsResponse = await supabase
          .from('claim_table')
          .select('id')
          .eq('vehicle_id', widget.vehicleId);

      if ((claimsResponse as List).isEmpty) {
        if (!mounted) return;
        setState(() => claimUpdates = []);
        return;
      }

      // Get all claim IDs
      final claimIds =
          (claimsResponse as List).map((c) => c['id']).toList();

      // Get all updates for these claims
      final updatesResponse = await supabase
          .from('claim_table_updates')
          .select('*')
          .inFilter('claim_id', claimIds)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        claimUpdates = updatesResponse;
      });
    } catch (e) {
      debugPrint('Error fetching claim updates: $e');
    }
  }

  /// The claims themselves, shown as their own cards (status + submitted
  /// date + cancel window) — separate from fetchClaimUpdates() above,
  /// which only pulls the update/comment feed for claims that already
  /// exist.
  Future<void> fetchClaims() async {
    try {
      final response = await Supabase.instance.client
          .from('claim_table')
          .select('*')
          .eq('vehicle_id', widget.vehicleId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => claims = response as List);
      _syncCancelTicker();
      if (claims.isNotEmpty) _maybeScrollToHighlight('claim');
    } catch (e) {
      debugPrint('Error fetching claims: $e');
    }
  }

  Future<void> fetchBookings() async {
    final supabase = Supabase.instance.client;

    try {
      // ── UPDATED QUERY: Now includes admin table data (garage name & address) ──
      final response = await supabase
          .from('bookings')
          .select('''
            *,
            admin:assigned_to_admin_id (
              username,
              address,
              latitude,
              longitude
            )
          ''')
          .eq('vehicle_id', widget.vehicleId)
          .order('created_at', ascending: false);

      // fetch all unread admin messages in one query
      final bookingIds =
          (response as List).map((b) => b['id'].toString()).toList();

      Set<String> unreadIds = {};

      if (bookingIds.isNotEmpty) {
        final unreadChats = await supabase
            .from('booking_chats')
            .select('booking_id')
            .inFilter('booking_id', bookingIds)
            .eq('sender', 'admin')
            .eq('is_read_by_consumer', false);

        unreadIds = (unreadChats as List)
            .map((c) => c['booking_id'].toString())
            .toSet();
      }

      if (!mounted) return;

      setState(() {
        bookings = response;
        unreadBookingIds = unreadIds;
        loading = false;
        _loadError = false;
      });
      _syncCancelTicker();
      if (bookings.isNotEmpty) _maybeScrollToHighlight('bookings');
      _retryHighlightAfterLoad();
      await _loadSeenBookingStatuses();
    } catch (e) {
      // Without this, a failed fetch (no network, RLS hiccup, timeout) left
      // `loading` stuck true forever — an unrecoverable spinner with no
      // way out but force-quitting the app.
      if (!mounted) return;
      setState(() {
        loading = false;
        _loadError = true;
      });
    }
  }

  /// Opens Google Maps directions to the assigned garage — shown only for
  /// Cash on Pickup bookings, since that's the one payment path where the
  /// customer (rather than a delivery partner) is the one actually going
  /// there in person.
  Future<void> _openGarageNavigation(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Opens the "why are you cancelling" dialog, then — only if the
  /// customer actually submits a reason — records the cancellation (with a
  /// snapshot of the title/price, since the source row is about to be
  /// deleted and can't be joined back later) and deletes the record
  /// outright from [table]. Tapping RETURN (or dismissing) leaves it
  /// untouched.
  Future<void> _showCancelFlow({
    required Map record,
    required String table,
    required String bookingType, // 'service' | 'pollution' | 'inspection' | 'claim'
    required String title,
    String? price,
  }) async {
    // The reason text field's controller is owned by _CancelReasonDialog's
    // own State, not created/disposed here — disposing it the instant
    // showDialog's Future resolves used to race the dialog's closing
    // animation (the TextField was still alive for that last frame),
    // throwing "TextEditingController used after being disposed" and
    // taking the whole screen down with it. Letting the dialog widget
    // dispose its own controller in its own dispose() means Flutter only
    // does that once the dialog element is actually gone.
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CancelReasonDialog(),
    );

    if (reason == null || reason.isEmpty) {
      return; // RETURN tapped or dialog dismissed — the booking is untouched.
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      // booking_cancellations.booking_type predates the Insurance Claim ->
      // Claim Assistance rename and almost certainly still only accepts
      // the original set of values (likely a fixed/enum column) — sending
      // the new 'claim' label here 400s the insert (confirmed via the
      // Supabase API logs). Map it back to the value that column already
      // recognizes; 'claim' is still used for every in-app routing
      // decision below (which fetch functions to re-run after cancelling).
      final dbBookingType = bookingType == 'claim' ? 'insurance' : bookingType;

      await supabase.from('booking_cancellations').insert({
        'booking_type': dbBookingType,
        'booking_id': record['id'],
        'user_id': user?.id,
        'vehicle_id': widget.vehicleId,
        'title': title,
        'price': price,
        'payment_status': record['payment_status'],
        'reason': reason,
      });

      await supabase.from(table).delete().eq('id', record['id']);

      if (!mounted) return;
      switch (bookingType) {
        case 'pollution':
          await fetchPollutionBookings();
          break;
        case 'inspection':
          await fetchInspectionBookings();
          break;
        case 'claim':
          await fetchClaims();
          await fetchClaimUpdates();
          break;
        default:
          await fetchBookings();
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 26),
                ),
                const SizedBox(height: 16),
                Text(
                  'Booking Cancelled',
                  style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  'If payment was done online, your amount will be returned to your bank account within 5 business days.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'OK',
                      style: TextStyle(color: AppColors.onAccentDark, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not cancel this booking. Please try again.',
      );
    }
  }

  /// The cancel countdown pill + CANCEL button shown on a booking card
  /// while it's still inside the cancel window.
  Widget _buildCancelWindow({
    required Map record,
    required String table,
    required String bookingType,
    required String title,
    String? price,
  }) {
    final remaining = _cancelTimeRemaining(record);
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    final timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.red, size: 15),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Can cancel in $timeStr',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _showCancelFlow(
              record: record,
              table: table,
              bookingType: bookingType,
              title: title,
              price: price,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> fetchPollutionBookings() async {
    try {
      final response = await Supabase.instance.client
          .from('pollution_booking')
          .select('*')
          .eq('vehicle_id', widget.vehicleId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => pollutionBookings = response as List);
      _syncCancelTicker();
      if (pollutionBookings.isNotEmpty) _maybeScrollToHighlight('pollution');
    } catch (e) {
      debugPrint('Error fetching pollution bookings: $e');
    }
  }

  Future<void> fetchInspectionBookings() async {
    try {
      final response = await Supabase.instance.client
          .from('inspection_booking')
          .select('*')
          .eq('vehicle_id', widget.vehicleId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => inspectionBookings = response as List);
      _syncCancelTicker();
      if (inspectionBookings.isNotEmpty) _maybeScrollToHighlight('inspection');
    } catch (e) {
      debugPrint('Error fetching inspection bookings: $e');
    }
  }

  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String formatDay(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[date.weekday - 1];
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceRaised,
        elevation: 0,
        title: Text(
          _carModel,
          style: const TextStyle(
            color: Color(0xFFD4A017),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: EmergencyBannerOverlay(
        child: loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFFD4A017)),
            )
          : _loadError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, color: AppColors.mut, size: 40),
                        const SizedBox(height: 16),
                        Text(
                          "Couldn't load this vehicle's bookings",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.mut, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => loading = true);
                            fetchBookings();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A017),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('RETRY',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ── VEHICLE HEADER ──
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.ink, AppColors.surfaceRaised],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'ACTIVE VEHICLE',
                                style: TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 11,
                                  letterSpacing: 2,
                                ),
                              ),
                              Row(
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _editVehicleSheet,
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD4A017).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.edit_outlined,
                                          color: Color(0xFFD4A017),
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _confirmDeleteVehicle,
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _carModel,
                            style: TextStyle(
                              color: AppColors.txt,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _carBrand,
                            style: TextStyle(color: AppColors.mut, fontSize: 16),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4A017)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFD4A017)
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              _carNumber,
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // This entire section only applies to THIS vehicle —
                    // `subscription` comes from fetchSubscription(), which
                    // queries `subscriptions` filtered to
                    // `vehicle_id = widget.vehicleId`, and stays `{}` when
                    // this vehicle has none. Previously this whole block
                    // rendered unconditionally with a hardcoded title/price
                    // fallback, making every vehicle look like it had an
                    // active subscription regardless of the actual data.
                    if (subscription.isNotEmpty) ...[
                    const SizedBox(height: 34),

                    const Text(
                      'Monthly Wash Plan',
                      style: TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── EXPANDABLE SUBSCRIPTION TILE ──
                    GestureDetector(
                      key: widget.highlightSection == 'subscription' ? _highlightKey : null,
                      onTap: () {
                        setState(() {
                          _subscriptionExpanded = !_subscriptionExpanded;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A017).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFD4A017).withOpacity(0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subscription['plan_title'] ??
                                            'Monthly Wash Plan',
                                        style: const TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '₹${subscription['price'] ?? '-'}/month',
                                            style: TextStyle(
                                              color: AppColors.txt,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD4A017),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Active',
                                              style: TextStyle(
                                                color: AppColors.onAccentDark,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _subscriptionExpanded ? Icons.expand_less : Icons.expand_more,
                                  color: const Color(0xFFD4A017),
                                  size: 28,
                                ),
                              ],
                            ),

                            // ── EXPANDED WASH HISTORY ──
                            if (_subscriptionExpanded) ...[
                              const SizedBox(height: 20),
                              const Divider(color: Color(0xFFD4A017)),
                              const SizedBox(height: 16),
                              const Text(
                                'Wash History',
                                style: TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (washHistory.isEmpty)
                                Text(
                                  'No washes yet',
                                  style: TextStyle(
                                    color: AppColors.mut,
                                    fontSize: 12,
                                  ),
                                )
                              else
                                ...washHistory.map((wash) {
                                  final dateStr = formatDate(wash['created_at'] ?? '');
                                  final dayStr = formatDay(wash['created_at'] ?? '');

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceSunken,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.line),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Date and Day
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  dateStr,
                                                  style: const TextStyle(
                                                    color: Color(0xFFD4A017),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  dayStr,
                                                  style: TextStyle(
                                                    color: AppColors.mut,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade900.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Completed',
                                                style: TextStyle(
                                                  color: Colors.green.shade400,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        // Before and After Photos
                                        if (wash['before_photo_url'] != null || wash['after_photo_url'] != null)
                                          Row(
                                            children: [
                                              if (wash['before_photo_url'] != null)
                                                Expanded(
                                                  child: Column(
                                                    children: [
                                                      GestureDetector(
                                                        onTap: () {
                                                          _showImageViewer(context, wash['before_photo_url'], 'Before Photo');
                                                        },
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(10),
                                                            border: Border.all(
                                                              color: AppColors.accent.withOpacity(0.35),
                                                              width: 1.2,
                                                            ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors.black.withOpacity(0.18),
                                                                blurRadius: 6,
                                                                offset: const Offset(0, 3),
                                                              ),
                                                            ],
                                                          ),
                                                          child: ClipRRect(
                                                            borderRadius: BorderRadius.circular(9),
                                                            child: Stack(
                                                              children: [
                                                                Image.network(
                                                                  wash['before_photo_url'],
                                                                  height: 70,
                                                                  width: double.infinity,
                                                                  fit: BoxFit.cover,
                                                                  errorBuilder: (_, __, ___) => Container(
                                                                    height: 70,
                                                                    color: AppColors.photoPlaceholder,
                                                                    child: Icon(Icons.image_not_supported, color: AppColors.mut),
                                                                  ),
                                                                ),
                                                                Positioned(
                                                                  right: 4,
                                                                  bottom: 4,
                                                                  child: Container(
                                                                    padding: const EdgeInsets.all(3),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.black.withOpacity(0.45),
                                                                      shape: BoxShape.circle,
                                                                    ),
                                                                    child: const Icon(
                                                                      Icons.zoom_in_rounded,
                                                                      color: Colors.white,
                                                                      size: 13,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Before',
                                                        style: TextStyle(
                                                          color: AppColors.mut,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              const SizedBox(width: 8),
                                              if (wash['after_photo_url'] != null)
                                                Expanded(
                                                  child: Column(
                                                    children: [
                                                      GestureDetector(
                                                        onTap: () {
                                                          _showImageViewer(context, wash['after_photo_url'], 'After Photo');
                                                        },
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(10),
                                                            border: Border.all(
                                                              color: AppColors.accent.withOpacity(0.35),
                                                              width: 1.2,
                                                            ),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: Colors.black.withOpacity(0.18),
                                                                blurRadius: 6,
                                                                offset: const Offset(0, 3),
                                                              ),
                                                            ],
                                                          ),
                                                          child: ClipRRect(
                                                            borderRadius: BorderRadius.circular(9),
                                                            child: Stack(
                                                              children: [
                                                                Image.network(
                                                                  wash['after_photo_url'],
                                                                  height: 70,
                                                                  width: double.infinity,
                                                                  fit: BoxFit.cover,
                                                                  errorBuilder: (_, __, ___) => Container(
                                                                    height: 70,
                                                                    color: AppColors.photoPlaceholder,
                                                                    child: Icon(Icons.image_not_supported, color: AppColors.mut),
                                                                  ),
                                                                ),
                                                                Positioned(
                                                                  right: 4,
                                                                  bottom: 4,
                                                                  child: Container(
                                                                    padding: const EdgeInsets.all(3),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.black.withOpacity(0.45),
                                                                      shape: BoxShape.circle,
                                                                    ),
                                                                    child: const Icon(
                                                                      Icons.zoom_in_rounded,
                                                                      color: Colors.white,
                                                                      size: 13,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'After',
                                                        style: TextStyle(
                                                          color: AppColors.mut,
                                                          fontSize: 9,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    ], // end if (subscription.isNotEmpty)

                    const SizedBox(height: 34),

                    Text(
                      'Booked Services',
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── CLAIM UPDATES SECTION ──
                    GestureDetector(
                      onTap: () => setState(() => _claimsExpanded = !_claimsExpanded),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: claimUpdates.isNotEmpty
                                ? const Color(0xFFD4A017).withOpacity(0.3)
                                : AppColors.line,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Claim Updates',
                                  style: TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Icon(
                                  _claimsExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: const Color(0xFFD4A017),
                                ),
                              ],
                            ),
                            if (_claimsExpanded) ...[
                              const SizedBox(height: 16),
                              if (claimUpdates.isEmpty)
                                Center(
                                  child: Text(
                                    'No claim updates yet',
                                    style: TextStyle(
                                      color: AppColors.mut,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              else
                                ...claimUpdates.map((update) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceSunken,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.line),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (update['photo_url'] != null)
                                          Container(
                                            height: 160,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              image: DecorationImage(
                                                image: NetworkImage(
                                                    update['photo_url']),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            margin: const EdgeInsets.only(
                                                bottom: 12),
                                          ),
                                        Text(
                                          update['description'] ??
                                              'No description',
                                          style: TextStyle(
                                            color: AppColors.txt,
                                            fontSize: 16,
                                            height: 1.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          (DateTime.tryParse('${update['created_at'] ?? ''}')
                                              ?.toString()
                                              .split('.')[0] ?? ''),
                                          style: TextStyle(
                                            color: AppColors.mut,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (bookings.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Center(
                          child: Text(
                            'No Services Booked Yet',
                            style: TextStyle(color: AppColors.mut, fontSize: 16),
                          ),
                        ),
                      ),

                    ...bookings.asMap().entries.map((entry) {
                      final index = entry.key;
                      final booking = entry.value;
                      final bookingId = booking['id'].toString();
                      final currentStatus = (booking['booking_status'] ?? '').toString();
                      final hasUpdate = currentStatus != 'Pending' &&
                          _seenBookingStatuses[bookingId] != currentStatus;
                      final hasUnread = unreadBookingIds
                          .contains(booking['id'].toString());

                      // ── GET GARAGE INFO FROM ADMIN DATA ──
                      final adminData = booking['admin'] as Map<String, dynamic>?;
                      final garageName = adminData?['username'] ?? 'Garage';
                      final garageAddress = adminData?['address'] ?? '';
                      final garageLat = (adminData?['latitude'] as num?)?.toDouble();
                      final garageLong = (adminData?['longitude'] as num?)?.toDouble();
                      // No pickup/drop selected means the customer
                      // themselves is the one going to the garage in
                      // person (to drop off and later collect the
                      // vehicle), so that's the case worth a navigate
                      // button — doorstep pickup/drop is a delivery
                      // partner's job instead, regardless of how the
                      // booking was paid for.
                      final needsGarageVisit =
                          (booking['pickupdrop'] ?? '').toString().toLowerCase() != 'yes';

                      return GestureDetector(
                        key: (widget.highlightSection == 'bookings' && index == 0)
                            ? _highlightKey
                            : null,
                        onTap: () {
                          // Viewing the tracking screen IS "seeing" this
                          // booking's current status — snapshot it now so
                          // the "NEW SERVICE UPDATE" badge clears and stays
                          // cleared until the status next changes.
                          if (currentStatus.isNotEmpty) {
                            _markBookingStatusSeen(bookingId, currentStatus);
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingTrackingScreen(
                                booking: booking,
                              ),
                            ),
                          ).then((_) => fetchBookings());
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 22),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      booking['package_name'] ?? '',
                                      style: TextStyle(
                                        color: AppColors.txt,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  // ── UNREAD CHAT BADGE ──
                                  if (hasUnread) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.red
                                                .withOpacity(0.5),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              Icons
                                                  .chat_bubble_rounded,
                                              color: Colors.white,
                                              size: 11),
                                          SizedBox(width: 5),
                                          Text(
                                            'CHAT',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight:
                                                  FontWeight.w900,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 10),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: AppColors.mut,
                                    size: 18,
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              if (hasUpdate)
                                Container(
                                  margin: const EdgeInsets.only(
                                      bottom: 18),
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700,
                                    borderRadius:
                                        BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red
                                            .withOpacity(0.45),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          Icons
                                              .notifications_active,
                                          color: Colors.white,
                                          size: 18),
                                      SizedBox(width: 10),
                                      Text(
                                        'NEW SERVICE UPDATE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              Text(
                                booking['package_price'] ?? '',
                                style: const TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatFullDateTime(booking['created_at']),
                                style: TextStyle(color: AppColors.mut, fontSize: 13),
                              ),

                              const SizedBox(height: 20),

                              // ── NEW: GARAGE INFO SECTION ──
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSunken,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Garage Name
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on_outlined,
                                          color:
                                              const Color(0xFFD4A017),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Garage: $garageName',
                                            style: const TextStyle(
                                              color: Color(0xFFD4A017),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Garage Address
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.home_outlined,
                                          color: AppColors.mut,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            garageAddress,
                                            style: TextStyle(
                                              color: AppColors.mut,
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                            maxLines: 2,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (needsGarageVisit &&
                                        garageLat != null &&
                                        garageLong != null &&
                                        booking['booking_status'] != 'Delivered') ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _openGarageNavigation(garageLat, garageLong),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFFD4A017),
                                            side: const BorderSide(color: Color(0xFFD4A017)),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12)),
                                          ),
                                          icon: const Icon(Icons.directions_rounded, size: 18),
                                          label: const Text(
                                            'NAVIGATE TO GARAGE',
                                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 0.4),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4A017),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFD4A017)
                                          .withOpacity(0.35),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  booking['booking_status'] ?? '',
                                  style: TextStyle(
                                    color: AppColors.onAccentDark,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),

                              if (_isCancellable(booking))
                                _buildCancelWindow(
                                  record: booking,
                                  table: 'bookings',
                                  bookingType: 'service',
                                  title: booking['package_name'] as String,
                                  price: booking['package_price'] as String?,
                                ),

                              if ((booking['pickupdrop'] ?? '')
                                      .toString()
                                      .toLowerCase() ==
                                  'yes') ...[
                                _DeliveryStageTracker(
                                  stage: booking['delivery_stage'],
                                  stageTimestamps: {
                                    'pickup_started': booking['stage_pickup_started_at'],
                                    'picked_up': booking['stage_picked_up_at'],
                                    'to_garage': booking['stage_to_garage_at'],
                                    'out_for_delivery': booking['stage_out_for_delivery_at'],
                                    'delivered': booking['stage_delivered_at'],
                                  },
                                  createdAt: booking['created_at'],
                                  hasGarageLeg: true,
                                ),
                                if (booking['delivery_stage'] == 'pickup_started')
                                  _PickupOtpVerification(
                                    table: 'bookings',
                                    bookingId: booking['id'],
                                    otpCode: booking['pickup_otp_code'] as String?,
                                    verifiedAt: booking['pickup_otp_verified_at'],
                                    onVerified: fetchBookings,
                                  ),
                                // Final leg back to the customer — mirrors
                                // the pickup OTP above, gating the delivery
                                // partner's "Vehicle Delivered" tap on the
                                // customer confirming they actually got it.
                                if (booking['delivery_stage'] == 'out_for_delivery')
                                  _ReturnOtpVerification(
                                    table: 'bookings',
                                    bookingId: booking['id'],
                                    otpCode: booking['return_otp_code'] as String?,
                                    verifiedAt: booking['return_otp_verified_at'],
                                    partnerLabel: 'your delivery partner',
                                    isCod: (booking['payment_status'] ?? '')
                                            .toString()
                                            .toLowerCase() ==
                                        'cod',
                                    amount: booking['package_price'] as String?,
                                    onVerified: fetchBookings,
                                  ),
                              ] else ...[
                                // No pickup/drop — the customer drives to
                                // the garage themselves, so there's a
                                // drop-off OTP exchange with the garage
                                // directly (booking_details_screen.dart
                                // generates it) instead of a delivery
                                // partner's pickup OTP. Reuses the same
                                // pickup_otp_* columns, which otherwise sit
                                // unused for a booking with no delivery trip.
                                if (booking['booking_status'] !=
                                        'Ready for Pickup' &&
                                    booking['booking_status'] != 'Delivered')
                                  _PickupOtpVerification(
                                    table: 'bookings',
                                    bookingId: booking['id'],
                                    otpCode: booking['pickup_otp_code'] as String?,
                                    verifiedAt: booking['pickup_otp_verified_at'],
                                    partnerLabel: 'the garage',
                                    onVerified: fetchBookings,
                                  ),
                                if (booking['booking_status'] ==
                                    'Ready for Pickup')
                                  _ReturnOtpVerification(
                                    table: 'bookings',
                                    bookingId: booking['id'],
                                    otpCode: booking['return_otp_code'] as String?,
                                    verifiedAt: booking['return_otp_verified_at'],
                                    partnerLabel: 'the garage',
                                    isCod: (booking['payment_status'] ?? '')
                                            .toString()
                                            .toLowerCase() ==
                                        'cod',
                                    amount: booking['package_price'] as String?,
                                    onVerified: fetchBookings,
                                  ),
                              ],

                              const SizedBox(height: 22),

                              Row(
                                children: [
                                  const Spacer(),
                                  Text(
                                    'Tap to view live updates',
                                    style: TextStyle(
                                        color: AppColors.mut,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_ios,
                                      color: AppColors.mut, size: 13),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    if (pollutionBookings.isNotEmpty ||
                        inspectionBookings.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Pollution & Inspection',
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...pollutionBookings.asMap().entries.map(
                        (entry) => _buildComplianceCard(
                          title: 'Pollution Check',
                          booking: entry.value,
                          table: 'pollution_booking',
                          bookingType: 'pollution',
                          highlightKey: (widget.highlightSection == 'pollution' && entry.key == 0)
                              ? _highlightKey
                              : null,
                        ),
                      ),
                      ...inspectionBookings.asMap().entries.map(
                        (entry) => _buildComplianceCard(
                          title: 'Vehicle Inspection',
                          booking: entry.value,
                          table: 'inspection_booking',
                          bookingType: 'inspection',
                          highlightKey: (widget.highlightSection == 'inspection' && entry.key == 0)
                              ? _highlightKey
                              : null,
                        ),
                      ),
                    ],

                    if (claims.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Claims',
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...claims.asMap().entries.map((entry) => _buildClaimCard(
                            entry.value,
                            highlightKey: (widget.highlightSection == 'claim' && entry.key == 0)
                                ? _highlightKey
                                : null,
                          )),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 1,
        onSelect: (i) => handleBottomNavSelect(
          context,
          i,
          currentIndex: 1,
          activeVehicle: _activeVehicleMap,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AskAiButton(
        onTap: () => openAiAdvisor(context, _activeVehicleMap),
      ),
    );
  }

  Map<String, dynamic> get _activeVehicleMap => {
        'id': widget.vehicleId,
        'car_brand': _carBrand,
        'car_model': _carModel,
        'car_number': _carNumber,
      };

  Widget _buildComplianceCard({
    required String title,
    required Map booking,
    required String table,
    required String bookingType,
    Key? highlightKey,
  }) {
    final status = (booking['status'] ?? 'booked').toString();
    final price = (booking['price'] ?? booking['package_price'])?.toString();
    final dateStr = formatFullDateTime(booking['created_at']);
    // Pre-delivery inspection deliberately skips the delivery-stage
    // timeline/OTP flow shown for pollution certificates — coordination
    // happens by phone instead (see customer_phone below and
    // web/deliverydashboard.html), since it's a scheduled-slot booking
    // rather than a spontaneous doorstep pickup. The customer just needs
    // to see the booking went through with the right details.
    final showTimeline = table != 'inspection_booking';

    return Container(
      key: highlightKey,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (price != null)
            Text(
              '₹$price',
              style: const TextStyle(
                color: Color(0xFFD4A017),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            dateStr,
            style: TextStyle(color: AppColors.mut, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A017),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: AppColors.onAccentDark,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          // Pollution bookings are always doorstep pickup+drop (see
          // supabase_pollution_inspection_tables.sql), so this tracker
          // always applies here — no pickupdrop check needed. Inspection
          // bookings skip it entirely (see showTimeline above).
          if (showTimeline) ...[
            _DeliveryStageTracker(
              stage: booking['delivery_stage'],
              stageTimestamps: {
                'pickup_started': booking['stage_pickup_started_at'],
                'picked_up': booking['stage_picked_up_at'],
                'to_garage': booking['stage_to_garage_at'],
                'delivered': booking['stage_delivered_at'],
              },
              createdAt: booking['created_at'],
              isPollutionCertificate: table == 'pollution_booking',
            ),
            if (booking['delivery_stage'] == 'pickup_started')
              _PickupOtpVerification(
                table: table,
                bookingId: booking['id'],
                otpCode: booking['pickup_otp_code'] as String?,
                verifiedAt: booking['pickup_otp_verified_at'],
                onVerified: fetchPollutionBookings,
              ),
            // Final leg back to the customer — these tables skip the
            // out_for_delivery stage, so 'to_garage' is the one immediately
            // before 'delivered' here.
            if (booking['delivery_stage'] == 'to_garage')
              _ReturnOtpVerification(
                table: table,
                bookingId: booking['id'],
                otpCode: booking['return_otp_code'] as String?,
                verifiedAt: booking['return_otp_verified_at'],
                partnerLabel: 'your delivery partner',
                isCod: (booking['payment_status'] ?? '').toString().toLowerCase() == 'cod',
                amount: price,
                onVerified: fetchPollutionBookings,
              ),
          ] else
            _InspectionBookingSummary(booking: booking),
          if (_isCancellable(booking))
            _buildCancelWindow(
              record: booking,
              table: table,
              bookingType: bookingType,
              title: title,
              price: price,
            ),
        ],
      ),
    );
  }

  /// A claim from `claim_table` — since this is now a full doorstep
  /// pickup/garage/return trip just like a paid 'bookings' service (see
  /// claim_screen.dart), this shows the exact same
  /// delivery-stage timeline + pickup/return OTP flow as a regular online
  /// service booking with pickup/drop, rather than the old plain
  /// status-only card.
  Widget _buildClaimCard(Map claim, {Key? highlightKey}) {
    final status = (claim['claim_status'] ?? 'submitted').toString();
    final dateStr = formatFullDateTime(claim['created_at']);
    final description = (claim['damage_description'] ?? '').toString();
    final price = claim['package_price']?.toString();

    return Container(
      key: highlightKey,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Claim Assistance',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (price != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                price,
                style: const TextStyle(color: Color(0xFFD4A017), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          Text(
            dateStr,
            style: TextStyle(color: AppColors.mut, fontSize: 13),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A017),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: AppColors.onAccentDark,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          _DeliveryStageTracker(
            stage: claim['delivery_stage'],
            stageTimestamps: {
              'pickup_started': claim['stage_pickup_started_at'],
              'picked_up': claim['stage_picked_up_at'],
              'to_garage': claim['stage_to_garage_at'],
              'out_for_delivery': claim['stage_out_for_delivery_at'],
              'delivered': claim['stage_delivered_at'],
            },
            createdAt: claim['created_at'],
            hasGarageLeg: true,
          ),
          if (claim['delivery_stage'] == 'pickup_started')
            _PickupOtpVerification(
              table: 'claim_table',
              bookingId: claim['id'],
              otpCode: claim['pickup_otp_code'] as String?,
              verifiedAt: claim['pickup_otp_verified_at'],
              onVerified: fetchClaims,
            ),
          if (claim['delivery_stage'] == 'out_for_delivery')
            _ReturnOtpVerification(
              table: 'claim_table',
              bookingId: claim['id'],
              otpCode: claim['return_otp_code'] as String?,
              verifiedAt: claim['return_otp_verified_at'],
              partnerLabel: 'your delivery partner',
              onVerified: fetchClaims,
            ),
          // Claims have no cancel option — see _anyCancellable, which no
          // longer includes `claims` either.
        ],
      ),
    );
  }

  void _showImageViewer(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: Colors.black.withOpacity(0.85),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
            // Pinch-to-zoom image
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.image_not_supported,
                      color: AppColors.mut,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "why are you cancelling" dialog used by [_VehicleBookingsScreenState
/// ._showCancelFlow]. Owns its own TextEditingController and disposes it in
/// its own State.dispose() — created and disposed by [showDialog] itself
/// only once the dialog's close animation actually finishes, unlike a
/// controller created in the caller and disposed the instant the awaited
/// Future resolves, which raced the dialog's own closing transition and
/// crashed with "TextEditingController used after being disposed".
///
/// Pops with the trimmed reason text on CANCEL (always non-empty, since the
/// button is disabled otherwise), or `null` on RETURN.
class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _reasonController.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.help_outline_rounded, color: Colors.red, size: 26),
            ),
            const SizedBox(height: 18),
            Text(
              'Hey, Can we know why you changed your mind?',
              style: TextStyle(
                color: AppColors.txt,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: AppColors.txt),
              decoration: InputDecoration(
                hintText: 'Type your reason here...',
                hintStyle: TextStyle(color: AppColors.mut),
                filled: true,
                fillColor: AppColors.surfaceSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.line),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'RETURN',
                      style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSubmit
                        ? () => Navigator.pop(context, _reasonController.text.trim())
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: Colors.red.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A day/date/time formatter shared by the delivery-stage tracker and the
/// pollution/inspection compliance cards, e.g. "Wed, 10 Sep 2026, 3:45 PM".
String formatFullDateTime(dynamic iso) {
  if (iso == null) return '';
  try {
    final date = DateTime.parse(iso.toString()).toLocal();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} '
        '${date.year}, $hour12:$minute $period';
  } catch (_) {
    return '';
  }
}

/// Shown in place of the delivery-stage timeline for a pre-delivery
/// inspection booking — just confirms the slot booking went through with
/// the details the customer picked in inspection_screen.dart's PLAN
/// INSPECTION popup. No stepper, no OTP: the delivery partner coordinates
/// pickup/return by phone (see customer_phone on the delivery dashboard)
/// rather than an in-app code exchange, since this is a pre-scheduled
/// slot rather than a spontaneous doorstep pickup.
class _InspectionBookingSummary extends StatelessWidget {
  const _InspectionBookingSummary({required this.booking});

  final Map booking;

  @override
  Widget build(BuildContext context) {
    final condition = booking['vehicle_condition']?.toString();
    final vehicleType = booking['vehicle_type']?.toString();
    final slotDateRaw = booking['slot_date']?.toString();
    final slotTime = booking['slot_time']?.toString();

    String? slotDateLabel;
    if (slotDateRaw != null) {
      final parsed = DateTime.tryParse(slotDateRaw);
      if (parsed != null) {
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        slotDateLabel = '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Booking Confirmed',
                style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
          if (condition != null || vehicleType != null || slotDateLabel != null) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.green.withOpacity(0.2)),
            const SizedBox(height: 12),
            if (condition != null) _row('Vehicle', condition),
            if (vehicleType != null) _row('Type', vehicleType),
            if (slotDateLabel != null)
              _row('Scheduled', slotTime != null ? '$slotDateLabel • $slotTime' : slotDateLabel),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.mut, fontSize: 12.5)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: AppColors.txt, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// An Amazon-style horizontal stepper showing where a booking's doorstep
/// pickup/drop currently stands, driven by the delivery partner from
/// web/deliverydashboard.html. `stage` is null until the partner taps
/// "Start Pickup" there — shown here as "Initiating Pickup" — then moves
/// through pickup_started -> picked_up -> to_garage -> delivered (or, for
/// the main service-booking card, the extra out_for_delivery leg once the
/// garage marks the service done — see [hasGarageLeg]).
class _DeliveryStageTracker extends StatelessWidget {
  const _DeliveryStageTracker({
    required this.stage,
    required this.stageTimestamps,
    required this.createdAt,
    this.hasGarageLeg = false,
    this.isPollutionCertificate = false,
  });

  final String? stage;

  /// Keyed by stage name (pickup_started/picked_up/to_garage/
  /// out_for_delivery/delivered) — when each stage was reached, or null
  /// if not reached yet.
  final Map<String, dynamic> stageTimestamps;

  final dynamic createdAt;

  /// True only for the main service-booking card ('bookings' table) —
  /// that's the only one with a garage-wait step of its own (see
  /// web/deliverydashboard.html's STAGE_ORDER_BOOKINGS), so it's the only
  /// one that ever actually reaches 'out_for_delivery'. Pollution/
  /// inspection bookings keep the original 4-node tracker since they
  /// never produce that stage value at all.
  final bool hasGarageLeg;

  /// True only for the pollution-certificate card ('pollution_booking') —
  /// swaps in wording that matches what's actually happening on that
  /// booking (getting the certificate processed, not "at a garage") for
  /// the same underlying pickup_started/picked_up/to_garage/delivered
  /// stage values inspection_booking still shows generically. Display
  /// only — no new stage values or DB columns involved.
  final bool isPollutionCertificate;

  static const _stageKeysWithGarageLeg = [
    'booked', 'pickup_started', 'picked_up', 'to_garage', 'out_for_delivery', 'delivered',
  ];
  static const _stageKeysSimple = ['booked', 'pickup_started', 'picked_up', 'to_garage', 'delivered'];
  List<String> get _stageKeys => hasGarageLeg ? _stageKeysWithGarageLeg : _stageKeysSimple;

  static const _nodeLabels = {
    'booked': 'Initiating\nPickup',
    'pickup_started': 'Pickup\nStarted',
    'picked_up': 'Picked\nUp',
    'to_garage': 'At\nGarage',
    'out_for_delivery': 'Out For\nDelivery',
    'delivered': 'Delivered',
  };

  static const _nodeLabelsPollution = {
    'booked': 'Initiating\nPickup',
    'pickup_started': 'Car\nPickup',
    'picked_up': 'Getting\nCertificate',
    'to_garage': 'Out For\nDelivery',
    'delivered': 'Delivered',
  };

  Map<String, String> get _activeNodeLabels =>
      isPollutionCertificate ? _nodeLabelsPollution : _nodeLabels;

  static const _statusText = {
    'booked': 'Initiating Pickup',
    'pickup_started': 'Pickup Started',
    'picked_up': 'Vehicle Picked Up',
    'to_garage': 'Vehicle At Garage',
    'out_for_delivery': 'Out For Delivery',
    'delivered': 'Vehicle Delivered',
  };

  static const _statusTextPollution = {
    'booked': 'Initiating Pickup',
    'pickup_started': 'Car Pickup',
    'picked_up': 'Getting Certificate',
    'to_garage': 'Out For Delivery',
    'delivered': 'Delivered',
  };

  Map<String, String> get _activeStatusText =>
      isPollutionCertificate ? _statusTextPollution : _statusText;

  static const Color _gold = Color(0xFFD4A017);

  int get _activeIndex => _stageKeys.indexOf(stage ?? 'booked');

  dynamic get _currentTimestamp {
    if (stage == null) return createdAt;
    return stageTimestamps[stage] ?? createdAt;
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeIndex;
    final timestamp = formatFullDateTime(_currentTimestamp);

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _activeStatusText[stage ?? 'booked'] ?? 'Status Unavailable',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: 15),
          ),
          if (timestamp.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(timestamp, style: TextStyle(color: AppColors.mut, fontSize: 11.5)),
          ],
          const SizedBox(height: 18),
          Row(
            children: List.generate(_stageKeys.length, (i) {
              final reached = i <= activeIndex;
              final leftLineReached = i > 0 && i <= activeIndex;
              final rightLineReached = i < _stageKeys.length - 1 && i < activeIndex;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: i == 0
                          ? const SizedBox()
                          : Container(height: 3, color: leftLineReached ? _gold : AppColors.line),
                    ),
                    Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reached ? _gold : AppColors.line,
                      ),
                    ),
                    Expanded(
                      child: i == _stageKeys.length - 1
                          ? const SizedBox()
                          : Container(height: 3, color: rightLineReached ? _gold : AppColors.line),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(_stageKeys.length, (i) {
              final key = _stageKeys[i];
              final reached = i <= activeIndex;
              return Expanded(
                child: Text(
                  _activeNodeLabels[key]!,
                  textAlign: i == 0
                      ? TextAlign.start
                      : (i == _stageKeys.length - 1 ? TextAlign.end : TextAlign.center),
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.25,
                    fontWeight: reached ? FontWeight.w800 : FontWeight.w500,
                    color: reached ? AppColors.txt : AppColors.mut,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Shown only while `delivery_stage == 'pickup_started'` — the delivery
/// partner has arrived and generated a code on their dashboard
/// (web/deliverydashboard.html's renderPickupOtpBlock); this is where the
/// customer enters it before handing over the keys. Matching against
/// [otpCode] happens server-side via the `.eq('pickup_otp_code', ...)`
/// filter on the update itself, rather than comparing [otpCode] locally,
/// so a zero-row result is the only source of truth for "wrong code."
class _PickupOtpVerification extends StatefulWidget {
  const _PickupOtpVerification({
    required this.table,
    required this.bookingId,
    required this.otpCode,
    required this.verifiedAt,
    required this.onVerified,
    this.partnerLabel = 'your delivery partner',
  });

  /// 'bookings' | 'pollution_booking' | 'inspection_booking'.
  final String table;
  final dynamic bookingId;

  /// The code the delivery partner generated — null until they do.
  final String? otpCode;

  /// Set once the customer has already verified successfully — shows a
  /// "waiting for pickup" state instead of the entry field again.
  final dynamic verifiedAt;

  /// Re-fetches this card's booking list so the tracker/verification state
  /// above picks up the fresh `pickup_otp_verified_at`.
  final VoidCallback onVerified;

  /// Who generated the code — 'your delivery partner' (default, doorstep
  /// pickup) or 'the garage' (drop-off verification for a booking with no
  /// pickup/drop trip) — filled into the copy below.
  final String partnerLabel;

  @override
  State<_PickupOtpVerification> createState() => _PickupOtpVerificationState();
}

class _PickupOtpVerificationState extends State<_PickupOtpVerification> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _justVerified = false;
  String? _error;
  // Bumped on every failed attempt — giving the shake TweenAnimationBuilder
  // below a fresh ValueKey each time is what makes it replay instead of
  // just sitting at its already-settled end value.
  int _shakeToken = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final entered = _controller.text.trim();
    if (entered.isEmpty) {
      setState(() {
        _error = 'Enter the code ${widget.partnerLabel} told you.';
        _shakeToken++;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from(widget.table)
          .update({'pickup_otp_verified_at': DateTime.now().toIso8601String()})
          .eq('id', widget.bookingId)
          .eq('pickup_otp_code', entered)
          .select('id');

      if (!mounted) return;

      if ((rows as List).isEmpty) {
        setState(() {
          _error = "That code doesn't match — check with ${widget.partnerLabel} and try again.";
          _submitting = false;
          _shakeToken++;
        });
        return;
      }

      // Flips the button itself to the same green-check "success" beat the
      // Edit Vehicle sheet's SAVE CHANGES button uses, just ahead of the
      // fuller-screen confirmation below.
      setState(() {
        _submitting = false;
        _justVerified = true;
      });
      widget.onVerified();

      await Future.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      await _showVerifiedDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong verifying that code — please try again.';
        _submitting = false;
        _shakeToken++;
      });
    }
  }

  Future<void> _showVerifiedDialog() {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Verified',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) => Transform.scale(scale: value, child: child),
                  child: const Icon(Icons.verified_rounded, color: Colors.green, size: 56),
                ),
                const SizedBox(height: 14),
                Text(
                  'Verified',
                  style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  'Give your keys to ${widget.partnerLabel} now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mut, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('OK', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    final Key contentKey;

    if (widget.verifiedAt != null || _justVerified) {
      contentKey = const ValueKey('verified');
      content = Container(
        key: contentKey,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Verified — this step is complete.',
                style: TextStyle(color: AppColors.txt.withOpacity(0.85), fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
    } else if (widget.otpCode == null) {
      contentKey = const ValueKey('waiting-for-code');
      content = Container(
        key: contentKey,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(Icons.pending_outlined, color: AppColors.mut, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_capitalize(widget.partnerLabel)} will share a code when you arrive — enter it here before handing over the keys.',
                style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
    } else {
      contentKey = const ValueKey('entry');
      content = Container(
        key: contentKey,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              const Color(0xFFD4A017).withOpacity(0.08), AppColors.surfaceSunken),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify ${widget.partnerLabel}',
              style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Ask ${widget.partnerLabel} for the code and enter it below before handing over the keys.',
              style: TextStyle(color: AppColors.mut, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_shakeToken),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 420),
                    // A decaying wobble — sin() for the back-and-forth,
                    // (1 - value) as the envelope so it settles to dead
                    // still by the time the animation ends.
                    builder: (context, value, child) => Transform.translate(
                      offset: Offset(math.sin(value * math.pi * 3) * 8 * (1 - value), 0),
                      child: child,
                    ),
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      style: TextStyle(
                        color: AppColors.txt,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 6,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••',
                        hintStyle: TextStyle(color: AppColors.mut, letterSpacing: 6),
                        filled: true,
                        fillColor: AppColors.surfaceRaised,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error != null ? Colors.redAccent : AppColors.line,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error != null ? Colors.redAccent : AppColors.line,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(_submitting ? 0.6 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _submitting ? null : _verify,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _submitting
                              ? const SizedBox(
                                  key: ValueKey('spinner'),
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Text(
                                  'Verify',
                                  key: ValueKey('label'),
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox.shrink(key: ValueKey('no-error'))
                  : Padding(
                      key: const ValueKey('error'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    return _VehicleEditFadeIn(
      index: 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        ),
        child: content,
      ),
    );
  }
}

/// Shown on the leg immediately before the final hand-back to the customer
/// — 'out_for_delivery' for 'bookings' (delivery partner), 'to_garage' for
/// pollution_booking/inspection_booking (no separate out-for-delivery leg
/// there), or once booking_details_screen.dart's MARK AS DONE has fired for
/// a 'bookings' row with no pickup/drop (customer collects in person).
/// Mirrors [_PickupOtpVerification] exactly, but against the
/// `return_otp_code` / `return_otp_verified_at` columns, and confirming the
/// customer *received* their vehicle rather than confirming who's taking it.
class _ReturnOtpVerification extends StatefulWidget {
  const _ReturnOtpVerification({
    required this.table,
    required this.bookingId,
    required this.otpCode,
    required this.verifiedAt,
    required this.onVerified,
    required this.partnerLabel,
    this.isCod = false,
    this.amount,
  });

  /// 'bookings' | 'pollution_booking' | 'inspection_booking'.
  final String table;
  final dynamic bookingId;

  /// The code the garage/delivery partner generated — null until they do.
  final String? otpCode;

  /// Set once the customer has already verified successfully.
  final dynamic verifiedAt;

  /// Re-fetches this card's booking list so it picks up the fresh
  /// `return_otp_verified_at`.
  final VoidCallback onVerified;

  /// Who's handing the vehicle back — e.g. 'your delivery partner' or
  /// 'the garage' — filled into the copy below.
  final String partnerLabel;

  /// Whether this booking was paid Cash on Pickup — when true, a cash
  /// reminder is shown alongside the return code so the customer knows to
  /// have payment ready for [partnerLabel], not just the vehicle handover.
  final bool isCod;

  /// The amount to show in that reminder — whatever [amount] format the
  /// caller already has on hand (a plain string, may be null).
  final String? amount;

  @override
  State<_ReturnOtpVerification> createState() => _ReturnOtpVerificationState();
}

class _ReturnOtpVerificationState extends State<_ReturnOtpVerification> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _justVerified = false;
  String? _error;
  // Bumped on every failed attempt — giving the shake TweenAnimationBuilder
  // below a fresh ValueKey each time is what makes it replay instead of
  // just sitting at its already-settled end value.
  int _shakeToken = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final entered = _controller.text.trim();
    if (entered.isEmpty) {
      setState(() {
        _error = 'Enter the code ${widget.partnerLabel} told you.';
        _shakeToken++;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // For 'bookings' rows, this is also the moment the booking itself
      // counts as finished — flipping booking_status to 'Delivered' here
      // (rather than waiting on the admin's separate stage dropdown in
      // booking_details_screen.dart) is what lets the customer actually
      // delete this vehicle afterwards; see _checkActiveService below,
      // which also treats return_otp_verified_at alone as "done" as a
      // fallback for rows verified before this existed.
      //
      // Exception: a COD, in-person-collection booking (no delivery
      // partner) isn't actually finished yet — the vehicle handover is
      // confirmed, but the garage still needs to collect cash and tap
      // COLLECT PAYMENT in booking_details_screen.dart before this counts
      // as truly done. _checkActiveService's return_otp_verified_at
      // fallback still lets the vehicle be deleted in the meantime, so
      // deferring this doesn't strand anyone.
      final deferToPaymentConfirmation =
          widget.table == 'bookings' && widget.isCod && widget.partnerLabel == 'the garage';
      final updatePayload = <String, dynamic>{
        'return_otp_verified_at': DateTime.now().toIso8601String(),
      };
      if (widget.table == 'bookings' && !deferToPaymentConfirmation) {
        updatePayload['booking_status'] = 'Delivered';
      } else if (widget.table == 'claim_table') {
        // claim_table plays the same role 'bookings' does here, just
        // under its own pre-existing column name (claim_status already
        // held 'submitted'/'Ready for Pickup' before this OTP existed).
        updatePayload['claim_status'] = 'Delivered';
      }

      final rows = await Supabase.instance.client
          .from(widget.table)
          .update(updatePayload)
          .eq('id', widget.bookingId)
          .eq('return_otp_code', entered)
          .select('id');

      if (!mounted) return;

      if ((rows as List).isEmpty) {
        setState(() {
          _error = "That code doesn't match — check with ${widget.partnerLabel} and try again.";
          _submitting = false;
          _shakeToken++;
        });
        return;
      }

      // Flips the button itself to the same green-check "success" beat the
      // Edit Vehicle sheet's SAVE CHANGES button uses, just ahead of the
      // fuller-screen confirmation below.
      setState(() {
        _submitting = false;
        _justVerified = true;
      });
      widget.onVerified();

      await Future.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      await _showVerifiedDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong verifying that code — please try again.';
        _submitting = false;
        _shakeToken++;
      });
    }
  }

  Future<void> _showVerifiedDialog() {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Vehicle received',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) => Transform.scale(scale: value, child: child),
                  child: const Icon(Icons.verified_rounded, color: Colors.green, size: 56),
                ),
                const SizedBox(height: 14),
                Text(
                  'Vehicle received',
                  style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  'Thanks for confirming — this booking is now complete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mut, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('OK', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    final Key contentKey;

    if (widget.verifiedAt != null || _justVerified) {
      contentKey = const ValueKey('verified');
      content = Container(
        key: contentKey,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Verified — this booking is complete.',
                style: TextStyle(color: AppColors.txt.withOpacity(0.85), fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
    } else if (widget.otpCode == null) {
      contentKey = const ValueKey('waiting-for-code');
      content = Container(
        key: contentKey,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(Icons.pending_outlined, color: AppColors.mut, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_capitalize(widget.partnerLabel)} will share a code before handing back your vehicle — enter it here to confirm you\'ve received it.',
                style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
    } else {
      contentKey = const ValueKey('entry');
      content = Container(
        key: contentKey,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              const Color(0xFFD4A017).withOpacity(0.08), AppColors.surfaceSunken),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Confirm you've received your vehicle",
              style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text(
              'Ask ${widget.partnerLabel} for the code and enter it below.',
              style: TextStyle(color: AppColors.mut, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_shakeToken),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 420),
                    // A decaying wobble — sin() for the back-and-forth,
                    // (1 - value) as the envelope so it settles to dead
                    // still by the time the animation ends.
                    builder: (context, value, child) => Transform.translate(
                      offset: Offset(math.sin(value * math.pi * 3) * 8 * (1 - value), 0),
                      child: child,
                    ),
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      style: TextStyle(
                        color: AppColors.txt,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 6,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••',
                        hintStyle: TextStyle(color: AppColors.mut, letterSpacing: 6),
                        filled: true,
                        fillColor: AppColors.surfaceRaised,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error != null ? Colors.redAccent : AppColors.line,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _error != null ? Colors.redAccent : AppColors.line,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(_submitting ? 0.6 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _submitting ? null : _verify,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _submitting
                              ? const SizedBox(
                                  key: ValueKey('spinner'),
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Text(
                                  'Verify',
                                  key: ValueKey('label'),
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox.shrink(key: ValueKey('no-error'))
                  : Padding(
                      key: const ValueKey('error'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11.5),
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    final switcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: child,
        ),
      ),
      child: content,
    );

    if (!widget.isCod) {
      return _VehicleEditFadeIn(index: 0, child: switcher);
    }

    final verified = widget.verifiedAt != null || _justVerified;
    final amountText = widget.amount != null && widget.amount!.isNotEmpty
        ? ' of ${widget.amount}'
        : '';

    return _VehicleEditFadeIn(
      index: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          switcher,
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_rupee_rounded, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verified
                        ? "Don't forget to pay${amountText.isEmpty ? ' the cash amount' : amountText} in cash to ${widget.partnerLabel}."
                        : 'This booking is Cash on Pickup — please pay${amountText.isEmpty ? ' the cash amount' : amountText} to ${widget.partnerLabel} when they arrive.',
                    style: TextStyle(color: AppColors.txt.withOpacity(0.85), fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Fades + rises a field into place, each successive [index] settling
/// slightly later than the one before — used by the "Edit Vehicle" sheet
/// above so its fields cascade in rather than popping in all at once.
class _VehicleEditFadeIn extends StatelessWidget {
  const _VehicleEditFadeIn({required this.index, required this.child});

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