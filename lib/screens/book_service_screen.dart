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

  // ── Extract price value from string like "₹1999"
  int _extractPrice(String priceStr) {
    return int.tryParse(priceStr.replaceAll('₹', '').replaceAll(',', '')) ?? 0;
  }

  // ── Show doorstep pickup dialog
  void _showDoorstepPickupDialog() {
    final selectedService = services[selectedIndex];
    final basePrice = _extractPrice(selectedService['price'] as String);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Color(0xFFD4A017),
                  size: 48,
                ),
              ),

              const SizedBox(height: 24),

              // ── Title ──
              const Text(
                'Doorstep Pickup?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 12),

              // ── Subtitle ──
              const Text(
                'We can pick up your vehicle from your home and drop it back after service',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 28),

              // ── Yes Button ──
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _proceedToPayment(basePrice + 100);
                  },
                  child: const Text(
                    'Yes, Add ₹100',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── No Button ──
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(
                      color: Color(0xFFD4A017),
                      width: 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _proceedToPayment(basePrice);
                  },
                  child: const Text(
                    'No, I\'ll Drop It Myself',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Proceed to payment
  void _proceedToPayment(int finalPrice) {
    final selectedService = services[selectedIndex];
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: selectedService['title'] as String,
          price: '₹$finalPrice',
          duration: selectedService['time'] as String,
          vehicleId: widget.vehicle['id'].toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Stack(
              children: [
                // ── Scrollable Content ──
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      /// HERO SECTION (IMPROVED)
                      Stack(
                        children: [
                          // ── Hero Image ──
                          SizedBox(
                            height: 400,
                            width: double.infinity,
                            child: Image.asset(
                              'assets/images/tile_book_service.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),

                          // ── Strong Dark Gradient Overlay ──
                          Container(
                            height: 400,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.3),
                                  Colors.black.withOpacity(0.75),
                                ],
                                stops: const [0.3, 1.0],
                              ),
                            ),
                          ),

                          // ── Hero Content ──
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // ── Back Button ──
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white30),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),

                                // ── Content at Bottom ──
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── Premium Badge ──
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD4A017).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'PREMIUM CARE',
                                        style: TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // ── Title ──
                                    const Text(
                                      'BOOK\nSERVICE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 52,
                                        fontWeight: FontWeight.w900,
                                        height: 0.95,
                                        letterSpacing: -1,
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // ── Description ──
                                    const Text(
                                      'Professional servicing for your vehicle with genuine parts and expert technicians.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 1.6,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 3,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      /// SERVICE CARDS (FULL WIDTH, STACKED VERTICALLY)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: List.generate(services.length, (index) {
                            final service = services[index];
                            final isSelected = index == selectedIndex;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == services.length - 1 ? 0 : 16,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => selectedIndex = index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1C),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFD4A017)
                                          : Colors.white10,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFFD4A017).withOpacity(0.2),
                                              blurRadius: 20,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // ── Header: Icon + Title + Price ──
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD4A017).withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                service['icon'] as IconData,
                                                color: const Color(0xFFD4A017),
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    service['title'] as String,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        service['price'] as String,
                                                        style: const TextStyle(
                                                          color: Color(0xFFD4A017),
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w900,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white10,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          service['time'] as String,
                                                          style: const TextStyle(
                                                            color: Colors.white60,
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 20),

                                        // ── Divider ──
                                        Container(
                                          height: 1,
                                          color: Colors.white10,
                                        ),

                                        const SizedBox(height: 20),

                                        // ── What's Included ──
                                        const Text(
                                          'WHAT\'S INCLUDED',
                                          style: TextStyle(
                                            color: Color(0xFFD4A017),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5,
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        Column(
                                          children: (service['features'] as List<String>)
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: entry.key <
                                                        (service['features'] as List)
                                                                .length -
                                                            1
                                                    ? 10
                                                    : 0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    margin: const EdgeInsets.only(top: 5),
                                                    width: 5,
                                                    height: 5,
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFFD4A017),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      entry.value,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 13,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),

                                        const SizedBox(height: 20),

                                        // ── Divider ──
                                        Container(
                                          height: 1,
                                          color: Colors.white10,
                                        ),

                                        const SizedBox(height: 20),

                                        // ── Details ──
                                        const Text(
                                          'DETAILS',
                                          style: TextStyle(
                                            color: Color(0xFFD4A017),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5,
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        Text(
                                          service['details'] as String,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            height: 1.7,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ));
                          }),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),

                // ── FLOATING BOOK NOW BUTTON (BOTTOM) ──
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF050505).withOpacity(0),
                          const Color(0xFF050505).withOpacity(0.95),
                          const Color(0xFF050505),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: SizedBox(
                        width: double.infinity,
                        height: 62,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A017),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 12,
                            shadowColor: const Color(0xFFD4A017).withOpacity(0.4),
                          ),
                          onPressed: _showDoorstepPickupDialog,
                          child: const Text(
                            'BOOK NOW',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}