import 'package:flutter/material.dart';
import 'payment_screen.dart';
class ServiceDetailsScreen extends StatelessWidget {
  final String title;
  final String image;
  final String price;
  final String duration;
  final String vehicleId;
  final List<String> services;
  final List<String> benefits;

  const ServiceDetailsScreen({
    super.key,
    required this.title,
    required this.vehicleId,
    required this.image,
    required this.price,
    required this.duration,
    required this.services,
    required this.benefits,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: Stack(
        children: [
          /// HERO IMAGE
          SizedBox(
            height: 420,
            width: double.infinity,

            child: Stack(
              fit: StackFit.expand,

              children: [
                Image.asset(
                  image,
                  fit: BoxFit.cover,
                ),

                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,

                      colors: [
                        Colors.black
                            .withOpacity(0.2),

                        Colors.black
                            .withOpacity(0.95),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          /// CONTENT
          /// CONTENT
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                  /// TOP BAR
                  Padding(
                    padding:
                        const EdgeInsets.all(20),

                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,

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
                              color: Colors
                                  .white
                                  .withOpacity(
                                      0.1),

                              shape:
                                  BoxShape.circle,
                            ),

                            child: const Icon(
                              Icons.arrow_back,
                              color:
                                  Colors.white,
                            ),
                          ),
                        ),

                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),

                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                                    0xFFFFC107),

                            borderRadius:
                                BorderRadius
                                    .circular(
                                        30),
                          ),

                          child: const Text(
                            'MOST POPULAR',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 140),

                  /// TITLE
                  Padding(
                    padding:
                        const EdgeInsets
                            .symmetric(
                                horizontal:
                                    24),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,

                      children: [
                        Text(
                          title,
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontSize: 42,
                            height: 1,
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),

                        const SizedBox(
                            height: 20),

                        Text(
                          price,
                          style:
                              const TextStyle(
                            color:
                                Color(
                                    0xFFFFC107),
                            fontSize: 52,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),

                        const SizedBox(
                            height: 12),

                        Row(
                          children: [
                            const Icon(
                              Icons.timer,
                              color: Colors
                                  .white70,
                              size: 18,
                            ),

                            const SizedBox(
                                width: 6),

                            Text(
                              duration,
                              style:
                                  const TextStyle(
                                color: Colors
                                    .white70,
                                fontSize: 16,
                              ),
                            ),

                            const SizedBox(
                                width: 20),

                            const Icon(
                              Icons.local_shipping,
                              color: Colors
                                  .white70,
                              size: 18,
                            ),

                            const SizedBox(
                                width: 6),

                            const Text(
                              'Pickup Included',
                              style:
                                  TextStyle(
                                color: Colors
                                    .white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  /// GLASS CARD
                  Container(
                    margin:
                        const EdgeInsets
                            .all(20),

                    padding:
                        const EdgeInsets
                            .all(24),

                    decoration:
                        BoxDecoration(
                      color: Colors.white
                          .withOpacity(
                              0.08),

                      borderRadius:
                          BorderRadius
                              .circular(30),

                      border: Border.all(
                        color: Colors
                            .white
                            .withOpacity(
                                0.08),
                      ),
                    ),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,

                      children: [
                        const Text(
                          'Included Services',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize: 24,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),

                        const SizedBox(
                            height: 24),

                        Wrap(
                          spacing: 12,
                          runSpacing: 12,

                          children: services
                              .map(
                                (s) =>
                                    Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal:
                                        16,
                                    vertical:
                                        12,
                                  ),

                                  decoration:
                                      BoxDecoration(
                                    color: Colors
                                        .white
                                        .withOpacity(
                                            0.08),

                                    borderRadius:
                                        BorderRadius.circular(
                                            18),
                                  ),

                                  child:
                                      Text(
                                    '✓ $s',
                                    style:
                                        const TextStyle(
                                      color: Colors
                                          .white,
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),

                        const SizedBox(
                            height: 36),

                        const Text(
                          'Benefits',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontSize: 24,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),

                        const SizedBox(
                            height: 22),

                        Column(
                          children: benefits
                              .map(
                                (b) => Padding(
                                  padding:
                                      const EdgeInsets.only(
                                          bottom:
                                              18),

                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons
                                            .verified,
                                        color: Color(
                                            0xFFFFC107),
                                      ),

                                      const SizedBox(
                                          width:
                                              12),

                                      Expanded(
                                        child:
                                            Text(
                                          b,
                                          style:
                                              const TextStyle(
                                            color:
                                                Colors.white,
                                            fontSize:
                                                16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                 const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ),
        ),

          /// BOOK BUTTON
Positioned(
  left: 0,
  right: 0,
  bottom: 20,

  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GestureDetector(
    onTap: () {

      Navigator.push(
        context,

        MaterialPageRoute(
          builder: (_) => PaymentScreen(
  title: title,
  price: price,
  duration: duration,

  vehicleId:
      vehicleId,
),
        ),
      );

    },

    child: Container(
      height: 72,

      decoration: BoxDecoration(
        gradient:
            const LinearGradient(
          colors: [
            Color(0xFFD4A017),
            Color(0xFFF5C842),
          ],
        ),

        borderRadius:
            BorderRadius.circular(
                28),

        boxShadow: [
          BoxShadow(
            color: const Color(
                    0xFFD4A017)
                .withOpacity(0.35),

            blurRadius: 24,

            offset:
                const Offset(0, 10),
          ),
        ],
      ),

      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [
          const Icon(
            Icons.calendar_month,
            color: Colors.black,
            size: 26,
          ),

          const SizedBox(width: 12),

          Text(
            'BOOK NOW • $price',

            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight:
                  FontWeight.w900,

              letterSpacing: 1,
            ),
          ),
        ],
      ),
    ),
  ),
      ),
    ),
  ),
),
        ],
      ),
    );
  }
}