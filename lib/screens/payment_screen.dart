import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '/services/payment_service_factory.dart';
import 'home_screen.dart';

class PaymentScreen extends StatefulWidget {
  final String title;
  final String price;
  final String duration;
  final String vehicleId;

  const PaymentScreen({
    super.key,
    required this.title,
    required this.price,
    required this.duration,
    required this.vehicleId,
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
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      // Parse the price string into paise (smallest currency unit)
      final priceDigits = widget.price.replaceAll(RegExp(r'[^0-9]'), '');
      final amountInRupees = int.tryParse(priceDigits) ?? 0;
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
        name: user.userMetadata?['full_name'] ?? 'Customer',
        email: user.email ?? '',
        contact: user.phone ?? '',
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

      // STEP 4: Only now insert the booking, since payment is confirmed real
      await supabase.from('bookings').insert({
        'user_id': user.id,
        'vehicle_id': widget.vehicleId,
        'package_name': widget.title,
        'package_price': widget.price,
        'assigned_admin': 'admin@gmail.com',
        'razorpay_order_id': result.orderId,
        'razorpay_payment_id': result.paymentId,
        'payment_status': 'paid',
      });

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
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      await supabase.from('bookings').insert({
        'user_id': user.id,
        'vehicle_id': widget.vehicleId,
        'package_name': widget.title,
        'package_price': widget.price,
        'assigned_admin': 'admin@gmail.com',
        'payment_status': 'cod', // cash on delivery/pickup
      });

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF0A0A0A),

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
                                  0xFF1A1A1A),

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
                                0xFF111111),

                        borderRadius:
                            BorderRadius
                                .circular(
                                    30),

                        border: Border.all(
                          color: const Color(
                              0xFF2A2A2A),
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
                                  widget.price,

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
                        ],
                      ),
                    ),

                    const SizedBox(
                        height: 50),

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

                    const SizedBox(
                        height: 16),

                    /// CASH ON PICKUP BUTTON
                    GestureDetector(
                      onTap: isProcessing ? null : placeCashOnPickupOrder,

                      child: Container(
                        height: 72,

                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFF2A2A2A),
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
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}