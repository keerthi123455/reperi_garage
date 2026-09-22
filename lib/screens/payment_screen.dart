import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/payment_service_factory.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'package:reperi_garage/services/address_service.dart';
import 'package:reperi_garage/screens/address_management_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '/services/admin_assignment_service.dart';
import '/services/delivery_partner_assignment_service.dart';
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
  /// directly; subscriptions, the pollution certificate, and the vehicle
  /// health check turn it off since those aren't a pickup/drop-a-vehicle
  /// service. Also suppressed automatically whenever [billItems] is set
  /// (the fleet flow), which already shows its own itemized total.
  final bool showPickupDropOption;

  /// When [showPickupDropOption] is off and this is true, the default
  /// `bookings` insert still writes `pickupdrop: 'yes'` instead of
  /// omitting the column — for services (like roadside assistance) that
  /// are inherently a pickup, just without the optional ₹100 toggle.
  final bool forcePickupDropYes;

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

  /// When set, this booking always goes to this exact admin username
  /// (e.g. 'emergency_service' for Roadside Assistance) instead of the
  /// usual vehicle-type rotation — see AdminAssignmentService.getNextAdminId.
  final String? forcedAdminUsername;

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
    this.vehicleRequired = true,
    this.forcedAdminUsername,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin {
  bool orderPlaced = false;
  bool isProcessing = false;

  // ── Doorstep pickup & drop add-on ──
  bool _addPickupDrop = false;
  static const int _pickupDropFee = 100;

  bool get _showPickupDrop => widget.showPickupDropOption && widget.billItems == null;

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
    if (widget.vehicleRequired && widget.vehicleId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showVehicleRequiredDialog());
    }

    // ── Initialize address service and load default address ──
    _addressService = AddressService();
    _loadDefaultAddress();
  }

  /// Shown instead of letting the user proceed to checkout with no
  /// vehicle to book the service against.
  void _showVehicleRequiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _PayColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'ADD A VEHICLE TO BOOK THIS SERVICE',
          style: TextStyle(color: _PayColors.navy, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen(autoOpenAddVehicle: true)),
              );
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddressManagementScreen(),
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

  /// Shared success animation + delay + navigation, used by both payment paths
  Future<void> _showSuccessAndGoHome() async {
    setState(() {
      orderPlaced = true;
      isProcessing = false;
    });

    _controller.forward();

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    _goToHomeScreen();
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
      // Fleet payments use the custom callback; consumer bookings use the
      // default insert into `bookings`.
      if (widget.onSuccess != null) {
        await widget.onSuccess!(result.orderId!, result.paymentId!);
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
        final assignedAdminId = await AdminAssignmentService.getNextAdminId(
          vehicleId: widget.vehicleId,
          forcedAdminUsername: widget.forcedAdminUsername,
        );
        // Only assign a delivery partner when there's actually a
        // pickup/drop for one to handle.
        final deliveryPartnerId = _pickupDropYes
            ? await DeliveryPartnerAssignmentService.getNextDeliveryPartnerId('bookings')
            : null;

        await supabase.from('bookings').insert({
          'user_id': user!.id,
          'vehicle_id': widget.vehicleId,
          'package_name': widget.title,
          'package_price': widget.price,
          if (_showPickupDrop)
            'pickupdrop': _addPickupDrop ? 'yes' : 'no'
          else if (widget.forcePickupDropYes)
            'pickupdrop': 'yes',
          if (deliveryPartnerId != null) 'delivery_partner_id': deliveryPartnerId,
          'razorpay_order_id': result.orderId,
          'razorpay_payment_id': result.paymentId,
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
          'customer_phone': profileData?['phone'],

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
        final assignedAdminId = await AdminAssignmentService.getNextAdminId(
          vehicleId: widget.vehicleId,
          forcedAdminUsername: widget.forcedAdminUsername,
        );
        // Only assign a delivery partner when there's actually a
        // pickup/drop for one to handle.
        final deliveryPartnerId = _pickupDropYes
            ? await DeliveryPartnerAssignmentService.getNextDeliveryPartnerId('bookings')
            : null;

        await supabase.from('bookings').insert({
          'user_id': user.id,
          'vehicle_id': widget.vehicleId,
          'package_name': widget.title,
          'package_price': widget.price,
          if (_showPickupDrop)
            'pickupdrop': _addPickupDrop ? 'yes' : 'no'
          else if (widget.forcePickupDropYes)
            'pickupdrop': 'yes',
          if (deliveryPartnerId != null) 'delivery_partner_id': deliveryPartnerId,
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
          'customer_phone': profileData?['phone'],

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
                      child: const Text(
                        'RECOMMENDED',
                        style: TextStyle(
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
                  active
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
          Switch(
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
                      Text(
                        '${widget.title} booked successfully',
                        style: const TextStyle(
                          color: _PayColors.muted,
                          fontSize: 15,
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
