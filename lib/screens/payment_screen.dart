import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/payment_service_factory.dart';
import 'home_screen.dart';
import 'package:reperi_garage/services/address_service.dart';
import 'package:reperi_garage/screens/address_management_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '/services/admin_assignment_service.dart';  // ✅ NEW: Admin assignment service
import '/services/delivery_partner_assignment_service.dart';

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
  });

  @override
  State<PaymentScreen> createState() =>
      _PaymentScreenState();
}

class _PaymentScreenState
    extends State<PaymentScreen>
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
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Doorstep Pickup & Drop',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '₹100 will be added to your bill for doorstep pickup and drop-off. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _addPickupDrop = true);
            },
            child: const Text(
              'YES, ADD ₹100',
              style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.bold),
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

  late AnimationController
      _controller;

  late Animation<double>
      _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 700),
    );

    _scaleAnimation =
        CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    
    // ── Initialize address service and load default address ──
    _addressService = AddressService();
    _loadDefaultAddress();
  }
  
  /// Load the default address for display
  Future<void> _loadDefaultAddress() async {
    try {
      final defaultAddr = await _addressService.getDefaultAddress();
      
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
    } catch (e) {
      if (mounted) {
        setState(() {
          selectedAddress = 'Error loading address';
          addressLoading = false;
        });
      }
    }
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
        backgroundColor: const Color(0xFF262626),
        title: const Text(
          'Address Required',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Enter valid address to continue to payment',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFFD4A017)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToAddressManagement();
            },
            child: const Text(
              'Add Address',
              style: TextStyle(color: Color(0xFFD4A017)),
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
        
        // ✅ NEW: Get admin ID for load-balanced assignment
        final assignedAdminId = await AdminAssignmentService.getNextAdminId();
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
          'dropoff_address': defaultAddr?['address'] ?? 'Not specified',
          'dropoff_latitude': defaultAddr?['latitude'],
          'dropoff_longitude': defaultAddr?['longitude'],
          
          // ── Customer Details ──
          'customer_name': profileData?['full_name'] ?? 'Unknown',
          'customer_phone': profileData?['phone'],
          
          // ✅ NEW: Admin Assignment (Load-Balanced)
          'assigned_to_admin_id': assignedAdminId,
        });
      }

      await _showSuccessAndGoHome();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
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

        // ✅ NEW: Get admin ID for load-balanced assignment
        final assignedAdminId = await AdminAssignmentService.getNextAdminId();
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
          'dropoff_address': defaultAddr?['address'] ?? 'Not specified',
          'dropoff_latitude': defaultAddr?['latitude'],
          'dropoff_longitude': defaultAddr?['longitude'],

          // ── Customer Details ──
          'customer_name': profileData?['full_name'] ?? 'Unknown',
          'customer_phone': profileData?['phone'],

          // ✅ NEW: Admin Assignment (Load-Balanced)
          'assigned_to_admin_id': assignedAdminId,
        });
      }

      await _showSuccessAndGoHome();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _billRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
      backgroundColor:
          const Color(0xFF262626),

      body: orderPlaced
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ScaleTransition(
                  scale: _scaleAnimation,

                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .center,

                    children: [
                    Container(
                      width: 140,
                      height: 140,

                      decoration:
                          const BoxDecoration(
                        shape:
                            BoxShape.circle,

                        color:
                            Color(
                                0xFFD4A017),
                      ),

                      child: const Icon(
                        Icons.check,
                        size: 80,
                        color:
                            Colors.black,
                      ),
                    ),

                    const SizedBox(
                        height: 30),

                    const Text(
                      'ORDER PLACED',

                      style: TextStyle(
                        color:
                            Colors.white,

                        fontSize: 34,

                        fontWeight:
                            FontWeight
                                .w900,

                        letterSpacing:
                            2,
                      ),
                    ),

                    const SizedBox(
                        height: 14),

                    Text(
                      '${widget.title} booked successfully',

                      style:
                          const TextStyle(
                        color:
                            Colors.white70,

                        fontSize: 16,
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
                  child:
                      SingleChildScrollView(
                    padding:
                        const EdgeInsets.all(
                            24),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,

                      children: [
                    /// TOP BAR
                    Row(
                      children: [

                        GestureDetector(
                          onTap: () {
                            Navigator.pop(
                                context);
                          },

                          child: Container(
                            padding:
                                const EdgeInsets
                                    .all(12),

                            decoration:
                                BoxDecoration(
                              color: const Color(
                                  0xFF262626),

                              borderRadius:
                                  BorderRadius
                                      .circular(
                                          18),
                            ),

                            child: const Icon(
                              Icons.arrow_back,
                              color:
                                  Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(
                            width: 18),

                        const Text(
                          'Confirm Order',

                          style:
                              TextStyle(
                            color:
                                Colors.white,

                            fontSize: 28,

                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                        height: 40),

                    /// PACKAGE CARD
                    Container(
                      padding:
                          const EdgeInsets
                              .all(24),

                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                                0xFF1C1C1C),

                        borderRadius:
                            BorderRadius
                                .circular(
                                    30),

                        border: Border.all(
                          color: const Color(
                              0xFF3A3A3A),
                        ),
                      ),

                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,

                        children: [

                          const Text(
                            'Selected Package',

                            style:
                                TextStyle(
                              color:
                                  Color(
                                      0xFFD4A017),

                              fontSize:
                                  14,

                              letterSpacing:
                                  2,
                            ),
                          ),

                          const SizedBox(
                              height: 18),

                          Text(
                            widget.title,

                            style:
                                const TextStyle(
                              color:
                                  Colors.white,

                              fontSize:
                                  30,

                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),

                          const SizedBox(
                              height: 12),

                          Row(
                            children: [

                              const Icon(
                                Icons.timer,
                                color:
                                    Colors.white70,
                                size: 18,
                              ),

                              const SizedBox(
                                  width: 6),

                              Text(
                                widget
                                    .duration,

                                style:
                                    const TextStyle(
                                  color:
                                      Colors
                                          .white70,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(
                              height: 28),

                          /// BILL BREAKDOWN — package amount, the (always
                          /// free, for now) platform fee, and the optional
                          /// doorstep pickup/drop add-on.
                          _billRow('Package Amount', widget.price),
                          const SizedBox(height: 10),
                          _billRow('Platform Fee', 'Free', valueColor: const Color(0xFF6FCF97)),
                          if (_showPickupDrop) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF262626),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF3A3A3A)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_shipping_outlined, color: Colors.white70, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Doorstep Pickup & Drop',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                        ),
                                        Text(
                                          _addPickupDrop ? '+ ₹$_pickupDropFee added' : 'Not added',
                                          style: TextStyle(
                                            color: _addPickupDrop ? const Color(0xFFD4A017) : Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _addPickupDrop,
                                    onChanged: _setPickupDrop,
                                    activeColor: const Color(0xFFD4A017),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Container(
                            height: 1,
                            color: const Color(0xFF3A3A3A),
                          ),
                          const SizedBox(height: 20),

                          Container(
                            width:
                                double.infinity,

                            padding:
                                const EdgeInsets
                                    .all(22),

                            decoration:
                                BoxDecoration(
                              gradient:
                                  const LinearGradient(
                                colors: [
                                  Color(
                                      0xFFD4A017),
                                  Color(
                                      0xFFF5C842),
                                ],
                              ),

                              borderRadius:
                                  BorderRadius
                                      .circular(
                                          24),
                            ),

                            child: Column(
                              children: [

                                const Text(
                                  'TOTAL PAYABLE',

                                  style:
                                      TextStyle(
                                    color:
                                        Colors.black87,

                                    letterSpacing:
                                        2,

                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(
                                    height:
                                        12),

                                Text(
                                  _totalPriceDisplay,

                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.black,

                                    fontSize:
                                        42,

                                    fontWeight:
                                        FontWeight
                                            .w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.billItems != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(16),
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
                                                  style: const TextStyle(color: Colors.white70),
                                                ),
                                              ),
                                              Text('₹${item['price']}',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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

                    const SizedBox(
                        height: 50),

                    /// ── ADDRESS DISPLAY SECTION ──
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF3A3A3A),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PICKUP ADDRESS',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFFD4A017),
                                size: 16,
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
                                            Color(0xFFD4A017),
                                          ),
                                        ),
                                      )
                                    : Text(
                                        selectedAddress,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: _navigateToAddressManagement,
                                child: const Text(
                                  'Change',
                                  style: TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    /// PAY ONLINE BUTTON
                    GestureDetector(
                      onTap: isProcessing ? null : placeOnlineOrder,

                      child: Container(
                        height: 72,

                        decoration:
                            BoxDecoration(
                          gradient:
                              const LinearGradient(
                            colors: [
                              Color(
                                  0xFFD4A017),
                              Color(
                                  0xFFF5C842),
                            ],
                          ),

                          borderRadius:
                              BorderRadius
                                  .circular(
                                      28),

                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                      0xFFD4A017)
                                  .withOpacity(
                                      0.35),

                              blurRadius:
                                  24,

                              offset:
                                  const Offset(
                                      0,
                                      10),
                            ),
                          ],
                        ),

                        child: Center(
                          child: isProcessing
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.bolt, color: Colors.black, size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'PAY ONLINE',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),

                    if (!widget.onlineOnly) ...[
                    const SizedBox(
                        height: 16),

                    /// CASH ON PICKUP BUTTON
                    GestureDetector(
                      onTap: isProcessing ? null : placeCashOnPickupOrder,

                      child: Container(
                        height: 72,

                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFF3A3A3A),
                          ),
                        ),

                        child: const Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.currency_rupee, color: Colors.white70, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'CASH ON PICKUP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                        height: 40),
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