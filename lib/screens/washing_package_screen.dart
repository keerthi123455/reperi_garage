import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data for the "Washing" (QuickCare) category —
/// deliberately NOT fetched from Supabase, matching the pattern used for
/// the Servicing screen. Same structural design: header, selectable tier
/// cards, one shared expandable full checklist, a comparison table, and a
/// sticky bottom "BOOK NOW" bar — with one addition: booking prompts for
/// an optional doorstep pickup (+₹100) before going to payment.
class _Tier {
  final String name;
  final String price;
  final String tagline;
  final String bestFor;
  final Color accent;
  final bool popular;
  final List<String> highlights;

  const _Tier({
    required this.name,
    required this.price,
    required this.tagline,
    required this.bestFor,
    required this.accent,
    required this.highlights,
    this.popular = false,
  });
}

const _tiers = [
  _Tier(
    name: 'EXPRESS WASH',
    price: '₹299',
    tagline: 'A quick refresh for your car',
    bestFor: 'Weekly cleaning or after a long drive.',
    accent: Color(0xFF4FA3E3),
    highlights: [
      'High-Pressure Exterior Wash',
      'Premium Foam Wash',
      'Microfiber Hand Drying',
      'Tyre Cleaning',
      'Alloy Wheel Cleaning',
      'Exterior Glass Cleaning',
      'Tyre Shine Dressing',
      'Final Quality Inspection',
    ],
  ),
  _Tier(
    name: 'PREMIUM WASH',
    price: '₹599',
    tagline: 'Inside & out, clean and refreshed',
    bestFor: 'Monthly maintenance and everyday use.',
    accent: Color(0xFFD4A017),
    popular: true,
    highlights: [
      'Everything in Express Wash',
      'Interior Vacuum Cleaning',
      'Dashboard & Console Cleaning',
      'Door Panel Wipe Down',
      'Interior Glass Cleaning',
      'Floor Mat Cleaning',
      'Boot (Trunk) Vacuum',
      'Air Freshener Application',
      'Plastic Trim Dressing',
      'Final Quality Inspection',
    ],
  ),
  _Tier(
    name: 'SIGNATURE DETAILING',
    price: '₹2,999',
    tagline: "Restore your car's showroom shine",
    bestFor:
        'Festive seasons, before resale, special occasions, or when you want your car looking its absolute best.',
    accent: Color(0xFFF5C842),
    highlights: [
      'Everything in Premium Wash',
      'Snow Foam Pre-Wash',
      'Two-Bucket Safe Hand Wash',
      'Bug & Tar Removal',
      'Clay Bar Surface Decontamination',
      'Machine Wax / Paint Sealant Application',
      'Exterior Plastic Trim Restoration',
      'Tyre & Alloy Deep Cleaning',
      'Engine Bay Surface Cleaning',
      'Interior Deep Vacuum',
      'Leather/Fabric Seat Cleaning',
      'Dashboard UV Protection',
      'Door Jamb Cleaning',
      'Interior Steam Sanitization (where applicable)',
      'Premium Glass Treatment',
      'Long-Lasting Air Freshener',
      'Final Multi-Point Quality Inspection',
    ],
  ),
];

// (feature, express, premium, signature)
const _comparisonRows = [
  ('Exterior Foam Wash', '✅', '✅', '✅'),
  ('Hand Drying', '✅', '✅', '✅'),
  ('Tyre & Wheel Cleaning', '✅', '✅', 'Deep Clean'),
  ('Tyre Shine', '✅', '✅', 'Premium'),
  ('Interior Vacuum', '❌', '✅', 'Deep'),
  ('Dashboard Cleaning', '❌', '✅', 'UV Protection'),
  ('Interior Glass', '❌', '✅', '✅'),
  ('Floor Mat Cleaning', '❌', '✅', '✅'),
  ('Paint Protection Wax', '❌', '❌', '✅'),
  ('Clay Bar Treatment', '❌', '❌', '✅'),
  ('Engine Bay Cleaning', '❌', '❌', '✅'),
  ('Steam Sanitization', '❌', '❌', '✅'),
  ('Leather/Fabric Care', '❌', '❌', '✅'),
  ('Air Freshener', '❌', '✅', 'Premium'),
];

const _whyChooseUs = [
  (Icons.wash_rounded, 'Trained Wash Specialists'),
  (Icons.receipt_long_rounded, 'Transparent Pricing'),
  (Icons.water_drop_rounded, 'Premium-Grade Products'),
  (Icons.verified_user_rounded, 'Final Quality Inspection'),
];

const int _doorstepPickupFee = 100;

class WashingPackageScreen extends StatefulWidget {
  final String vehicleId;

  const WashingPackageScreen({super.key, required this.vehicleId});

  @override
  State<WashingPackageScreen> createState() => _WashingPackageScreenState();
}

class _WashingPackageScreenState extends State<WashingPackageScreen> {
  int _selectedTier = 1; // default to Premium Wash, matching "Most Popular"
  bool _checklistExpanded = false;

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the washing packages.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Adds a flat rupee fee to a "₹x,xxx" style price string and reformats
  // it with thousands separators, e.g. "₹2,999" + 100 -> "₹3,099".
  String _addFee(String price, int fee) {
    final digits = price.replaceAll(RegExp(r'[^0-9]'), '');
    final value = int.parse(digits) + fee;
    final formatted = value.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => ',',
        );
    return '₹$formatted';
  }

  void _goToPayment(_Tier tier, {required bool withPickup}) {
    final finalPrice =
        withPickup ? _addFee(tier.price, _doorstepPickupFee) : tier.price;
    final finalTitle =
        withPickup ? '${tier.name} + Doorstep Pickup' : tier.name;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: finalTitle,
          price: finalPrice,
          duration: '1-2 hrs',
          vehicleId: widget.vehicleId,
        ),
      ),
    );
  }

  void _bookNow(_Tier tier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.home_work_rounded,
                        color: Color(0xFFD4A017), size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Add Doorstep Pickup?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "We'll pick up your car from your doorstep and drop it back once the $_doorstepPickupWashLabel is done — this adds ₹$_doorstepPickupFee to your bill.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _goToPayment(tier, withPickup: true);
                  },
                  child: Text(
                    'Yes, Add Pickup (+₹$_doorstepPickupFee)',
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF3A3A3A)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _goToPayment(tier, withPickup: false);
                  },
                  child: const Text(
                    "No, I'll Drop Off Myself",
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _doorstepPickupWashLabel => 'wash';

  @override
  Widget build(BuildContext context) {
    final selected = _tiers[_selectedTier];

    return Scaffold(
      backgroundColor: const Color(0xFF262626),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── HEADER (no hero photo — clean typographic header) ──
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF262626),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: const Color(0xFF3A3A3A)),
                            ),
                            child: const Icon(Icons.arrow_back,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 26,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4A017),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFD4A017)
                                        .withOpacity(0.6),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'WASHING',
                              style: TextStyle(
                                color: Color(0xFFD4A017),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'A Clean That Feels\nLike New',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'From a quick weekly refresh to full showroom-grade detailing — pick the wash that fits your car right now.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── SECTION TITLE ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose Your Wash',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Simple, aspirational, and built around how you actually use your car.',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              // ── PACKAGE CARDS ──
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 500,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    itemCount: _tiers.length,
                    itemBuilder: (_, i) {
                      final tier = _tiers[i];
                      final isSelected = i == _selectedTier;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTier = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: tier.popular ? 250 : 220,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: tier.popular
                                ? const Color(0xFF1C1806)
                                : const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected
                                  ? tier.accent
                                  : tier.accent.withOpacity(0.25),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: tier.popular
                                ? [
                                    BoxShadow(
                                      color: tier.accent.withOpacity(0.25),
                                      blurRadius: 26,
                                      offset: const Offset(0, 12),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (tier.popular)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tier.accent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'MOST POPULAR',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              if (tier.popular) const SizedBox(height: 12),
                              Text(
                                tier.name,
                                style: TextStyle(
                                  color: tier.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                tier.price,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tier.tagline,
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12),
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: ListView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  children: tier.highlights
                                      .take(9)
                                      .map((h) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(Icons.check_circle,
                                                    color: tier.accent,
                                                    size: 15),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    h,
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12.5),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Best for: ${tier.bestFor}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isSelected
                                        ? tier.accent
                                        : const Color(0xFF262626),
                                    foregroundColor: isSelected
                                        ? Colors.black
                                        : Colors.white70,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                  onPressed: () => _bookNow(tier),
                                  child: const Text('Book Now',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── COMPARISON TABLE ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compare Washes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Table(
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          columnWidths: const {
                            0: FixedColumnWidth(170),
                            1: FixedColumnWidth(80),
                            2: FixedColumnWidth(80),
                            3: FixedColumnWidth(110),
                          },
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom:
                                      BorderSide(color: Color(0xFF3A3A3A)),
                                ),
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('Feature',
                                      style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹299',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFF4FA3E3),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹599',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹2,999',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFFF5C842),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                            for (final row in _comparisonRows)
                              TableRow(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                        color: Color(0xFF1E1E1E)),
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$1,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12.5)),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$2,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12.5)),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$3,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12.5)),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$4,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12.5)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── WHY CHOOSE REPERI ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Why Choose Reperi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.5,
                        children: _whyChooseUs
                            .map((f) => Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141414),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                        color: const Color(0xFF3A3A3A)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(f.$1,
                                          color: const Color(0xFFD4A017),
                                          size: 26),
                                      const SizedBox(height: 10),
                                      Text(
                                        f.$2,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── TALK TO ADVISOR ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 140),
                  child: Column(
                    children: [
                      Text('Not sure which wash to pick?',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      const Text('Talk to our Service Advisor',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _openWhatsApp,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF25D366)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        icon: const Icon(Icons.chat_bubble_rounded,
                            color: Color(0xFF25D366), size: 18),
                        label: const Text('WhatsApp',
                            style: TextStyle(
                                color: Color(0xFF25D366),
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── STICKY BOOK NOW BAR ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: () => _bookNow(selected),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4A017).withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_month,
                            color: Colors.black, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'BOOK ${selected.name} • ${selected.price}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
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