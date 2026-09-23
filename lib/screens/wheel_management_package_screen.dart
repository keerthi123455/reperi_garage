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
  final String duration;
  final String tagline;
  final String bestFor;
  final Color accent;
  final bool recommended;
  final List<String> highlights;

  const _Tier({
    required this.name,
    required this.price,
    required this.duration,
    required this.tagline,
    required this.bestFor,
    required this.accent,
    required this.highlights,
    this.recommended = false,
  });
}

// Matches the real Wheel Alignment (₹499), Wheel Balancing (₹299), and
// Wheel Alignment and Balancing (₹799) packages — the same three the Tyre
// Care screen and the Services catalog offer, just presented in this
// screen's tier-card UI.
const _tiers = [
  _Tier(
    name: 'WHEEL ALIGNMENT',
    price: '₹499',
    duration: '45 mins',
    tagline: 'Better handling, smoother driving, and longer tyre life',
    bestFor:
        'Every 8,000–10,000 km, after hitting potholes, or when the car pulls to one side.',
    accent: Color(0xFF4FA3E3),
    highlights: [
      'Computerized alignment',
      'Steering correction',
      'Camber adjustment',
      'Wheel angle optimization',
      'Road stability testing',
    ],
  ),
  _Tier(
    name: 'WHEEL BALANCING',
    price: '₹299',
    duration: '30 mins',
    tagline: 'Improves ride quality and tyre longevity',
    bestFor: 'Every 10,000 km, or if you feel vibration at highway speed.',
    accent: Color(0xFF4CAF7A),
    highlights: [
      'Dynamic balancing',
      'Wheel weight calibration',
      'Vibration reduction',
      'High-speed balancing',
      'Extra charges up to ₹200 may apply (tyre-dependent)',
    ],
  ),
  _Tier(
    name: 'WHEEL ALIGNMENT AND BALANCING',
    price: '₹799',
    duration: '60 mins',
    tagline: 'Our most complete wheel care combo, in one visit',
    bestFor: 'New tyres, high-speed vibration issues, or every 10,000 km.',
    accent: Color(0xFFD4A017),
    recommended: true,
    highlights: [
      'Everything in Wheel Alignment',
      'Dynamic balancing',
      'Wheel weight calibration',
      'Extra charges up to ₹200 may apply (tyre-dependent)',
    ],
  ),
];

// (feature, ₹499, ₹299, ₹799)
const _comparisonRows = [
  ('Computerized Alignment', '✅', '❌', '✅'),
  ('Steering Correction', '✅', '❌', '✅'),
  ('Camber Adjustment', '✅', '❌', '✅'),
  ('Dynamic Balancing', '❌', '✅', '✅'),
  ('Wheel Weight Calibration', '❌', '✅', '✅'),
  ('Road Stability Testing', '✅', '❌', '✅'),
  ('Extra Charges (tyre-dependent)', '—', 'Up to ₹200', 'Up to ₹200'),
];

const _whyChooseUs = [
  (Icons.speed_rounded, 'Computerized Precision'),
  (Icons.receipt_long_rounded, 'Transparent Pricing'),
  (Icons.description_rounded, 'Digital Alignment Report'),
  (Icons.verified_user_rounded, 'Trained Technicians'),
];

class WheelManagementPackageScreen extends StatefulWidget {
  final String vehicleId;

  /// When set (matches one of the tier names above, case-insensitive),
  /// that tier is pre-selected and scrolled into view on open.
  final String? highlightPackage;

  const WheelManagementPackageScreen({super.key, required this.vehicleId, this.highlightPackage});

  @override
  State<WheelManagementPackageScreen> createState() =>
      _WheelManagementPackageScreenState();
}

class _WheelManagementPackageScreenState
    extends State<WheelManagementPackageScreen> {
  int _selectedTier = 2; // default to Wheel Alignment and Balancing (recommended)

  // When true, the sticky nav bar's "COMPARE" tab is active and the
  // comparison table shows in place of the selected tier's card. The
  // sticky bottom BOOK bar still tracks _selectedTier regardless, so
  // switching to Compare and back never loses what was selected.
  bool _showComparison = false;

  @override
  void initState() {
    super.initState();
    if (widget.highlightPackage != null) {
      final target = widget.highlightPackage!.toLowerCase();
      final match = _tiers.indexWhere((t) => t.name.toLowerCase() == target);
      if (match != -1) {
        _selectedTier = match;
      }
    }
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
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please try again.')),
      );
    }
  }

  void _bookNow(_Tier tier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: tier.name,
          price: tier.price,
          duration: tier.duration,
          vehicleId: widget.vehicleId,
        ),
      ),
    );
  }

  void _showTierDetails(_Tier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TierDetailsSheet(
        tier: tier,
        onBookNow: () {
          Navigator.pop(sheetContext);
          _bookNow(tier);
        },
      ),
    );
  }

  /// Simplified summary card — just enough to identify and compare the
  /// tier at a glance. Full highlights/best-for copy and the actual "Book
  /// Now" action live in the detail sheet ([_showTierDetails]) instead of
  /// crowding this card.
  Widget _buildTierCard(_Tier tier, Color recommendedCardColor) {
    final isSelected = _selectedTier == _tiers.indexOf(tier);
    return GestureDetector(
      onTap: () => _showTierDetails(tier),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color:
              tier.recommended ? recommendedCardColor : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? tier.accent : tier.accent.withOpacity(0.25),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            if (tier.recommended) const SizedBox(height: 14),
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
              style: TextStyle(
                color: AppColors.txt,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tier.tagline,
              style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tier.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Duration: ${tier.duration}',
                style: TextStyle(
                  color: tier.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tap for full details',
                  style: TextStyle(
                    color: AppColors.mut,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.mut, size: 22),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonTable() {
    return Column(
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
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FixedColumnWidth(190),
              1: FixedColumnWidth(80),
              2: FixedColumnWidth(80),
              3: FixedColumnWidth(80),
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
                    child: Text('₹499',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF4FA3E3),
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('₹299',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF4CAF7A),
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('₹799',
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
                      bottom:
                          BorderSide(color: AppColors.line.withOpacity(0.6)),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(row.$1,
                          style: TextStyle(
                              color: AppColors.txt.withOpacity(0.7),
                              fontSize: 12.5)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(row.$2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.txt.withOpacity(0.7),
                              fontSize: 12.5)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(row.$3,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.txt.withOpacity(0.7),
                              fontSize: 12.5)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(row.$4,
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
                        Semantics(
                          button: true,
                          label: 'Back',
                          child: GestureDetector(
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

              // ── STICKY TIER SWITCHER ──
              SliverPersistentHeader(
                pinned: true,
                delegate: _WheelTabBarDelegate(
                  selectedIndex: _selectedTier,
                  showComparison: _showComparison,
                  onSelectTier: (i) => setState(() {
                    _selectedTier = i;
                    _showComparison = false;
                  }),
                  onSelectCompare: () =>
                      setState(() => _showComparison = true),
                ),
              ),

              // ── SELECTED TIER CARD OR COMPARISON TABLE ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _showComparison
                      ? _buildComparisonTable()
                      : _buildTierCard(
                          _tiers[_selectedTier], recommendedCardColor),
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
                                      Flexible(
                                        child: Text(
                                          f.$2,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: AppColors.txt,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700),
                                        ),
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // A tier name can run long ("WHEEL ALIGNMENT AND
                          // BALANCING") — Flexible + ellipsis keeps this bar
                          // from overflowing horizontally instead of just
                          // hoping every name stays short.
                          Flexible(
                            child: Text(
                              'BOOK ${selected.name} • ${selected.price}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.onAccentDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
                              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Full tier detail sheet, opened by tapping a tier card. Carries the "Book
// Now" action itself — the inline card is a tap target only.
// ─────────────────────────────────────────────────────────────────────────────
class _TierDetailsSheet extends StatelessWidget {
  const _TierDetailsSheet({
    required this.tier,
    required this.onBookNow,
  });

  final _Tier tier;
  final VoidCallback onBookNow;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  children: [
                    if (tier.recommended)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: tier.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.workspace_premium_rounded,
                                color: AppColors.onAccentDark, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                color: AppColors.onAccentDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (tier.recommended) const SizedBox(height: 14),
                    Text(
                      tier.name,
                      style: TextStyle(
                        color: tier.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tier.price,
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tier.tagline,
                      style: TextStyle(
                          color: AppColors.mut, fontSize: 15.5, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: tier.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Duration: ${tier.duration}',
                        style: TextStyle(
                          color: tier.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      "What's included",
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...tier.highlights.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle,
                                  color: tier.accent, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  h,
                                  style: TextStyle(
                                    color: AppColors.txt.withOpacity(0.85),
                                    fontSize: 15.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.chipBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'Best for: ${tier.bestFor}',
                        style: TextStyle(
                          color: AppColors.mut,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 12, 24, 12 + MediaQuery.of(context).padding.bottom),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tier.accent,
                      foregroundColor: AppColors.onAccentDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: onBookNow,
                    child: const Text(
                      'Book Now',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The sticky pill switcher between the three tiers, plus a fourth "COMPARE"
// tab that swaps the card below for the comparison table instead of
// selecting a tier. Replaces the old horizontal-scroll cards + the
// comparison table that used to always sit underneath them.
// ─────────────────────────────────────────────────────────────────────────────
class _WheelTabBarDelegate extends SliverPersistentHeaderDelegate {
  _WheelTabBarDelegate({
    required this.selectedIndex,
    required this.showComparison,
    required this.onSelectTier,
    required this.onSelectCompare,
  });

  final int selectedIndex;
  final bool showComparison;
  final ValueChanged<int> onSelectTier;
  final VoidCallback onSelectCompare;

  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            ...List.generate(_tiers.length, (i) {
              final tier = _tiers[i];
              final selected = !showComparison && i == selectedIndex;
              // Short label — the full tier names ("WHEEL ALIGNMENT AND
              // BALANCING") are far too long for a tab.
              final label = switch (i) {
                0 => 'Alignment',
                1 => 'Balancing',
                _ => 'Both',
              };
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelectTier(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: selected ? tier.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? AppColors.onAccentDark
                            : AppColors.txt.withOpacity(0.7),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              );
            }),
            Expanded(
              child: GestureDetector(
                onTap: onSelectCompare,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: showComparison
                        ? const Color(0xFFD4A017)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Compare',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: showComparison
                          ? AppColors.onAccentDark
                          : AppColors.txt.withOpacity(0.7),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _WheelTabBarDelegate oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.showComparison != showComparison;
  }
}
