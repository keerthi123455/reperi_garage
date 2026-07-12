import 'package:flutter/material.dart';

import 'payment_screen.dart';
import '../services/catalog_service.dart';

class BookServiceScreen extends StatefulWidget {

  final Map<String, dynamic> vehicle;

  const BookServiceScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<BookServiceScreen> createState() =>
      _BookServiceScreenState();
}

class _BookServiceScreenState
    extends State<BookServiceScreen> {

  bool pickupEnabled = true;

  int selectedIndex = 0;

  List<Map<String, dynamic>> services = [

    {
      "title": "Quick Service",
      "price": "₹1999",
      "time": "90 mins",
      "icon": Icons.build_rounded,

      "features": [

        "Engine oil replacement",
        "Oil filter cleaning",
        "Brake inspection",
        "Fluid top-up",
        "Battery check",
      ],

      "details":
          "A fast maintenance package designed for regular upkeep and smoother daily performance.",
    },

    {
      "title": "Full Service",
      "price": "₹4999",
      "time": "4 hrs",
      "icon": Icons.car_repair,

      "features": [

        "Complete engine inspection",
        "Full oil replacement",
        "Air filter replacement",
        "Wheel balancing",
        "Suspension check",
        "Brake servicing",
      ],

      "details":
          "Comprehensive servicing package covering all major systems of the vehicle for peak performance.",
    },

    {
      "title": "AC Service",
      "price": "₹2499",
      "time": "2 hrs",
      "icon": Icons.ac_unit_rounded,

      "features": [

        "AC gas refill",
        "Cooling efficiency check",
        "Cabin filter cleaning",
        "Vent sanitization",
        "Leak inspection",
      ],

      "details":
          "Deep AC inspection and cooling optimization to ensure maximum comfort and airflow.",
    },

    {
      "title": "Engine Diagnostics",
      "price": "₹1499",
      "time": "45 mins",
      "icon": Icons.settings,

      "features": [

        "OBD scan",
        "Engine health report",
        "Sensor diagnostics",
        "Error code detection",
        "Performance analysis",
      ],

      "details":
          "Advanced computer diagnostics to identify hidden engine and electrical issues.",
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchServiceData();
  }

  Future<void> _fetchServiceData() async {
    try {
      final rows = await CatalogService.fetchByCategory('Book Service');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      const keyOrder = [
        'book_quick_service',
        'book_full_service',
        'book_ac_service',
        'book_engine_diagnostics',
      ];

      setState(() {
        for (var i = 0; i < keyOrder.length && i < services.length; i++) {
          final row = byKey[keyOrder[i]];
          if (row != null) {
            services[i]['price'] = row['price'];
            services[i]['time'] = row['duration'];
            services[i]['details'] = row['details'] ?? services[i]['details'];
            services[i]['features'] = List<String>.from(row['services']);
          }
        }
      });
    } catch (e) {
      // Keep the hardcoded fallback values above if the fetch fails.
    }
  }

  @override
  Widget build(BuildContext context) {

    final selectedService =
        services[selectedIndex];

    return Scaffold(

      backgroundColor:
          const Color(0xFF050505),

      body: SafeArea(
  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              /// HERO
              Stack(

                children: [

                  SizedBox(

                    height: 360,
                    width: double.infinity,

                    child: Image.asset(

                      'assets/images/tile_book_service.jpg',

                      fit: BoxFit.cover,
                    ),
                  ),

                  Container(

                    height: 360,

                    decoration:
                        BoxDecoration(

                      gradient:
                          LinearGradient(

                        begin:
                            Alignment.bottomCenter,

                        end:
                            Alignment.topCenter,

                        colors: [

                          Colors.black,

                          Colors.black
                              .withOpacity(
                                  0.2),
                        ],
                      ),
                    ),
                  ),

                  Padding(

                    padding:
                        const EdgeInsets.all(
                            24),

                    child: Column(

                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,

                      children: [

                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(
                            height: 20),

                        Container(

                          padding:
                              const EdgeInsets.symmetric(

                            horizontal: 14,
                            vertical: 8,
                          ),

                          decoration:
                              BoxDecoration(

                            color: const Color(
                                    0xFFD4A017)
                                .withOpacity(
                                    0.12),

                            borderRadius:
                                BorderRadius.circular(
                                    20),
                          ),

                          child:
                              const Text(

                            'PREMIUM CARE',

                            style:
                                TextStyle(

                              color:
                                  Color(
                                      0xFFD4A017),

                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ),

                        const SizedBox(
                            height: 26),

                        const Text(

                          'BOOK\nSERVICE',

                          style: TextStyle(

                            color:
                                Colors.white,

                            fontSize: 52,

                            fontWeight:
                                FontWeight.w900,

                            height: 0.95,
                          ),
                        ),

                        const SizedBox(
                            height: 16),

                        const Text(

                          'Professional servicing for your vehicle with premium quality support.',

                          style: TextStyle(

                            color:
                                Colors.white70,

                            fontSize: 18,

                            height: 1.5,
                          ),
                        ),

                        const SizedBox(
                            height: 26),

                        Wrap(

                          spacing: 10,
                          runSpacing: 10,

                          children: [

                            _chip(
                                'LIVE TRACKING'),

                            _chip(
                                'GENUINE PARTS'),

                            _chip(
                                'SERVICE WARRANTY'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(
                  height: 28),

              /// VEHICLE CARD
              Padding(

                padding:
                    const EdgeInsets.symmetric(
                        horizontal: 18),

                child: Container(

                  padding:
                      const EdgeInsets.all(
                          22),

                  decoration:
                      BoxDecoration(

                    color:
                        const Color(
                            0xFF111111),

                    borderRadius:
                        BorderRadius.circular(
                            28),

                    border: Border.all(

                      color:
                          const Color(
                              0xFF2A2A2A),
                    ),
                  ),

                  child: Row(

                    children: [

                      Container(

                        width: 72,
                        height: 72,

                        decoration:
                            BoxDecoration(

                          color: const Color(
                                  0xFFD4A017)
                              .withOpacity(
                                  0.1),

                          borderRadius:
                              BorderRadius.circular(
                                  22),
                        ),

                        child:
                            const Icon(

                          Icons
                              .directions_car,

                          color:
                              Color(
                                  0xFFD4A017),

                          size: 36,
                        ),
                      ),

                      const SizedBox(
                          width: 18),

                      Expanded(

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            Text(

                              (widget.vehicle['car_model'] ?? '')
                                  .toString(),

                              style:
                                  const TextStyle(

                                color:
                                    Colors.white,

                                fontSize:
                                    24,

                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),

                            const SizedBox(
                                height: 6),

                            Text(

                              (widget.vehicle['car_brand'] ?? '')
                                  .toString(),

                              style:
                                  const TextStyle(

                                color:
                                    Colors.white54,
                              ),
                            ),

                            const SizedBox(
                                height: 6),

                            Text(

                              (widget.vehicle['car_number'] ?? '')
                                  .toString(),

                              style:
                                  const TextStyle(

                                color:
                                    Color(
                                        0xFFD4A017),

                                fontWeight:
                                    FontWeight.w700,

                                letterSpacing:
                                    2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                  height: 34),

              /// SERVICES
              const Padding(

                padding:
                    EdgeInsets.symmetric(
                        horizontal: 18),

                child: Text(

                  'SELECT SERVICE',

                  style: TextStyle(

                    color:
                        Colors.white,

                    fontSize: 28,

                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ),

              const SizedBox(
                  height: 18),

              SizedBox(

                height: 200,

                child: ListView.builder(

                  scrollDirection:
                      Axis.horizontal,

                  padding:
                      const EdgeInsets.symmetric(
                          horizontal: 18),

                  itemCount:
                      services.length,

                  itemBuilder:
                      (context, index) {

                    final service =
                        services[index];

                    final selected =
                        selectedIndex ==
                            index;

                    return GestureDetector(

                      onTap: () {

                        setState(() {

                          selectedIndex =
                              index;
                        });
                      },

                      child: Container(

                        width: 190,

                        margin:
                            const EdgeInsets.only(
                                right: 14),

                        padding:
                            const EdgeInsets.all(
                                18),

                        decoration:
                            BoxDecoration(

                          gradient:
                              LinearGradient(

                            colors: [

                              selected

                                  ? const Color(
                                      0xFF2A1E00)

                                  : const Color(
                                      0xFF141414),

                              const Color(
                                  0xFF0A0A0A),
                            ],
                          ),

                          borderRadius:
                              BorderRadius.circular(
                                  28),

                          border: Border.all(

                            color: selected

                                ? const Color(
                                    0xFFD4A017)

                                : const Color(
                                    0xFF2A2A2A),
                          ),
                        ),

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            Container(

                              padding:
                                  const EdgeInsets.all(
                                      10),

                              decoration:
                                  BoxDecoration(

                                color: const Color(
                                        0xFFD4A017)
                                    .withOpacity(
                                        0.12),

                                borderRadius:
                                    BorderRadius.circular(
                                        14),
                              ),

                              child: Icon(

                                service['icon']
                                    as IconData,

                                color:
                                    const Color(
                                        0xFFD4A017),
                              ),
                            ),

                            const Spacer(),

                            Text(

                              service['title']
                                  as String,

                              style:
                                  const TextStyle(

                                color:
                                    Colors.white,

                                fontSize:
                                    18,

                                fontWeight:
                                    FontWeight.w900,
                              ),
                            ),

                            const SizedBox(
                                height: 8),

                            Text(

                              service['price']
                                  as String,

                              style:
                                  const TextStyle(

                                color:
                                    Color(
                                        0xFFD4A017),

                                fontWeight:
                                    FontWeight.w900,

                                fontSize:
                                    20,
                              ),
                            ),

                            const SizedBox(
                                height: 4),

                            Text(

                              service['time']
                                  as String,

                              style:
                                  const TextStyle(

                                color:
                                    Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(
                  height: 34),

              /// FEATURES
              Padding(

                padding:
                    const EdgeInsets.symmetric(
                        horizontal: 18),

                child: Container(

                  width: double.infinity,

                  padding:
                      const EdgeInsets.all(
                          24),

                  decoration:
                      BoxDecoration(

                    color:
                        const Color(
                            0xFF111111),

                    borderRadius:
                        BorderRadius.circular(
                            28),
                  ),

                  child: Column(

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      const Text(

                        'SERVICE FEATURES',

                        style: TextStyle(

                          color:
                              Color(
                                  0xFFD4A017),

                          fontSize: 13,

                          fontWeight:
                              FontWeight.bold,

                          letterSpacing:
                              2,
                        ),
                      ),

                      const SizedBox(
                          height: 20),

                      ...(selectedService[
                                  'features']
                              as List<String>)
                          .map(

                        (feature) {

                          return Padding(

                            padding:
                                const EdgeInsets.only(
                                    bottom: 14),

                            child: Row(

                              children: [

                                const Icon(

                                  Icons.check_circle,

                                  color:
                                      Color(
                                          0xFFD4A017),

                                  size: 20,
                                ),

                                const SizedBox(
                                    width: 12),

                                Expanded(

                                  child: Text(

                                    feature,

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
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                  height: 26),

              /// DETAILS
              Padding(

                padding:
                    const EdgeInsets.symmetric(
                        horizontal: 18),

                child: Container(

                  width: double.infinity,

                  padding:
                      const EdgeInsets.all(
                          24),

                  decoration:
                      BoxDecoration(

                    color:
                        const Color(
                            0xFF111111),

                    borderRadius:
                        BorderRadius.circular(
                            28),
                  ),

                  child: Column(

                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [

                      const Text(

                        'WHAT WE DO',

                        style: TextStyle(

                          color:
                              Color(
                                  0xFFD4A017),

                          fontSize: 13,

                          fontWeight:
                              FontWeight.bold,

                          letterSpacing:
                              2,
                        ),
                      ),

                      const SizedBox(
                          height: 18),

                      Text(

                        selectedService[
                            'details'] as String,

                        style:
                            const TextStyle(

                          color:
                              Colors.white70,

                          fontSize: 16,

                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                  height: 30),

              /// PICKUP
              Padding(

                padding:
                    const EdgeInsets.symmetric(
                        horizontal: 18),

                child: Container(

                  padding:
                      const EdgeInsets.all(
                          22),

                  decoration:
                      BoxDecoration(

                    color:
                        const Color(
                            0xFF111111),

                    borderRadius:
                        BorderRadius.circular(
                            24),
                  ),

                  child: Row(

                    children: [

                      const Expanded(

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            Text(

                              'Pickup & Drop',

                              style:
                                  TextStyle(

                                color:
                                    Colors.white,

                                fontSize:
                                    20,

                                fontWeight:
                                    FontWeight
                                        .w900,
                              ),
                            ),

                            SizedBox(
                                height: 6),

                            Text(

                              'Doorstep vehicle collection available',

                              style:
                                  TextStyle(

                                color:
                                    Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Switch(

                        value:
                            pickupEnabled,

                        activeColor:
                            const Color(
                                0xFFD4A017),

                        onChanged:
                            (v) {

                          setState(() {

                            pickupEnabled =
                                v;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                  height: 40),

              /// BOOK BUTTON
              Padding(

                padding:
                    const EdgeInsets.symmetric(
                        horizontal: 18),

                child: SizedBox(

                  width: double.infinity,
                  height: 68,

                  child:
                      ElevatedButton(

                    style:
                        ElevatedButton.styleFrom(

                      backgroundColor:
                          const Color(
                              0xFFD4A017),

                      shape:
                          RoundedRectangleBorder(

                        borderRadius:
                            BorderRadius.circular(
                                24),
                      ),
                    ),

                    onPressed: () {

                      Navigator.push(

                        context,

                        MaterialPageRoute(

                          builder: (_) =>
                              PaymentScreen(

                            title:
                                selectedService[
                                    'title'] as String,

                            price:
                                selectedService[
                                    'price'] as String,

                            duration:
                                selectedService[
                                    'time'] as String,

                            vehicleId:
                                widget.vehicle['id']
                                    .toString(),
                          ),
                        ),
                      );
                    },

                    child:
                        const Text(

                      'BOOK NOW',

                      style:
                          TextStyle(

                        color:
                            Colors.black,

                        fontWeight:
                            FontWeight.w900,

                        fontSize:
                            20,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }
  static Widget _chip(
      String text) {

    return Container(

      padding:
          const EdgeInsets.symmetric(

        horizontal: 14,
        vertical: 8,
      ),

      decoration:
          BoxDecoration(

        color:
            const Color(
                0xFFD4A017)
                .withOpacity(0.12),

        borderRadius:
            BorderRadius.circular(
                18),
      ),

      child: Text(

        text,

        style: const TextStyle(

          color:
              Color(0xFFD4A017),

          fontWeight:
              FontWeight.w800,

          fontSize: 12,
        ),
      ),
    );
  }
}