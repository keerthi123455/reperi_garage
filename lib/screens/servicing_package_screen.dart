import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data for the "Servicing" (21-Step Inspection)
/// category — deliberately NOT fetched from Supabase, per request. This
/// mirrors a premium tiered-pricing page (Essential / Premium / Signature)
/// instead of the old single-package hero+bullet-list layout.
class _Tier {
  final String name;
  final String price;
  final String tagline;
  final Color accent;
  final bool popular;
  final List<String> highlights;

  const _Tier({
    required this.name,
    required this.price,
    required this.tagline,
    required this.accent,
    required this.highlights,
    this.popular = false,
  });
}

const _tiers = [
  _Tier(
    name: 'ESSENTIAL',
    price: '₹999',
    tagline: 'Perfect for routine service',
    accent: Color(0xFF4FA3E3),
    highlights: [
      'Engine Oil Change',
      'Oil Filter Change',
      'Brake Inspection',
      'AC Cooling Check',
      'Battery Health Test',
      'Tyre Inspection',
      'Fluid Level Check',
      '21-Point Diagnostics',
      'Digital Health Report',
    ],
  ),
  _Tier(
    name: 'PREMIUM CARE',
    price: '₹3,999',
    tagline: 'Most Popular',
    accent: Color(0xFFD4A017),
    popular: true,
    highlights: [
      'Everything in Essential',
      'Premium Engine Oil',
      'Oil Filter Replacement',
      'Brake Fluid Top-up',
      'AC Performance Service',
      'Air Filter Cleaning',
      'Cabin Filter Cleaning',
      'Steering Check',
      'Suspension Check',
      'Car Wash',
      'Interior Vacuum',
      '35-Point Diagnostics',
    ],
  ),
  _Tier(
    name: 'SIGNATURE SERVICE',
    price: '₹5,999',
    tagline: 'Ultimate Protection',
    accent: Color(0xFFF5C842),
    highlights: [
      'Everything in Premium',
      'Synthetic Engine Oil',
      'Brake Fluid Replacement',
      'Air Filter Replacement',
      'Cabin Filter Replacement',
      'Battery Load Test',
      'Fuel System Check',
      'Complete Brake Service',
      'Wheel Alignment Check',
      'Underbody Inspection',
      'Deep Interior Cleaning',
      'Foam Exterior Wash',
      '50+ Point Diagnostics',
      'Photo Health Report',
      'Priority Support',
    ],
  ),
];

const _fullChecklist = {
  'Engine': [
    'Engine Oil Change',
    'Oil Filter',
    'Air Filter',
    'Spark Plug Check',
  ],
  'Brakes': ['Brake Pad Inspection', 'Brake Fluid', 'Brake Lines'],
  'Electrical': ['Battery Test', 'Alternator Check'],
  'Air Conditioning': [
    'Cooling Performance',
    'Cabin Filter',
    'Compressor Inspection',
  ],
  'Tyres': ['Pressure', 'Wear Pattern', 'Rotation Recommendation'],
  'Safety': ['Lights', 'Horn', 'Wipers', 'Seat Belts'],
  'Digital Report': [
    'OBD Scan',
    'Vehicle Health Score',
    'Repair Recommendations',
  ],
};

// (feature, essential, premium, signature)
const _comparisonRows = [
  ('Engine Oil Change', '✅', '✅', '✅'),
  ('Oil Filter', '✅', '✅', '✅'),
  ('Brake Check', '✅', '✅', '✅'),
  ('Brake Fluid', 'Check', 'Top-up', 'Replace'),
  ('AC Check', '✅', '✅', 'Deep Inspection'),
  ('Battery Test', '✅', '✅', 'Load Test'),
  ('Suspension Check', 'Visual', 'Detailed', 'Complete'),
  ('Interior Cleaning', '❌', 'Vacuum', 'Deep Clean'),
  ('Exterior Wash', '❌', 'Standard', 'Foam Wash'),
  ('Diagnostics', '21 Point', '35 Point', '50+ Point'),
  ('Digital Report', '✅', '✅', 'Photos Included'),
  ('Priority Service', '❌', '❌', '✅'),
];

const _whyChooseUs = [
  (Icons.build_circle_rounded, 'Certified Mechanics'),
  (Icons.receipt_long_rounded, 'Transparent Pricing'),
  (Icons.smartphone_rounded, 'Digital Vehicle Health Report'),
  (Icons.verified_user_rounded, 'Genuine Parts'),
];

class ServicingPackageScreen extends StatefulWidget {
  final String vehicleId;

  const ServicingPackageScreen({super.key, required this.vehicleId});

  @override
  State<ServicingPackageScreen> createState() =>
      _ServicingPackageScreenState();
}

class _ServicingPackageScreenState extends State<ServicingPackageScreen> {
  int _selectedTier = 1; // default to Premium Care, matching "Most Popular"
  bool _checklistExpanded = false;

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the servicing packages.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _bookNow(_Tier tier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: tier.name,
          price: tier.price,
          duration: '3-4 hrs',
          vehicleId: widget.vehicleId,
        ),
      ),
    );
  }

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
                              'SERVICING',
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
                          'Keep Your Car\nRunning Like New',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Professional servicing by certified mechanics with transparent pricing and a digital health report.',
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
                        'Choose Your Service Package',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Three packages designed for every stage of your car's life.",
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
                  height: 480,
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
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
                              const SizedBox(height: 16),
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

              // ── EXPANDABLE FULL CHECKLIST ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF3A3A3A)),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => setState(
                              () => _checklistExpanded = !_checklistExpanded),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 16),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'View Complete Checklist',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14),
                                  ),
                                ),
                                Icon(
                                  _checklistExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: const Color(0xFFD4A017),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 250),
                          crossFadeState: _checklistExpanded
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _fullChecklist.entries
                                  .map((entry) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.key,
                                              style: const TextStyle(
                                                color: Color(0xFFD4A017),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ...entry.value.map((item) =>
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 4),
                                                  child: Text(
                                                    '✓ $item',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                )),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          secondChild: const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── COMPARISON TABLE ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compare Packages',
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
                            0: FixedColumnWidth(150),
                            1: FixedColumnWidth(90),
                            2: FixedColumnWidth(90),
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
                                  child: Text('₹999',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFF4FA3E3),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹3,999',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹5,999',
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
                      Text('Still not sure?',
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