import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/payment_service_factory.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'vehicle_bookings_screen.dart';
import 'package:reperi_garage/services/address_service.dart';
import 'package:reperi_garage/screens/address_management_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '/services/admin_assignment_service.dart';
import '/services/delivery_partner_assignment_service.dart';
import '/services/washer_assignment_service.dart';
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
  final String title;
  final String price;
  final String duration;
  final String vehicleId;

  /// Optional — when provided, shows an itemized bill breakdown instead of
  /// a single price row. Used by the fleet "Pay Now" flow.
  final List<Map<String, dynamic>>? billItems;

  /// Optional — when provided, called instead of inserting into `bookings`
  /// after a verified payment. Used by the fleet flow to update
  /// `fleet_pickup_requests` instead. Receives (orderId, paymentId).
  final Future<void> Function(String orderId, String paymentId)? onSuccess;

  /// When true, hides the "Cash on Pickup" option — used for fleet payments,
  /// which are always online-only.
  final bool onlineOnly;

  /// Whether to offer the "Doorstep Pickup & Drop (+₹100)" add-on. Left on
  /// by default for the many package-booking screens that navigate here
  /// directly; subscriptions, the pollution certificate, the vehicle
  /// health check, and Claim Assistance turn it off explicitly since those
  /// aren't an optional-pickup service. [billItems] only controls whether
  /// the bill is shown as a single price or an itemized breakdown — it has
  /// no bearing on pickup/drop, so a screen using an itemized bill (like
  /// Paint Care's add-ons checkout) still needs to set this explicitly if
  /// it wants pickup/drop hidden, the same as any other screen.
  final bool showPickupDropOption;

  /// When [showPickupDropOption] is off and this is true, the default
  /// `bookings` insert still writes `pickupdrop: 'yes'` instead of
  /// omitting the column — for services that are inherently a pickup with
  /// no separate add-on fee at all (the card is never shown), e.g.
  /// pollution/inspection. Contrast with [lockPickupDropOn] below, which
  /// still shows the card and charges the ₹100 fee, just without a way to
  /// turn it off.
  final bool forcePickupDropYes;

  /// Shows the same "Doorstep Pickup & Drop (+₹100)" card as the normal
  /// optional flow, already switched on and billed, but with no Switch to
  /// turn it off — for services where doorstep pickup/drop isn't optional
  /// but is still billed as its own line, e.g. Roadside Assistance (you
  /// can't ask someone stranded with a dead battery to drive the vehicle
  /// in themselves). Leave [showPickupDropOption] at its default (true)
  /// when using this — it still drives the fee/insert logic, this only
  /// removes the ability to deselect it.
  final bool lockPickupDropOn;

  /// Whether this booking needs a real vehicle behind it. True for every
  /// ordinary service booking (the default); set to false for the couple
  /// of flows that legitimately have no single vehicle to book against —
  /// Roadside Assistance and the fleet "Pay Now" flow — which pass an
  /// empty [vehicleId] on purpose. When true and [vehicleId] is empty,
  /// this screen shows an "add a vehicle first" prompt instead of the
  /// payment form, since every package-browsing screen upstream of this
  /// one is allowed to be reached without a vehicle (so people can look
  /// around before adding one) and this is the one place that actually
  /// needs it.
  final bool vehicleRequired;

  /// Called when this screen fills in a vehicle it wasn't given — either
  /// the customer's existing active vehicle, or one they just added from
  /// the "ADD A VEHICLE" prompt. Screens that save the booking themselves
  /// (see [onSuccess]) use it to know which vehicle the booking is for.
  final ValueChanged<String>? onVehicleResolved;

  /// When set, this booking always goes to this exact admin username
  /// (e.g. 'emergency_service' for Roadside Assistance) instead of the
  /// usual vehicle-type rotation — see AdminAssignmentService.getNextAdminId.
  final String? forcedAdminUsername;

  /// Whether a delivery partner should be assigned at all when this is a
  /// pickup/drop booking. True for every ordinary service (the default) —
  /// a real delivery partner drives to the customer, takes the vehicle to
  /// the garage, and brings it back. Roadside Assistance sets this to
  /// false: there's no vehicle being taken anywhere — the emergency_service
  /// admin (a mobile technician) comes to the customer and fixes it on the
  /// spot, so there's no separate "delivery guy" leg for anyone to handle,
  /// even though the doorstep pickup/drop fee still applies (see
  /// [lockPickupDropOn]).
  final bool assignsDeliveryPartner;

  /// Whether a garage admin should be assigned at all. True for every
  /// ordinary service (the default) — there's a real garage doing the
  /// work. The ₹299/₹599 one-time wash packages set this to false: a
  /// doorstep wash is handled entirely by the washer (see [assignsWasher]),
  /// with no garage/admin involved at all, in real use or during Apple
  /// review — unlike [forcedAdminUsername], which still assigns *some*
  /// admin, this assigns none.
  final bool assignsAdmin;

  /// Which section of VehicleBookingsScreen this booking lands in, so the
  /// success flow below can scroll straight to it — 'bookings' (the
  /// default `bookings` table insert path, used by every ordinary package
  /// screen), 'pollution', 'inspection', 'claim', or 'subscription'.
  /// Screens with a custom [onSuccess] writing to a different table pass
  /// the matching value explicitly.
  final String bookingSection;

  /// True only for the one-time wash packages (washing_package_screen.dart's
  /// ₹299/₹599 tiers) — when set, the default `bookings` insert also
  /// assigns a washer via WasherAssignmentService (alternating between
  /// washer 1 and 2 for real customers, or the fixed Apple review washer
  /// for the review account), alongside the usual admin/delivery-partner
  /// assignment. Every other package leaves washer_id unset, same as today.
  final bool assignsWasher;

  const PaymentScreen({
    super.key,
    required this.title,
    required this.price,
    required this.duration,
    required this.vehicleId,
    this.billItems,
    this.onSuccess,
    this.onlineOnly = false,
    this.showPickupDropOption = true,
    this.forcePickupDropYes = false,
    this.lockPickupDropOn = false,
    this.assignsDeliveryPartner = true,
    this.assignsAdmin = true,
    this.assignsWasher = false,
    this.vehicleRequired = true,
    this.onVehicleResolved,
    this.forcedAdminUsername,
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

  // ── Doorstep pickup & drop add-on ──
  bool _addPickupDrop = false;
  static const int _pickupDropFee = 100;

  bool get _showPickupDrop => widget.showPickupDropOption;

  /// Whether this booking is actually being picked up/dropped off — used to
  /// decide whether a delivery partner should be assigned at all. A "no"
  /// (or no pickup/drop concept for this booking) means there's nothing for
  /// a delivery partner to do.
  bool get _pickupDropYes {
    if (_showPickupDrop) return _addPickupDrop;
    return widget.forcePickupDropYes;
  }

  /// Null when [PaymentScreen.price] isn't a plain "₹NNN" amount (e.g. a
  /// "Get Quote"/"Custom Quote" placeholder) — the pickup/drop fee and the
  /// computed total only make sense when there's a real number to add to.
  int? get _baseAmountRupees {
    final digits = widget.price.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  int? get _totalAmountRupees {
    final base = _baseAmountRupees;
    if (base == null) return null;
    return base + (_addPickupDrop ? _pickupDropFee : 0);
  }

  String get _totalPriceDisplay {
    final total = _totalAmountRupees;
    return total != null ? '₹$total' : widget.price;
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
        content: const Text(
          '₹100 will be added to your bill for doorstep pickup and drop-off. Continue?',
          style: TextStyle(color: _PayColors.muted),
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
            child: const Text(
              'YES, ADD ₹100',
              style: TextStyle(color: _PayColors.blue, fontWeight: FontWeight.bold),
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

    // lockPickupDropOn services (Roadside Assistance) show the pickup/drop
    // card already switched on, with no way to turn it back off — see
    // _pickupDropCard's Switch below.
    if (widget.lockPickupDropOn) _addPickupDrop = true;

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
      if (widget.billItems == null &&
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

  /// PATH 1: Pay Online via Razorpay
  Future<void> placeOnlineOrder() async {
    // ── VALIDATION: Check if address is valid ──
    if (!_isAddressValid()) {
      _showAddressErrorPopup();
      return;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    // Fleet payments don't use Supabase Auth (fleet operators log in via
    // a separate table-based system), so only require a signed-in consumer
    // user for the default (non-fleet) booking flow.
    if (widget.onSuccess == null && user == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      // Package amount plus the doorstep pickup/drop fee if the customer
      // added it — falls back to the raw price string's digits when
      // there's no add-on to fold in.
      final amountInRupees = _totalAmountRupees ?? 0;
      final amountInPaise = amountInRupees * 100;

      if (amountInPaise <= 0) {
        throw Exception('Invalid price: ${widget.price}');
      }

      // STEP 1: Create Razorpay order via Edge Function
      final orderResponse = await supabase.functions.invoke(
        'create-razorpay-order',
        body: {
          'amount': amountInPaise,
          'currency': 'INR',
          'receipt': 'booking_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (orderResponse.status != 200) {
        throw Exception('Failed to create order: ${orderResponse.data}');
      }

      final orderData = orderResponse.data as Map<String, dynamic>;
      final orderId = orderData['orderId'] as String;
      final keyId = orderData['keyId'] as String;

      // STEP 2: Open Razorpay checkout
      final paymentService = getPaymentService();
      final result = await paymentService.openCheckout(
        orderId: orderId,
        keyId: keyId,
        amountInPaise: amountInPaise,
        name: user?.userMetadata?['full_name'] ?? widget.title,
        email: user?.email ?? '',
        contact: user?.phone ?? '',
      );

      if (!result.success) {
        if (!mounted) return;
        setState(() {
          isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? 'Payment cancelled')),
        );
        return;
      }

      // STEP 3: Verify payment signature via Edge Function
      final verifyResponse = await supabase.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'razorpay_order_id': result.orderId,
          'razorpay_payment_id': result.paymentId,
          'razorpay_signature': result.signature,
        },
      );

      final verifyData = verifyResponse.data as Map<String, dynamic>;
      final isVerified = verifyData['verified'] == true;

      if (!isVerified) {
        throw Exception('Payment verification failed');
      }

      // STEP 4: Only now record the payment, since it's confirmed real.
      // Isolated in its own try/catch (rather than sharing the one above)
      // because Razorpay has already charged the customer by this point —
      // a failure saving the record (dropped connection, DB hiccup) is a
      // different situation than a failed payment. It must never be
      // treated the same way, since tapping "try again" on the generic
      // failure message would run a brand-new Razorpay checkout and charge
      // them a second time. Instead this says plainly that the charge went
      // through, and its retry re-attempts only this save with the same
      // orderId/paymentId — never a new charge.
      // Razorpay's SDK has documented cases where orderId/paymentId come
      // back null on the success callback even though the charge went
      // through — force-unwrapping here used to throw straight into the
      // generic "Could not place your booking" catch below, telling an
      // already-charged customer their payment failed. Show the honest
      // "we couldn't save it" message instead, with whatever reference we
      // do have.
      if (result.orderId == null || result.paymentId == null) {
        if (!mounted) return;
        setState(() {
          isProcessing = false;
        });
        ErrorDisplay.showPremiumError(
          context,
          error: Exception('Missing payment reference after a verified payment'),
          customMessage:
              'Your payment went through, but we couldn\'t save your booking (ref: ${result.paymentId ?? result.orderId ?? "unavailable"}). Please contact support with that reference.',
        );
        return;
      }
      final orderIdForRecord = result.orderId!;
      final paymentIdForRecord = result.paymentId!;

      Future<void> recordBooking() async {
        try {
          // Fleet payments use the custom callback; consumer bookings use
          // the default insert into `bookings`.
          if (widget.onSuccess != null) {
            await widget.onSuccess!(orderIdForRecord, paymentIdForRecord);
          } else {
            // ── Get location and customer details ──
            final addressService = AddressService();
            final defaultAddr = await addressService.getDefaultAddress();

            // Get customer details from profiles
            Map<String, dynamic>? profileData;
            try {
              profileData = await supabase
                  .from('profiles')
                  .select('full_name, phone')
                  .eq('id', user!.id)
                  .single();
            } catch (e) {
              // Profile might not exist, continue with null values
            }

            // Get admin ID — forcedAdminUsername (e.g. Roadside
            // Assistance -> 'emergency_service') always wins; otherwise scoped
            // to this vehicle's type (two-wheeler bookings only rotate among
            // two-wheeler admins, four-wheeler among four-wheeler admins).
            // assignsAdmin: false (the wash packages) skips this entirely —
            // no garage is involved, so no admin should ever be assigned,
            // in real use or during Apple review.
            final assignedAdminId = widget.assignsAdmin
                ? await AdminAssignmentService.getNextAdminId(
                    vehicleId: _vehicleId,
                    forcedAdminUsername: widget.forcedAdminUsername,
                  )
                : null;
            // Only assign a delivery partner when there's actually a
            // pickup/drop for one to handle, and this service actually uses
            // one (Roadside Assistance sets assignsDeliveryPartner: false —
            // the forced emergency_service admin handles it on-site, no
            // separate delivery leg for anyone else to drive).
            final deliveryPartnerId = (_pickupDropYes && widget.assignsDeliveryPartner)
                ? await DeliveryPartnerAssignmentService.getNextDeliveryPartnerId('bookings')
                : null;
            final washerId = widget.assignsWasher
                ? await WasherAssignmentService.getNextWasherId(
                    'bookings',
                    customerEmail: user!.email,
                  )
                : null;

            await supabase.from('bookings').insert({
              'user_id': user!.id,
              // Roadside Assistance passes an empty vehicleId on purpose
              // (vehicleRequired: false — this booking isn't tied to a
              // specific vehicle). Writing '' into a uuid column throws a
              // Postgres "invalid input syntax for type uuid" error —
              // exactly what was turning a successful payment into a
              // "couldn't save your booking" failure. Omit the column
              // entirely instead, leaving it NULL.
              if (_vehicleId.isNotEmpty) 'vehicle_id': _vehicleId,
              'package_name': widget.title,
              'package_price': widget.price,
              if (_showPickupDrop)
                'pickupdrop': _addPickupDrop ? 'yes' : 'no'
              else if (widget.forcePickupDropYes)
                'pickupdrop': 'yes',
              if (deliveryPartnerId != null) 'delivery_partner_id': deliveryPartnerId,
              if (washerId != null) 'washer_id': washerId,
              'razorpay_order_id': orderIdForRecord,
              'razorpay_payment_id': paymentIdForRecord,
              'payment_status': 'paid',

              // ── Location Data ──
              'pickup_address': defaultAddr?['address'] ?? 'Not specified',
              'pickup_latitude': defaultAddr?['latitude'],
              'pickup_longitude': defaultAddr?['longitude'],
              'pickup_address_name': defaultAddr?['name'],
              'dropoff_address': defaultAddr?['address'] ?? 'Not specified',
              'dropoff_latitude': defaultAddr?['latitude'],
              'dropoff_longitude': defaultAddr?['longitude'],
              'dropoff_address_name': defaultAddr?['name'],

              // ── Customer Details ──
              'customer_name': profileData?['full_name'] ?? 'Unknown',
              'customer_phone': profileData?['phone'] ??
              // Emergency bookings must always carry a reachable number
              // for the on-site technician — fall back to the login phone.
              (widget.forcedAdminUsername != null
                  ? (user?.phone?.isNotEmpty == true
                      ? user!.phone
                      : user?.userMetadata?['phone'] as String?)
                  : null),

              // Admin Assignment (Load-Balanced)
              'assigned_to_admin_id': assignedAdminId,
            });
          }

          await _showSuccessAndGoHome();
        } catch (e) {
          if (!mounted) return;
          setState(() {
            isProcessing = false;
          });
          ErrorDisplay.showPremiumError(
            context,
            error: e,
            customMessage:
                'Your payment went through, but we couldn\'t save your booking (ref: $paymentIdForRecord). Tap retry, or contact support with that reference if it keeps failing.',
            onRetry: recordBooking,
          );
        }
      }

      await recordBooking();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isProcessing = false;
      });
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not place your booking. Please try again.',
      );
    }
  }

  /// PATH 2: Cash on Pickup, no online payment
  Future<void> placeCashOnPickupOrder() async {
    // ── VALIDATION: Check if address is valid ──
    if (!_isAddressValid()) {
      _showAddressErrorPopup();
      return;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      // Fleet payments / subscriptions & compliance bookings use the
      // custom callback, same as the online-payment path — otherwise a
      // Cash-on-Pickup subscription booking would land in `bookings`
      // instead of its own table.
      if (widget.onSuccess != null) {
        await widget.onSuccess!('COD', 'COD');
      } else {
        // ── Get location and customer details ──
        final addressService = AddressService();
        final defaultAddr = await addressService.getDefaultAddress();

        // Get customer details from profiles
        Map<String, dynamic>? profileData;
        try {
          profileData = await supabase
              .from('profiles')
              .select('full_name, phone')
              .eq('id', user.id)
              .single();
        } catch (e) {
          // Profile might not exist, continue with null values
        }

        // Get admin ID — forcedAdminUsername (e.g. Roadside
        // Assistance -> 'emergency_service') always wins; otherwise scoped
        // to this vehicle's type (two-wheeler bookings only rotate among
        // two-wheeler admins, four-wheeler among four-wheeler admins).
        // assignsAdmin: false (the wash packages) skips this entirely — no
        // garage is involved, so no admin should ever be assigned, in real
        // use or during Apple review.
        final assignedAdminId = widget.assignsAdmin
            ? await AdminAssignmentService.getNextAdminId(
                vehicleId: _vehicleId,
                forcedAdminUsername: widget.forcedAdminUsername,
              )
            : null;
        // Only assign a delivery partner when there's actually a
        // pickup/drop for one to handle, and this service actually uses one
        // (Roadside Assistance sets assignsDeliveryPartner: false — the
        // forced emergency_service admin handles it on-site, no separate
        // delivery leg for anyone else to drive).
        final deliveryPartnerId = (_pickupDropYes && widget.assignsDeliveryPartner)
            ? await DeliveryPartnerAssignmentService.getNextDeliveryPartnerId('bookings')
            : null;
        final washerId = widget.assignsWasher
            ? await WasherAssignmentService.getNextWasherId(
                'bookings',
                customerEmail: user.email,
              )
            : null;

        await supabase.from('bookings').insert({
          'user_id': user.id,
          // Same reasoning as the online-payment insert above — omit
          // rather than write '' into a uuid column for the no-vehicle
          // flows (Roadside Assistance).
          if (_vehicleId.isNotEmpty) 'vehicle_id': _vehicleId,
          'package_name': widget.title,
          'package_price': widget.price,
          if (_showPickupDrop)
            'pickupdrop': _addPickupDrop ? 'yes' : 'no'
          else if (widget.forcePickupDropYes)
            'pickupdrop': 'yes',
          if (deliveryPartnerId != null) 'delivery_partner_id': deliveryPartnerId,
          if (washerId != null) 'washer_id': washerId,
          'payment_status': 'cod', // cash on delivery/pickup

          // ── Location Data ──
          'pickup_address': defaultAddr?['address'] ?? 'Not specified',
          'pickup_latitude': defaultAddr?['latitude'],
          'pickup_longitude': defaultAddr?['longitude'],
          'pickup_address_name': defaultAddr?['name'],
          'dropoff_address': defaultAddr?['address'] ?? 'Not specified',
          'dropoff_latitude': defaultAddr?['latitude'],
          'dropoff_longitude': defaultAddr?['longitude'],
          'dropoff_address_name': defaultAddr?['name'],

          // ── Customer Details ──
          'customer_name': profileData?['full_name'] ?? 'Unknown',
          'customer_phone': profileData?['phone'] ??
              // Emergency bookings must always carry a reachable number
              // for the on-site technician — fall back to the login phone.
              (widget.forcedAdminUsername != null
                  ? (user?.phone?.isNotEmpty == true
                      ? user!.phone
                      : user?.userMetadata?['phone'] as String?)
                  : null),

          // Admin Assignment (Load-Balanced)
          'assigned_to_admin_id': assignedAdminId,
        });
      }

      await _showSuccessAndGoHome();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isProcessing = false;
      });
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not place your booking. Please try again.',
      );
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
                        widget.lockPickupDropOn ? 'REQUIRED' : 'RECOMMENDED',
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
                  widget.lockPickupDropOn
                      ? 'Included — +₹$_pickupDropFee for pickup & drop'
                      : active
                          ? 'Added — +₹$_pickupDropFee for pickup & drop'
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
          widget.lockPickupDropOn
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
                              _billRow('Package Amount', widget.price),
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
                              if (widget.billItems != null) ...[
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _PayColors.bg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _PayColors.border),
                                  ),
                                  child: Column(
                                    children: widget.billItems!
                                        .map((item) => Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item['name']?.toString() ?? '',
                                                      style: const TextStyle(color: _PayColors.muted),
                                                    ),
                                                  ),
                                                  Text('₹${item['price']}',
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
                        Container(
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
                          onTap: isProcessing ? null : placeOnlineOrder,
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

                        if (!widget.onlineOnly) ...[
                          const SizedBox(height: 14),

                          /// CASH ON PICKUP BUTTON
                          GestureDetector(
                            onTap: isProcessing ? null : placeCashOnPickupOrder,
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
