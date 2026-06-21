import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> placeOrder() async {
    final supabase =
        Supabase.instance.client;

    final user =
        supabase.auth.currentUser;

    if (user == null) return;

    try {

      /// INSERT BOOKING
      await supabase
          .from('bookings')
          .insert({

        'user_id': user.id,

        'vehicle_id':
            widget.vehicleId,

        'package_name':
            widget.title,

        'package_price':
            widget.price,

        'assigned_admin':
            'admin@gmail.com',
      });

      setState(() {
        orderPlaced = true;
      });

      _controller.forward();

      await Future.delayed(
        const Duration(seconds: 3),
      );

      if (!mounted) return;

      Navigator.popUntil(
        context,
        (route) => route.isFirst,
      );

    } catch (e) {

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content:
              Text(e.toString()),
        ),
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
                        height: 34),

                    /// PAYMENT METHODS
                    const Text(
                      'Payment Method',

                      style: TextStyle(
                        color:
                            Colors.white,

                        fontSize: 22,

                        fontWeight:
                            FontWeight
                                .w900,
                      ),
                    ),

                    const SizedBox(
                        height: 20),

                    _paymentTile(
                      Icons
                          .account_balance_wallet,
                      'UPI / Wallet',
                    ),

                    const SizedBox(
                        height: 14),

                    _paymentTile(
                      Icons.credit_card,
                      'Credit / Debit Card',
                    ),

                    const SizedBox(
                        height: 14),

                    _paymentTile(
                      Icons.currency_rupee,
                      'Cash on Pickup',
                    ),

                    const SizedBox(
                        height: 60),

                    /// CONFIRM BUTTON
                    GestureDetector(
                      onTap: placeOrder,

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

                        child:
                            const Center(
                          child: Text(
                            'CONFIRM & PAY',

                            style:
                                TextStyle(
                              color:
                                  Colors.black,

                              fontSize:
                                  20,

                              fontWeight:
                                  FontWeight
                                      .w900,

                              letterSpacing:
                                  1,
                            ),
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

  Widget _paymentTile(
    IconData icon,
    String title,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color:
            const Color(0xFF111111),

        borderRadius:
            BorderRadius.circular(
                22),

        border: Border.all(
          color:
              const Color(0xFF2A2A2A),
        ),
      ),

      child: Row(
        children: [

          Container(
            width: 52,
            height: 52,

            decoration:
                BoxDecoration(
              color: const Color(
                      0xFFD4A017)
                  .withOpacity(0.1),

              borderRadius:
                  BorderRadius.circular(
                      16),
            ),

            child: Icon(
              icon,

              color:
                  const Color(
                      0xFFD4A017),
            ),
          ),

          const SizedBox(width: 18),

          Text(
            title,

            style:
                const TextStyle(
              color:
                  Colors.white,

              fontSize: 17,

              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}