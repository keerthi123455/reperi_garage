import 'package:flutter/material.dart';
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteLoading = false;
        _quoteError = e is BookingApiException ? e.message : 'Couldn\'t load the price. Check your connection and try again.';
      });
    }
  }

  void _setPickupDrop(bool value) {
    if (!value) {
      setState(() => _addPickupDrop = false);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _PayColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Doorstep Pickup & Drop',
          style: TextStyle(color: _PayColors.navy, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${formatRupees(_pickupDropFee)} will be added to your bill for doorstep pickup and drop-off. Continue?',
          style: const TextStyle(color: _PayColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: _PayColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _addPickupDrop = true);
            },
            child: Text(
              'YES, ADD ${formatRupees(_pickupDropFee)}',
              style: const TextStyle(color: _PayColors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
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

  Widget _billRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: _PayColors.muted, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? _PayColors.navy,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// The doorstep pickup/drop toggle — given a bordered, tinted card of its
  /// own (rather than blending into the bill breakdown like the other
  /// rows) plus a small badge, so it reads as the one decision on this
  /// screen worth pausing on instead of another line item to skim past.
  Widget _pickupDropCard() {
    final active = _addPickupDrop;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PayColors.blueTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? _PayColors.blue : _PayColors.blue.withOpacity(0.35),
          width: active ? 1.6 : 1.1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _PayColors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Doorstep Pickup & Drop',
                      style: TextStyle(color: _PayColors.navy, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _PayColors.blue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _pickupLocked ? 'REQUIRED' : 'RECOMMENDED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _pickupLocked
                      ? 'Included — +${formatRupees(_pickupDropFee)} for pickup & drop'
                      : active
                          ? 'Added — +${formatRupees(_pickupDropFee)} for pickup & drop'
                          : 'We collect your vehicle and drop it back — no need to visit the garage',
                  style: TextStyle(
                    color: active ? _PayColors.blue : _PayColors.muted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // lockPickupDropOn services can't turn this off at all — a
          // disabled Switch would just look broken (greyed out, seemingly
          // unresponsive), so it's replaced with a plain lock glyph
          // instead of a Switch entirely.
          _pickupLocked
              ? Icon(Icons.lock_rounded, color: _PayColors.blue, size: 22)
              : Switch(
                  value: _addPickupDrop,
                  onChanged: _setPickupDrop,
                  activeColor: _PayColors.blue,
                ),
        ],
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
    return Scaffold(
      backgroundColor: _PayColors.bg,

      body: orderPlaced
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _PayColors.blue,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'ORDER PLACED',
                        style: TextStyle(
                          color: _PayColors.navy,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '${widget.title} booked successfully',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _PayColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// TOP BAR
                        Row(
                          children: [
                            Semantics(
                              button: true,
                              label: 'Back',
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _PayColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _PayColors.border),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back,
                                    color: _PayColors.navy,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'Confirm Order',
                              style: TextStyle(
                                color: _PayColors.navy,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        /// PACKAGE CARD
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: _PayColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _PayColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: _PayColors.navy.withOpacity(0.05),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SELECTED PACKAGE',
                                style: TextStyle(
                                  color: _PayColors.blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: _PayColors.navy,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, color: _PayColors.muted, size: 17),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.duration,
                                    style: const TextStyle(color: _PayColors.muted, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              /// BILL BREAKDOWN — package amount, the (always
                              /// free, for now) platform fee, and the optional
                              /// doorstep pickup/drop add-on.
                              _billRow('Package Amount', _quote == null ? '—' : formatRupees(_quote!.subtotal)),
                              const SizedBox(height: 10),
                              _billRow('Platform Fee', 'Free', valueColor: _PayColors.success),
                              if (_showPickupDrop) ...[
                                const SizedBox(height: 16),
                                _pickupDropCard(),
                              ],
                              const SizedBox(height: 20),
                              Container(height: 1, color: _PayColors.border),
                              const SizedBox(height: 20),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: _PayColors.blue,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'TOTAL PAYABLE',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        letterSpacing: 1.5,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _totalPriceDisplay,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_quoteLoading) ...[
                                const SizedBox(height: 14),
                                const Center(
                                  child: SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: _PayColors.blue),
                                  ),
                                ),
                              ],
                              if (_quoteError != null) ...[
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: Color(0xFFE5484D), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _quoteError!,
                                        style: const TextStyle(color: _PayColors.navy, fontSize: 13),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _loadQuote,
                                      child: const Text(
                                        'RETRY',
                                        style: TextStyle(color: _PayColors.blue, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if ((_quote?.lines.length ?? 0) > 1) ...[
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _PayColors.bg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _PayColors.border),
                                  ),
                                  child: Column(
                                    children: _quote!.lines
                                        .map((item) => Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item.name,
                                                      style: const TextStyle(color: _PayColors.muted),
                                                    ),
                                                  ),
                                                  Text(item.display,
                                                      style: const TextStyle(
                                                          color: _PayColors.navy, fontWeight: FontWeight.w700)),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        /// ── ADDRESS DISPLAY SECTION ──
                        if (!_isFleet) Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _PayColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _PayColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PICKUP ADDRESS',
                                style: TextStyle(
                                  color: _PayColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: _PayColors.blue,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: addressLoading
                                        ? const SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                _PayColors.blue,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            selectedAddress,
                                            style: const TextStyle(
                                              color: _PayColors.navy,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.2,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: _navigateToAddressManagement,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: _PayColors.blueTint,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _PayColors.blue.withOpacity(0.35)),
                                      ),
                                      child: const Text(
                                        'CHANGE',
                                        style: TextStyle(
                                          color: _PayColors.blue,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        /// PAY ONLINE BUTTON
                        GestureDetector(
                          onTap: (isProcessing || _quote == null) ? null : placeOnlineOrder,
                          child: Container(
                            height: 58,
                            decoration: BoxDecoration(
                              color: _PayColors.blue,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: _PayColors.blue.withOpacity(0.28),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: isProcessing
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.lock_outline_rounded, color: Colors.white, size: 19),
                                        SizedBox(width: 10),
                                        Text(
                                          'PAY SECURELY ONLINE',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),

                        if (_quote?.allowCod == true && !_isFleet) ...[
                          const SizedBox(height: 14),

                          /// CASH ON PICKUP BUTTON
                          GestureDetector(
                            onTap: (isProcessing || _quote == null) ? null : placeCashOnPickupOrder,
                            child: Container(
                              height: 58,
                              decoration: BoxDecoration(
                                color: _PayColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _PayColors.border, width: 1.4),
                              ),
                              child: const Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.currency_rupee_rounded, color: _PayColors.navy, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'CASH ON PICKUP',
                                      style: TextStyle(
                                        color: _PayColors.navy,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 36),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
