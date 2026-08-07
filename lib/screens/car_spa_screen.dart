import 'dart:async';
import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';

class CarSpaScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  const CarSpaScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<CarSpaScreen> createState() => _CarSpaScreenState();
}

class _CarSpaScreenState extends State<CarSpaScreen> {
  int selectedPackage = -1;

  Timer? _autoScrollTimer;

  final List<String> _beforeAfterImages = [
    'assets/images/before_after_1.jpg',
    'assets/images/before_after_2.jpg',
    'assets/images/before_after_3.jpg',
  ];

  static const Color _bg = Color(0xFF050505);
  static const Color _card = Color(0xFF111111);
  static const Color _gold = Color(0xFFD4A017);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _grey = Color(0xFF9E9E9E);

  List<Map<String, dynamic>> packages = [
    {
      'title': 'QUICK REFRESH',
      'subtitle': 'Exterior Basic Care',
      'price': '₹399',
      'duration': '30 mins',
      'icon': Icons.water_drop_outlined,
      'details': 'Fast maintenance with essential exterior and basic interior cleaning.',
      'features': [
        'Pressure Water Wash',
        'pH Neutral Foam Wash',
        'Exterior Hand Wash',
        'Microfiber Drying',
        'Tyre Cleaning',
        'Tyre Polish',
        'Wheel Rim Cleaning',
        'Exterior Glass Cleaning',
        'Dashboard Dusting',
        'Interior Vacuum Cleaning',
        'Door Jamb Cleaning',
        'Final Quality Inspection',
      ],
    },
    {
      'title': 'PREMIUM SPA',
      'subtitle': 'Interior Deep Clean',
      'price': '₹999',
      'duration': '90 mins',
      'icon': Icons.chair_outlined,
      'details': 'Everything in Quick Refresh, plus deep interior cleaning and protective treatments.',
      'features': [
        'Pressure Water Wash',
        'Premium Foam Wash',
        'Exterior Hand Drying',
        'Complete Interior Vacuum',
        'Dashboard Detailing',
        'Door Panel Cleaning',
        'Seat Deep Cleaning',
        'Floor Mat Cleaning',
        'Interior Plastic Dressing',
        'Interior Steam Cleaning',
        'AC Vent Cleaning',
        'Odour Removal Treatment',
        'Interior UV Protection',
        'Tyre Polish',
        'Exterior Glass Cleaning',
        'Final Quality Inspection',
      ],
    },
    {
      'title': 'SIGNATURE SPA+',
      'subtitle': 'Complete Car Restoration',
      'price': '₹2499',
      'duration': '150 mins',
      'icon': Icons.diamond_outlined,
      'details': 'Complete restoration with paint treatment, engine bay detailing, and premium finishing.',
      'features': [
        'Premium Foam Wash',
        'Paint Decontamination',
        'Clay Bar Treatment',
        'Machine Wax Polish',
        'Paint Gloss Enhancement',
        'Exterior Plastic Restoration',
        'Wheel Arch Cleaning',
        'Alloy Wheel Detailing',
        'Tyre Dressing',
        'Complete Interior Vacuum',
        'Dashboard Restoration',
        'Leather / Fabric Seat Cleaning',
        'Carpet Shampooing',
        'Roof Lining Cleaning',
        'Door Panel Restoration',
        'Interior Steam Sanitization',
        'AC Vent Sanitization',
        'Engine Bay Cleaning',
        'Exterior Glass Treatment',
        'Premium Perfume Finish',
        'Final Quality Inspection',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchPackageData();
  }

  Future<void> _fetchPackageData() async {
    try {
      final rows = await CatalogService.fetchByCategory('Car Spa');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      setState(() {
        if (byKey['car_spa_quick_refresh'] != null) {
          packages[0]['price'] = byKey['car_spa_quick_refresh']!['price'];
          packages[0]['duration'] = byKey['car_spa_quick_refresh']!['duration'];
        }
        if (byKey['car_spa_premium'] != null) {
          packages[1]['price'] = byKey['car_spa_premium']!['price'];
          packages[1]['duration'] = byKey['car_spa_premium']!['duration'];
        }
        if (byKey['car_spa_signature_plus'] != null) {
          packages[2]['price'] = byKey['car_spa_signature_plus']!['price'];
          packages[2]['duration'] = byKey['car_spa_signature_plus']!['duration'];
        }
      });
    } catch (e) {
      // Keep fallback values
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  // ── Extract price value
  int _extractPrice(String priceStr) {
    return int.tryParse(priceStr.replaceAll('₹', '').replaceAll(',', '')) ?? 0;
  }

  // ── Show doorstep pickup dialog
  void _showDoorstepPickupDialog() {
    final selectedPkg = packages[selectedPackage];
    final basePrice = _extractPrice(selectedPkg['price'] as String);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: _gold,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Doorstep Pickup?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
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
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
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
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(color: _gold, width: 2),
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
                      color: _gold,
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
    final selectedPkg = packages[selectedPackage];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: selectedPkg['title'] as String,
          price: '₹$finalPrice',
          duration: selectedPkg['duration'] as String,
          vehicleId: widget.vehicle['id'].toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
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
                              'assets/images/car_spa_hero.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFF1A1A1A),
                                child: const Center(
                                  child: Icon(
                                    Icons.directions_car,
                                    color: _gold,
                                    size: 80,
                                  ),
                                ),
                              ),
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
                                      color: _white,
                                      size: 20,
                                    ),
                                  ),
                                ),

                                // ── Content at Bottom ──
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _gold.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'PREMIUM DETAILING',
                                        style: TextStyle(
                                          color: _gold,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'CAR SPA\nSERVICES',
                                      style: TextStyle(
                                        color: _white,
                                        fontSize: 52,
                                        fontWeight: FontWeight.w900,
                                        height: 0.95,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Premium detailing and restoration to keep your car looking showroom-new.',
                                      style: TextStyle(
                                        color: _white,
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

                      /// PACKAGE CARDS (FULL WIDTH, STACKED VERTICALLY)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: List.generate(packages.length, (index) {
                            final pkg = packages[index];
                            final isSelected = index == selectedPackage;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == packages.length - 1 ? 0 : 16,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => selectedPackage = index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: _card,
                                    border: Border.all(
                                      color: isSelected ? _gold : Colors.white10,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: _gold.withOpacity(0.2),
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
                                                color: _gold.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                pkg['icon'] as IconData,
                                                color: _gold,
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    pkg['title'] as String,
                                                    style: const TextStyle(
                                                      color: _white,
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    pkg['subtitle'] as String,
                                                    style: const TextStyle(
                                                      color: _grey,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        pkg['price'] as String,
                                                        style: const TextStyle(
                                                          color: _gold,
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
                                                          pkg['duration'] as String,
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
                                            color: _gold,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5,
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        Column(
                                          children: (pkg['features'] as List<String>)
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: entry.key <
                                                        (pkg['features'] as List).length - 1
                                                    ? 10
                                                    : 0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    margin: const EdgeInsets.only(top: 5),
                                                    width: 5,
                                                    height: 5,
                                                    decoration: const BoxDecoration(
                                                      color: _gold,
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
                                            color: _gold,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.5,
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        Text(
                                          pkg['details'] as String,
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
                          _bg.withOpacity(0),
                          _bg.withOpacity(0.95),
                          _bg,
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
                            backgroundColor: selectedPackage == -1
                                ? Colors.grey.shade700
                                : _gold,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 12,
                            shadowColor: _gold.withOpacity(0.4),
                          ),
                          onPressed: selectedPackage == -1
                              ? null
                              : _showDoorstepPickupDialog,
                          child: Text(
                            selectedPackage == -1 ? 'SELECT A PACKAGE' : 'BOOK NOW',
                            style: TextStyle(
                              color: selectedPackage == -1
                                  ? Colors.grey.shade400
                                  : Colors.black87,
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