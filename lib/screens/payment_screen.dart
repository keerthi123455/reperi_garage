import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/payment_service_factory.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'vehicle_bookings_screen.dart';
import 'package:reperi_garage/services/address_service.dart';
import 'package:reperi_garage/screens/address_management_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/booking_api.dart';
import '../services/payment_service.dart';
import '../models/catalog_item.dart' show formatRupees;
import '/services/service_area.dart';
import '../widgets/error_display.dart';

/// Fixed white/blue corporate palette for this screen — set explicitly
/// rather than pulled from Theme.of(context), so checkout looks identical
/// whether the device is in light or dark mode. Radii here are kept modest
/// (12–16) rather than the pill-shaped buttons used elsewhere in the app;
/// sharper corners read as more like a bank/payment form, which is the
/// point on the one screen where people are about to pay.
class _PayColors {
  static const bg = Color(0xFFF5F8FC);
  static const surface = Colors.white;
  static const border = Color(0xFFE0E7F1);
  static const navy = Color(0xFF0E2A4A);
  static const blue = Color(0xFF1D5FD6);
  static const blueDark = Color(0xFF123E8F);
  static const blueTint = Color(0xFFEAF1FC);
  static const muted = Color(0xFF62728A);
  static const success = Color(0xFF1E9E64);
}

class PaymentScreen extends StatefulWidget {
  /// Shown at the top of checkout ("SELECTED PACKAGE") and on success.
  final String title;
  final String duration;
  final String vehicleId;

  /// What's being booked: service keys from the Supabase `services` table —
  /// one package plus any add-ons. The price and who the booking goes to
  /// are decided by the server (booking-api), never by the app.
  final List<String> serviceKeys;

  /// Extra details some bookings need, passed straight to the server:
  /// `label` (Roadside issue), `inspection` (condition + slot) or `claim`
  /// (uploaded document paths + description).
  final Map<String, dynamic> bookingOptions;

  /// Fleet "Pay Now": pays an existing fleet_pickup_requests row, priced by
  /// the garage on that request. When set, [serviceKeys] is ignored.
  final String? fleetRequestId;

  /// Whether this booking needs a real vehicle behind it. True for every
  /// ordinary service booking (the default); false for Roadside Assistance
  /// and fleet payments, which pass an empty [vehicleId] on purpose. When
  /// true and [vehicleId] is empty, this screen shows an "add a vehicle
  /// first" prompt, since every package screen upstream can be browsed
  /// without one.
  final bool vehicleRequired;

  /// Called when this screen fills in a vehicle it wasn't given — either
  /// the customer's existing active vehicle, or one they just added from
  /// the "ADD A VEHICLE" prompt.
  final ValueChanged<String>? onVehicleResolved;

  /// Which section of VehicleBookingsScreen this booking lands in, so the
  /// success flow can scroll straight to it — 'bookings', 'pollution',
  /// 'inspection', 'claim' or 'subscription'.
  final String bookingSection;

  const PaymentScreen({
    super.key,
    required this.title,
    required this.duration,
    required this.vehicleId,
    this.serviceKeys = const [],
    this.bookingOptions = const {},
    this.fleetRequestId,
    this.vehicleRequired = true,
    this.onVehicleResolved,
    this.bookingSection = 'bookings',
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin {
  /// The vehicle this booking is for. Starts as [PaymentScreen.vehicleId]
  /// but can be filled in here when that was empty — see
  /// _resolveVehicleOrAsk.
  late String _vehicleId = widget.vehicleId;

  bool orderPlaced = false;
  bool isProcessing = false;

  bool get _isFleet => widget.fleetRequestId != null;

  // ── Server price ──
  // Everything shown in the bill comes from booking-api's quote, which
  // prices the cart from the `services` table — the same calculation the
  // server charges, so what the customer sees is exactly what they pay.
  BookingQuote? _quote;
  bool _quoteLoading = true;
  String? _quoteError;

  // ── Doorstep pickup & drop add-on ──
  bool _addPickupDrop = false;
  bool _pickupDefaultApplied = false;

  bool get _showPickupDrop => _quote?.showsPickupCard ?? false;
  bool get _pickupLocked => _quote?.pickupLocked ?? false;
  int get _pickupDropFee => _quote?.pickupFee ?? 0;

  int? get _totalAmountRupees {
    final q = _quote;
    if (q == null) return null;
    final fee = (q.pickupMode == 'locked' || (q.pickupMode == 'optional' && _addPickupDrop)) ? q.pickupFee : 0;
    return q.subtotal + fee;
  }

  String get _totalPriceDisplay {
    final total = _totalAmountRupees;
    return total != null ? formatRupees(total) : '—';
  }

  Future<void> _loadQuote() async {
    if (!_quoteLoading || _quoteError != null) {
      setState(() {
        _quoteLoading = true;
        _quoteError = null;
      });
    }
    try {
      final q = await BookingApi.quote(
        items: widget.serviceKeys,
        fleetRequestId: widget.fleetRequestId,
      );
      if (!mounted) return;
      setState(() {
        _quote = q;
        _quoteLoading = false;
        if (q.pickupLocked) _addPickupDrop = true;
        // Doorstep pickup is pre-selected the first time the price loads;
        // the customer can still switch it off.
        if (!_pickupDefaultApplied && q.pickupMode == 'optional') _addPickupDrop = true;
        _pickupDefaultApplied = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteLoading = false;
        _quoteError = e is BookingApiException ? e.message : 'Couldn\'t load the price. Check your connection and try again.';
      });
    }
  }

  /// The fee is shown right on the card, so toggling needs no extra
  /// confirmation dialog.
  void _setPickupDrop(bool value) {
    if (_pickupLocked) return;
    setState(() => _addPickupDrop = value);
  }

  // ── Address state ──
  String selectedAddress = 'Loading address...';
  double? selectedLatitude;
  double? selectedLongitude;
  bool addressLoading = true;
  late final AddressService _addressService;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _loadQuote();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    // Package-browsing screens upstream (the catalog, tier pickers, etc.)
    // are reachable without a vehicle so people can look around before
    // adding one — this is the one place that actually needs a real
    // vehicle, so it's the one place that checks. Deferred a frame since
    // showDialog needs the widget tree to have already been laid out.
    if (widget.vehicleRequired && _vehicleId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveVehicleOrAsk());
    }

    // ── Initialize address service and load default address ──
    _addressService = AddressService();
    _loadDefaultAddress();
  }

  /// No vehicle was passed in. Package screens opened from Home before
  /// any vehicle existed keep that empty id even after one is added, so
  /// first check whether the customer has a vehicle NOW (their active one)
  /// and just use it — only ask them to add one when there truly is none.
  Future<void> _resolveVehicleOrAsk() async {
    final existing = await _findCurrentVehicleId();
    if (!mounted) return;
    if (existing != null) {
      _useVehicle(existing);
    } else {
      _showVehicleRequiredDialog();
    }
  }

  /// The customer's active vehicle, or any vehicle they own — null if none.
  Future<String?> _findCurrentVehicleId() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    try {
      final profile = await supabase
          .from('profiles')
          .select('active_vehicle_id')
          .eq('id', user.id)
          .maybeSingle();
      final active = profile?['active_vehicle_id']?.toString();
      if (active != null && active.isNotEmpty) return active;

      final rows = await supabase
          .from('vehicles')
          .select('id')
          .eq('user_id', user.id)
          .limit(1);
      if ((rows as List).isNotEmpty) return rows.first['id']?.toString();
    } catch (_) {}
    return null;
  }

  void _useVehicle(String vehicleId) {
    setState(() => _vehicleId = vehicleId);
    widget.onVehicleResolved?.call(vehicleId);
  }

  /// Shown instead of letting the user proceed to checkout with no
  /// vehicle to book the service against.
  ///
  /// FIX: ADD VEHICLE used to REPLACE this screen with Profile, so after
  /// adding a car the customer fell back to the package screen — which
  /// still had no vehicle — and got asked again. Now Profile opens on top
  /// of this screen and closes itself as soon as the vehicle is saved,
  /// handing back its id, so checkout carries on right here.
  void _showVehicleRequiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _PayColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ADD A VEHICLE TO BOOK THIS SERVICE',
          style: TextStyle(color: _PayColors.navy, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // close dialog
              final addedId = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(
                    autoOpenAddVehicle: true,
                    returnAddedVehicle: true,
                  ),
                ),
              );
              if (!mounted) return;
              final vehicleId = addedId ?? await _findCurrentVehicleId();
              if (!mounted) return;
              if (vehicleId != null) {
                _useVehicle(vehicleId);
              } else {
                // Backed out of Profile without adding one — nothing to
                // book against, so leave checkout.
                Navigator.pop(context);
              }
            },
            child: const Text('ADD VEHICLE', style: TextStyle(color: _PayColors.blue)),
          ),
        ],
      ),
    );
  }

  /// Load the default address for display
  Future<void> _loadDefaultAddress() async {
    try {
      final defaultAddr = await _addressService.getDefaultAddress(rethrowOnError: true);

      if (mounted) {
        setState(() {
          if (defaultAddr != null) {
            selectedAddress = defaultAddr['address'] ?? 'Address not found';
            selectedLatitude = defaultAddr['latitude'];
            selectedLongitude = defaultAddr['longitude'];
          } else {
            selectedAddress = 'No address saved';
          }
          addressLoading = false;
        });
      }

      // Fleet payments (billItems set) aren't gated by the consumer
      // doorstep-service area — only check for the regular booking flow,
      // and only once we actually have coordinates to check.
      if (!_isFleet &&
          selectedLatitude != null &&
          selectedLongitude != null &&
          !ServiceArea.isWithinServiceArea(selectedLatitude!, selectedLongitude!)) {
        _showOutOfServiceAreaDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          selectedAddress = 'Error loading address';
          addressLoading = false;
        });
      }
    }
  }

  /// Shown when the customer's address falls outside the area this app
  /// currently services. Used to just leave them stuck with no way
  /// forward except backing out entirely — now offers changing the
  /// pickup address right from here, reusing the same
  /// _navigateToAddressManagement() flow the "no address saved" dialog
  /// already uses: it pushes AddressManagementScreen and re-runs
  /// _loadDefaultAddress() on return, which re-checks the new address
  /// against the service area automatically. Pick one that's in range
  /// and this dialog simply doesn't reappear — no need to back out and
  /// restart the booking from scratch.
  void _showOutOfServiceAreaDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _PayColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Not Available in Your Area',
          style: TextStyle(color: _PayColors.navy, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'We are not operational in your area yet! Try a different pickup address, or come back later.',
          style: TextStyle(color: _PayColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // leave PaymentScreen
            },
            child: const Text('CANCEL', style: TextStyle(color: _PayColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog only — stay on PaymentScreen
              _navigateToAddressManagement();
            },
            child: const Text('CHANGE ADDRESS', style: TextStyle(color: _PayColors.blue)),
          ),
        ],
      ),
    );
  }

  /// Check if address is valid before proceeding to payment
  bool _isAddressValid() {
    return selectedAddress.isNotEmpty &&
        selectedAddress != 'No address saved' &&
        selectedAddress != 'Address not found' &&
        selectedAddress != 'Loading address...' &&
        selectedLatitude != null &&
        selectedLongitude != null;
  }

  /// Show error popup if address is invalid
  void _showAddressErrorPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _PayColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Address Required',
          style: TextStyle(
            color: _PayColors.navy,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Enter valid address to continue to payment',
          style: TextStyle(color: _PayColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: _PayColors.blue),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToAddressManagement();
            },
            child: const Text(
              'Add Address',
              style: TextStyle(color: _PayColors.blue),
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to address management screen
  Future<void> _navigateToAddressManagement() async {
    // returnAfterSave: the address screen closes itself as soon as a new
    // address is saved, bringing the customer straight back here.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddressManagementScreen(returnAfterSave: true),
      ),
    );
    // Reload address after returning
    await _loadDefaultAddress();
  }

  void _goToHomeScreen() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  /// After a successful booking, land the customer on that vehicle's own
  /// dashboard, scrolled straight to the package they just booked — rather
  /// than always dumping them back on the home screen. Roadside Assistance
  /// and the fleet "Pay Now" flow pass an empty [vehicleId] on purpose
  /// (there's no single vehicle to show a dashboard for), so those still
  /// fall back to Home.
  Future<void> _goToBookingDestination() async {
    if (_vehicleId.isEmpty) {
      _goToHomeScreen();
      return;
    }

    String carModel = widget.title;
    String carBrand = '';
    String carNumber = '';
    try {
      final vehicle = await Supabase.instance.client
          .from('vehicles')
          .select('car_model, car_brand, car_number')
          .eq('id', _vehicleId)
          .single();
      carModel = (vehicle['car_model'] ?? carModel).toString();
      carBrand = (vehicle['car_brand'] ?? carBrand).toString();
      carNumber = (vehicle['car_number'] ?? carNumber).toString();
    } catch (e) {
      // Vehicle lookup failed — still worth landing on the dashboard with
      // whatever we have rather than falling all the way back to Home.
    }

    if (!mounted) return;
    // Two pushes, not one pushAndRemoveUntil straight to
    // VehicleBookingsScreen with (route) => false — that used to wipe out
    // the entire stack including HomeScreen, leaving this screen as the
    // only route that ever existed. With nothing left underneath it, the
    // bottom nav's Home tab (which just pops back to the first route) had
    // nothing to pop to, there was no back arrow since Navigator.canPop
    // was false, and the Android back button exited the app outright.
    // Rebuilding a fresh Home underneath first, then pushing the vehicle
    // dashboard on top of it, gives the exact same two-level stack every
    // other bottom-nav destination in this app already ends up with.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleBookingsScreen(
          vehicleId: _vehicleId,
          carModel: carModel,
          carBrand: carBrand,
          carNumber: carNumber,
          highlightSection: widget.bookingSection,
        ),
      ),
    );
  }

  /// Shared success animation + delay + navigation, used by both payment paths
  Future<void> _showSuccessAndGoHome() async {
    setState(() {
      orderPlaced = true;
      isProcessing = false;
    });

    _controller.forward();

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    await _goToBookingDestination();
  }

  /// Turns a booking-api error into the right next step for the customer.
  void _handleCreateError(Object e) {
    if (!mounted) return;
    setState(() => isProcessing = false);
    if (e is BookingApiException) {
      switch (e.code) {
        case 'address_required':
          _showAddressErrorPopup();
          return;
        case 'out_of_service_area':
          _showOutOfServiceAreaDialog();
          return;
        case 'vehicle_required':
          _showVehicleRequiredDialog();
          return;
        case 'service_unavailable':
        case 'not_payable':
          // Prices/packages changed since this screen opened — refresh.
          _loadQuote();
          break;
      }
      ErrorDisplay.showPremiumError(context, error: e, customMessage: e.message);
      return;
    }
    ErrorDisplay.showPremiumError(
      context,
      error: e,
      customMessage: 'Could not place your booking. Please try again.',
    );
  }

  /// PATH 1: Pay Online via Razorpay. The server creates the order for the
  /// amount IT calculates, then books the service after verifying payment.
  Future<void> placeOnlineOrder() async {
    if (!_isFleet && !_isAddressValid()) {
      _showAddressErrorPopup();
      return;
    }
    if (_quote == null) {
      await _loadQuote();
      if (!mounted || _quote == null) return;
    }

    setState(() => isProcessing = true);

    final CreateResult created;
    try {
      created = await BookingApi.create(
        items: widget.serviceKeys,
        cash: false,
        pickupDrop: _addPickupDrop,
        vehicleId: _vehicleId,
        options: widget.bookingOptions,
        fleetRequestId: widget.fleetRequestId,
      );
    } catch (e) {
      _handleCreateError(e);
      return;
    }

    final orderId = created.orderId;
    final keyId = created.keyId;
    final amountPaise = created.amountPaise;
    if (orderId == null || keyId == null || amountPaise == null) {
      _handleCreateError(const BookingApiException('unexpected', 'Couldn\'t start the payment. Please try again.'));
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    final PaymentResult result;
    try {
      result = await getPaymentService().openCheckout(
        orderId: orderId,
        keyId: keyId,
        amountInPaise: amountPaise,
        name: user?.userMetadata?['full_name'] ?? widget.title,
        email: user?.email ?? '',
        contact: user?.phone ?? '',
      );
    } catch (e) {
      _handleCreateError(e);
      return;
    }

    if (!result.success) {
      if (!mounted) return;
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Payment cancelled')),
      );
      return;
    }

    // Razorpay's SDK has documented cases where the ids come back null on
    // a successful charge. The server's webhook books it anyway, so wait
    // for that instead of telling an already-charged customer it failed.
    if (result.orderId == null || result.paymentId == null || result.signature == null) {
      await _finishViaStatus(created.intentId, result.paymentId ?? orderId);
      return;
    }

    await _confirmPayment(
      orderId: result.orderId!,
      paymentId: result.paymentId!,
      signature: result.signature!,
      intentId: created.intentId,
    );
  }

  /// Verifies the payment and creates the booking on the server. Retrying
  /// this never charges the customer again.
  Future<void> _confirmPayment({
    required String orderId,
    required String paymentId,
    required String signature,
    required String intentId,
  }) async {
    if (mounted) setState(() => isProcessing = true);
    try {
      final booking = await BookingApi.confirm(orderId: orderId, paymentId: paymentId, signature: signature);
      if (booking.booked) {
        await _showSuccessAndGoHome();
        return;
      }
      await _finishViaStatus(intentId, paymentId);
    } catch (e) {
      if (!mounted) return;
      setState(() => isProcessing = false);
      final retry = await _showPaidButNotSavedDialog(paymentId);
      if (retry) {
        await _confirmPayment(orderId: orderId, paymentId: paymentId, signature: signature, intentId: intentId);
      }
    }
  }

  /// Polls the server for a booking that's being finished (e.g. by the
  /// Razorpay webhook) — and asks the server to retry a failed save.
  Future<void> _finishViaStatus(String intentId, String paymentRef) async {
    if (mounted) setState(() => isProcessing = true);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final status = await BookingApi.status(intentId);
        if (status.booked) {
          await _showSuccessAndGoHome();
          return;
        }
      } catch (_) {
        // keep waiting — the webhook may still be on its way
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    if (!mounted) return;
    setState(() => isProcessing = false);
    final retry = await _showPaidButNotSavedDialog(paymentRef);
    if (retry) await _finishViaStatus(intentId, paymentRef);
  }

  /// Can't be dismissed by tapping outside — the customer has paid, so they
  /// must choose to retry (never a new charge) or contact support.
  Future<bool> _showPaidButNotSavedDialog(String paymentRef) async {
    if (!mounted) return false;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: _PayColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Payment received',
            style: TextStyle(color: _PayColors.navy, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Your payment went through, but we couldn\'t finish saving your booking — usually a weak connection. '
            'Tap RETRY to try again. You will not be charged again.\n\nPayment ref: $paymentRef',
            style: const TextStyle(color: _PayColors.muted, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CONTACT SUPPORT', style: TextStyle(color: _PayColors.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('RETRY', style: TextStyle(color: _PayColors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (retry == true) return true;
    try {
      await launchUrl(Uri(scheme: 'tel', path: '9353094672'));
    } catch (_) {}
    return false;
  }

  /// PATH 2: Cash on Pickup — the server books it straight away.
  Future<void> placeCashOnPickupOrder() async {
    if (!_isAddressValid()) {
      _showAddressErrorPopup();
      return;
    }
    if (_quote == null) {
      await _loadQuote();
      if (!mounted || _quote == null) return;
    }

    setState(() => isProcessing = true);
    try {
      final created = await BookingApi.create(
        items: widget.serviceKeys,
        cash: true,
        pickupDrop: _addPickupDrop,
        vehicleId: _vehicleId,
        options: widget.bookingOptions,
      );
      if (!created.booked) {
        throw const BookingApiException('unexpected', 'Could not place your booking. Please try again.');
      }
      await _showSuccessAndGoHome();
    } catch (e) {
      _handleCreateError(e);
    }
  }


  // ══════════════════════════════════════════════════════════════════════
  //  UI
  //
  //  Layout: a short scrollable summary (booking, bill, pickup, address)
  //  and a checkout bar pinned to the bottom of the screen with the payment
  //  method, the total and the one action button — so paying never needs
  //  a scroll, whatever the phone size.
  // ══════════════════════════════════════════════════════════════════════

  /// Which method the customer picked in the checkout bar. Only matters
  /// when the server allows Cash on Pickup for this booking.
  bool _payCash = false;

  bool get _codAvailable => _quote?.allowCod == true && !_isFleet;
  bool get _cashSelected => _payCash && _codAvailable;

  int get _pickupFeeCharged {
    final q = _quote;
    if (q == null) return 0;
    return (q.pickupMode == 'locked' || (q.pickupMode == 'optional' && _addPickupDrop)) ? q.pickupFee : 0;
  }

  void _onCheckoutPressed() {
    if (isProcessing || _quote == null) return;
    if (_cashSelected) {
      placeCashOnPickupOrder();
    } else {
      placeOnlineOrder();
    }
  }

  static TextStyle _t(
    double size,
    FontWeight weight,
    Color color, {
    double? spacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      GoogleFonts.manrope(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: height,
        decoration: decoration,
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: _PayColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _PayColors.border),
        boxShadow: [
          BoxShadow(
            color: _PayColors.navy.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text.toUpperCase(), style: _t(11, FontWeight.w800, _PayColors.muted, spacing: 1.4)),
      );

  // ── Header ────────────────────────────────────────────────────────────

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: Material(
              color: _PayColors.surface,
              shape: const CircleBorder(side: BorderSide(color: _PayColors.border)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isProcessing ? null : () => Navigator.pop(context),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.arrow_back_rounded, color: _PayColors.navy, size: 21),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Checkout', style: _t(22, FontWeight.w800, _PayColors.navy, spacing: -0.3)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _PayColors.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_rounded, color: _PayColors.success, size: 14),
                const SizedBox(width: 5),
                Text('Secure', style: _t(11.5, FontWeight.w800, _PayColors.success)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Booking summary (hero) ────────────────────────────────────────────

  Widget _bookingHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_PayColors.blueDark, _PayColors.blue],
        ),
        boxShadow: [
          BoxShadow(
            color: _PayColors.blue.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Soft decorative ring in the corner.
          Positioned(
            right: -36,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.10), width: 18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isFleet ? 'FLEET PAYMENT' : 'YOUR BOOKING',
                style: _t(11, FontWeight.w800, Colors.white.withOpacity(0.72), spacing: 1.6),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _t(21, FontWeight.w800, Colors.white, height: 1.2, spacing: -0.2),
                ),
              ),
              if (widget.duration.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(widget.duration, style: _t(12, FontWeight.w700, Colors.white)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Bill ──────────────────────────────────────────────────────────────

  Widget _billLine(String label, String value, {Color? valueColor, bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? _t(15, FontWeight.w800, _PayColors.navy)
                  : _t(13.5, FontWeight.w600, _PayColors.muted, height: 1.35),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: strong
                ? _t(17, FontWeight.w800, _PayColors.navy)
                : _t(13.5, FontWeight.w700, valueColor ?? _PayColors.navy),
          ),
        ],
      ),
    );
  }

  Widget _billCard() {
    final q = _quote;
    Widget body;

    if (_quoteError != null && q == null) {
      body = Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFFE5484D), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_quoteError!, style: _t(13, FontWeight.w600, _PayColors.navy, height: 1.35)),
          ),
          TextButton(
            onPressed: _loadQuote,
            child: Text('Retry', style: _t(13, FontWeight.w800, _PayColors.blue)),
          ),
        ],
      );
    } else if (q == null) {
      body = Shimmer.fromColors(
        baseColor: const Color(0xFFE9EEF5),
        highlightColor: const Color(0xFFF7F9FC),
        child: Column(
          children: List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: i == 2 ? 90 : 150,
                    height: 12,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                  ),
                  const Spacer(),
                  Container(
                    width: 56,
                    height: 12,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                  ),
                ],
              ),
            );
          }),
        ),
      );
    } else {
      body = Column(
        children: [
          for (final line in q.lines) _billLine(line.name, line.display),
          if (_pickupFeeCharged > 0) _billLine('Doorstep pickup & drop', formatRupees(_pickupFeeCharged)),
          _billLine('Platform fee', 'Free', valueColor: _PayColors.success),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: LayoutBuilder(
              builder: (context, c) {
                // Dashed divider, like a receipt.
                final count = (c.maxWidth / 8).floor();
                return Row(
                  children: List.generate(
                    count,
                    (_) => Expanded(
                      child: Container(
                        height: 1.2,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: _PayColors.border,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _billLine('To pay', _totalPriceDisplay, strong: true),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: _cardDecoration(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: body,
      ),
    );
  }

  // ── Pickup & drop ─────────────────────────────────────────────────────

  /// Pickup & drop: one compact row, pre-selected. On = solid blue card;
  /// off = white card with a blue outline and an "Add" button.
  Widget _pickupDropCard() {
    final active = _addPickupDrop;
    final canToggle = !_pickupLocked && !isProcessing;
    final fg = active ? Colors.white : _PayColors.navy;
    final sub = active ? Colors.white.withOpacity(0.82) : _PayColors.muted;

    return GestureDetector(
      onTap: canToggle ? () => _setPickupDrop(!active) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A6FE8), _PayColors.blueDark],
                )
              : const LinearGradient(colors: [_PayColors.surface, _PayColors.surface]),
          border: Border.all(color: active ? Colors.transparent : _PayColors.blue, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: _PayColors.blue.withOpacity(active ? 0.25 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: active ? Colors.white.withOpacity(0.16) : _PayColors.blueTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_shipping_rounded,
                  color: active ? Colors.white : _PayColors.blue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Doorstep pickup & drop',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(14, FontWeight.w800, fg),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: active ? Colors.white.withOpacity(0.18) : const Color(0xFFFFB020),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _pickupLocked ? 'INCLUDED' : 'RECOMMENDED',
                          style: _t(8.5, FontWeight.w800, active ? Colors.white : _PayColors.navy,
                              spacing: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '+${formatRupees(_pickupDropFee)} · We pick up & drop it back',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(12, FontWeight.w600, sub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _pickupLocked
                ? Icon(Icons.lock_rounded, size: 18, color: active ? Colors.white : _PayColors.blue)
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? Colors.white : _PayColors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Row(
                        key: ValueKey(active),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            active ? Icons.check_rounded : Icons.add_rounded,
                            size: 16,
                            color: active ? _PayColors.blue : Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            active ? 'Added' : 'Add',
                            style: _t(12.5, FontWeight.w800, active ? _PayColors.blue : Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // ── Address ───────────────────────────────────────────────────────────

  Widget _addressCard() {
    final missing = !addressLoading && !_isAddressValid();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isProcessing ? null : _navigateToAddressManagement,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: _cardDecoration().copyWith(
            border: Border.all(
              color: missing ? const Color(0xFFE5484D).withOpacity(0.6) : _PayColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: missing ? const Color(0xFFFDECEC) : _PayColors.blueTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: missing ? const Color(0xFFE5484D) : _PayColors.blue,
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: addressLoading
                    ? Shimmer.fromColors(
                        baseColor: const Color(0xFFE9EEF5),
                        highlightColor: const Color(0xFFF7F9FC),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 180,
                              height: 12,
                              decoration:
                                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 120,
                              height: 12,
                              decoration:
                                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        missing ? 'Add an address for pickup' : selectedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _t(13.5, FontWeight.w700, _PayColors.navy, height: 1.35),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                missing ? 'Add' : 'Change',
                style: _t(13, FontWeight.w800, _PayColors.blue),
              ),
              const Icon(Icons.chevron_right_rounded, color: _PayColors.blue, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Checkout bar (always visible) ─────────────────────────────────────

  Widget _methodOption({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: '$title. $subtitle',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isProcessing ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? _PayColors.blueTint : _PayColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _PayColors.blue : _PayColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? _PayColors.blue : _PayColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(13, FontWeight.w800, selected ? _PayColors.navy : _PayColors.muted),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(10.5, FontWeight.w600, _PayColors.muted),
                      ),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: const Icon(Icons.check_circle_rounded, size: 18, color: _PayColors.blue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkoutBar() {
    final cash = _cashSelected;
    final ready = !isProcessing && _quote != null;
    final buttonLabel = cash ? 'Confirm booking' : 'Pay now';

    return Container(
      decoration: BoxDecoration(
        color: _PayColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: _PayColors.navy.withOpacity(0.10),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_codAvailable) ...[
                Row(
                  children: [
                    _methodOption(
                      selected: !cash,
                      icon: Icons.credit_card_rounded,
                      title: 'Pay online',
                      subtitle: 'UPI · Cards · Netbanking',
                      onTap: () => setState(() => _payCash = false),
                    ),
                    const SizedBox(width: 10),
                    _methodOption(
                      selected: cash,
                      icon: Icons.payments_rounded,
                      title: 'Cash on pickup',
                      subtitle: 'Pay after service',
                      onTap: () => setState(() => _payCash = true),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  // Total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('TOTAL', style: _t(10.5, FontWeight.w800, _PayColors.muted, spacing: 1.4)),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _totalPriceDisplay,
                          key: ValueKey(_totalPriceDisplay),
                          style: _t(22, FontWeight.w800, _PayColors.navy, spacing: -0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Action
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _quote == null ? 0.55 : 1,
                      child: Material(
                        color: Colors.transparent,
                        child: Ink(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_PayColors.blue, _PayColors.blueDark],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _PayColors.blue.withOpacity(0.30),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: ready ? _onCheckoutPressed : null,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: isProcessing
                                    ? const SizedBox(
                                        key: ValueKey('busy'),
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                      )
                                    : Row(
                                        key: ValueKey(buttonLabel),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            cash ? Icons.check_rounded : Icons.lock_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              buttonLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: _t(16, FontWeight.w800, Colors.white, spacing: 0.2),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  cash
                      ? 'Pay in cash once the service is done'
                      : 'Secured by Razorpay · you are never charged twice',
                  key: ValueKey(cash),
                  textAlign: TextAlign.center,
                  style: _t(11, FontWeight.w600, _PayColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Success ───────────────────────────────────────────────────────────

  Widget _successView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_PayColors.blue, _PayColors.blueDark],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _PayColors.blue.withOpacity(0.35),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, size: 66, color: Colors.white),
                ),
                const SizedBox(height: 28),
                Text('Booking confirmed', style: _t(26, FontWeight.w800, _PayColors.navy, spacing: -0.3)),
                const SizedBox(height: 10),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: _t(15, FontWeight.w700, _PayColors.navy, height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  'Taking you to your booking…',
                  textAlign: TextAlign.center,
                  style: _t(13, FontWeight.w600, _PayColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Don't let a back gesture leave mid-payment.
      canPop: !isProcessing && !orderPlaced,
      child: Scaffold(
        backgroundColor: _PayColors.bg,
        bottomNavigationBar: orderPlaced
            ? null
            : Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _checkoutBar(),
                ),
              ),
        body: orderPlaced
            ? _successView()
            : SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        _header(),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _bookingHero(),
                                if (_showPickupDrop) ...[
                                  const SizedBox(height: 14),
                                  _pickupDropCard(),
                                ],
                                const SizedBox(height: 22),
                                _sectionLabel('Bill details'),
                                _billCard(),
                                if (!_isFleet) ...[
                                  const SizedBox(height: 22),
                                  _sectionLabel('Service address'),
                                  _addressCard(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}