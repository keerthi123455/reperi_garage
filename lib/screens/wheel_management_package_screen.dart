import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data for the "Wheel Management" (WheelzCare)
/// category — same structural pattern as Servicing/Washing: typographic
/// header (no hero photo), selectable tier cards, one shared expandable
/// checklist, a comparison table, and a sticky bottom "BOOK NOW" bar.
class _Tier {
  final String name;
  final String price;
  final String tagline;
  final String bestFor;
  final Color accent;
  final bool recommended;
  final List<String> highlights;

  const _Tier({
    required this.name,
    required this.price,
    required this.tagline,
    required this.bestFor,
    required this.accent,
    required this.highlights,
    this.recommended = false,
  });
}

const _tiers = [
  _Tier(
    name: 'PRECISION ALIGNMENT',
    price: '₹999',
    tagline: 'Better handling, smoother driving, and longer tyre life',
    bestFor:
        'Every 8,000–10,000 km, after hitting potholes, or when the car pulls to one side.',
    accent: Color(0xFF4FA3E3),
    highlights: [
      'Computerized Wheel Alignment',
      'Steering Alignment Check',
      'Suspension Geometry Inspection',
      'Tyre Pressure Adjustment',
      'Front & Rear Tyre Wear Inspection',
      'Steering Wheel Centering',
      'Road Test After Alignment',
      'Digital Alignment Report',
    ],
  ),
  _Tier(
    name: 'COMPLETE WHEEL CARE',
    price: '₹1,999',
    tagline: 'Maximize tyre life and improve driving comfort',
    bestFor: 'New tyres, high-speed vibration issues, or every 10,000 km.',
    accent: Color(0xFFD4A017),
    recommended: true,
    highlights: [
      'Everything in Precision Alignment',
      'Computerized Wheel Balancing (All 4 Wheels)',
      'Alloy Wheel Inspection',
      'Tyre Rotation (if applicable)',
      'Valve & Air Leak Check',
      'Wheel Nut Torque Check',
      'Suspension & Steering Linkage Inspection',
      'Brake Disc Visual Inspection',
      'Tyre Tread Depth Measurement',
      'Tyre Health Report with Replacement Advice',
      'Complimentary Tyre Shine',
    ],
  ),
];

// (feature, ₹999, ₹1,999)
const _comparisonRows = [
  ('Wheel Alignment', '✅', '✅'),
  ('Wheel Balancing', '❌', '✅'),
  ('Tyre Rotation', '❌', '✅'),
  ('Suspension Check', '✅', 'Detailed'),
  ('Tyre Pressure Adjustment', '✅', '✅'),
  ('Steering Check', '✅', '✅'),
  ('Digital Report', '✅', '✅'),
  ('Tyre Health Report', '❌', '✅'),
];

const _whyChooseUs = [
  (Icons.speed_rounded, 'Computerized Precision'),
  (Icons.receipt_long_rounded, 'Transparent Pricing'),
  (Icons.description_rounded, 'Digital Alignment Report'),
  (Icons.verified_user_rounded, 'Trained Technicians'),
];

class WheelManagementPackageScreen extends StatefulWidget {
  final String vehicleId;

  const WheelManagementPackageScreen({super.key, required this.vehicleId});

  @override
  State<WheelManagementPackageScreen> createState() =>
      _WheelManagementPackageScreenState();
}

class _WheelManagementPackageScreenState
    extends State<WheelManagementPackageScreen> {
  int _selectedTier = 1; // default to Complete Wheel Care (recommended)

  @override
  void initState() {
    super.initState();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the wheel management packages.")}',
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
          duration: '1-2 hrs',
          vehicleId: widget.vehicleId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _tiers[_selectedTier];
    // A warm, gold-tinted card for the "recommended" tier — blended over
    // the current mode's surface so it stays subtle in both themes instead
    // of a fixed near-black tint that would look wrong in light mode.
    final recommendedCardColor = Color.alphaBlend(
      AppColors.accent.withOpacity(0.12),
      AppColors.surfaceRaised,
    );

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── HEADER (no hero photo) ──
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
                              color: AppColors.surfaceRaised,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Icon(Icons.arrow_back,
                                color: AppColors.txt, size: 20),
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
                              'WHEEL MANAGEMENT',
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
                        Text(
                          'Smoother Rides,\nLonger Tyre Life',
                          style: TextStyle(
                            color: AppColors.txt,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Computerized alignment and balancing to keep your car running straight and your tyres lasting longer.',
                          style: TextStyle(
                            color: AppColors.mut,
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
                      Text(
                        'Choose Your Package',
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Two levels of care, from a quick alignment to complete wheel health.',
                        style: TextStyle(color: AppColors.mut, fontSize: 13),
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
                          width: tier.recommended ? 260 : 230,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: tier.recommended
                                ? recommendedCardColor
                                : AppColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected
                                  ? tier.accent
                                  : tier.accent.withOpacity(0.25),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: tier.recommended
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
                              if (tier.recommended)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tier.accent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.workspace_premium_rounded,
                                          color: AppColors.onAccentDark, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'RECOMMENDED',
                                        style: TextStyle(
                                          color: AppColors.onAccentDark,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (tier.recommended) const SizedBox(height: 12),
                              Text(
                                tier.name,
                                style: TextStyle(
                                  color: tier.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                tier.price,
                                style: TextStyle(
                                  color: AppColors.txt,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tier.tagline,
                                style: TextStyle(
                                    color: AppColors.mut, fontSize: 12),
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
                                                    style: TextStyle(
                                                        color: AppColors.txt
                                                            .withOpacity(0.7),
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
                                  color: AppColors.mut,
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
                                        : AppColors.chipBg,
                                    foregroundColor: isSelected
                                        ? AppColors.onAccentDark
                                        : AppColors.txt.withOpacity(0.7),
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
                      Text(
                        'Compare Packages',
                        style: TextStyle(
                          color: AppColors.txt,
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
                            0: FixedColumnWidth(190),
                            1: FixedColumnWidth(90),
                            2: FixedColumnWidth(90),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: AppColors.line),
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text('Feature',
                                      style: TextStyle(
                                          color: AppColors.mut,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹999',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFF4FA3E3),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹1,999',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                            for (final row in _comparisonRows)
                              TableRow(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                        color: AppColors.line.withOpacity(0.6)),
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$1,
                                        style: TextStyle(
                                            color: AppColors.txt.withOpacity(0.7),
                                            fontSize: 12.5)),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$2,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: AppColors.txt.withOpacity(0.7),
                                            fontSize: 12.5)),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(row.$3,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: AppColors.txt.withOpacity(0.7),
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
                      Text(
                        'Why Choose Reperi',
                        style: TextStyle(
                          color: AppColors.txt,
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
                                    color: AppColors.surfaceRaised,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: AppColors.line),
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
                                        style: TextStyle(
                                            color: AppColors.txt,
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
                      Text('Not sure which package to pick?',
                          style: TextStyle(color: AppColors.mut, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Talk to our Service Advisor',
                          style: TextStyle(
                              color: AppColors.txt,
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
                        Icon(Icons.calendar_month,
                            color: AppColors.onAccentDark, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'BOOK ${selected.name} • ${selected.price}',
                          style: TextStyle(
                            color: AppColors.onAccentDark,
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
