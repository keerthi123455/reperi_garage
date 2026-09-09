import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data for the "Washing" (QuickCare) category —
/// deliberately NOT fetched from Supabase, matching the pattern used for
/// the Servicing screen. Presented as three tabs (Browse / Compare /
/// Details) instead of one long scroll, with a sticky bottom "BOOK NOW"
/// bar that goes straight to PaymentScreen — the optional doorstep
/// pickup/drop add-on is asked there now, not here.
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

class WashingPackageScreen extends StatefulWidget {
  final String vehicleId;

  const WashingPackageScreen({super.key, required this.vehicleId});

  @override
  State<WashingPackageScreen> createState() => _WashingPackageScreenState();
}

class _WashingPackageScreenState extends State<WashingPackageScreen>
    with SingleTickerProviderStateMixin {
  int _selectedTier = 1; // default to Premium Wash, matching "Most Popular"
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    _tabController.dispose();
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the washing packages.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // The doorstep pickup/drop add-on is now asked on PaymentScreen itself,
  // not here — "Book Now" just goes straight there with the tier's price.
  void _goToPayment(_Tier tier) {
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

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildTabBar(),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBrowseView(),
                  _buildCompareView(),
                  _buildDetailsView(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _buildStickyBar(selected),
        ),
      ),
    );
  }

  // ── HEADER ──
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
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
              child:
                  Icon(Icons.arrow_back, color: AppColors.txt, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'WASHING',
                      style: TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'A Clean That Feels Like New',
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB BAR (segmented-control styled) ──
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'BROWSE'),
            Tab(text: 'COMPARE'),
            Tab(text: 'DETAILS'),
          ],
          labelColor: AppColors.onAccentDark,
          unselectedLabelColor: AppColors.mut,
          labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          indicator: BoxDecoration(
            color: const Color(0xFFD4A017),
            borderRadius: BorderRadius.circular(11),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
        ),
      ),
    );
  }

  // ── TAB 1: BROWSE (vertical stack, easy to compare) ──
  Widget _buildBrowseView() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _tiers.length,
      itemBuilder: (_, i) {
        final tier = _tiers[i];
        final isSelected = i == _selectedTier;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () => setState(() => _selectedTier = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: tier.popular
                    ? Color.alphaBlend(
                        tier.accent.withOpacity(0.12), AppColors.surfaceRaised)
                    : AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? tier.accent : AppColors.line,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tier.popular) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: tier.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'MOST POPULAR',
                                  style: TextStyle(
                                    color: tier.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                              tier.name,
                              style: TextStyle(
                                color: AppColors.txt,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        tier.price,
                        style: TextStyle(
                          color: tier.accent,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tier.tagline,
                    style: TextStyle(color: AppColors.mut, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tier.highlights
                        .take(5)
                        .map((h) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: tier.accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      color: tier.accent, size: 13),
                                  const SizedBox(width: 5),
                                  Text(
                                    h,
                                    style: TextStyle(
                                      color: AppColors.txt,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() => _selectedTier = i);
                            _tabController.animateTo(1);
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.line),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            'COMPARE',
                            style: TextStyle(
                              color: AppColors.txt.withOpacity(0.8),
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _selectedTier = i);
                            _goToPayment(tier);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isSelected ? tier.accent : AppColors.chipBg,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            isSelected ? 'SELECTED ✓' : 'BOOK',
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.onAccentDark
                                  : AppColors.txt.withOpacity(0.8),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── TAB 2: COMPARE (side-by-side table) ──
  Widget _buildCompareView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compare All Washes',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(170),
                1: FixedColumnWidth(90),
                2: FixedColumnWidth(90),
                3: FixedColumnWidth(110),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: AppColors.line, width: 2)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Feature',
                        style: TextStyle(
                          color: AppColors.mut,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ..._tiers.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            children: [
                              Text(
                                t.name.split(' ').first,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: t.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                t.price,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.txt,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
                for (final row in _comparisonRows)
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: AppColors.line.withOpacity(0.4))),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          row.$1,
                          style: TextStyle(
                              color: AppColors.txt.withOpacity(0.8),
                              fontSize: 12),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: _buildComparisonCell(row.$2)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: _buildComparisonCell(row.$3)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: _buildComparisonCell(row.$4)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFFD4A017), size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Choose Based On:',
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._tiers.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: t.accent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${t.price} — ${t.bestFor}',
                              style: TextStyle(
                                color: AppColors.txt.withOpacity(0.7),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCell(String value) {
    if (value == '✅') {
      return const Icon(Icons.check_circle, color: Colors.green, size: 18);
    }
    if (value == '❌') {
      return Icon(Icons.close, color: Colors.red.shade600, size: 18);
    }
    return Text(
      value,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.txt.withOpacity(0.7), fontSize: 11),
    );
  }

  // ── TAB 3: DETAILS (full specs for the selected tier) ──
  Widget _buildDetailsView() {
    final tier = _tiers[_selectedTier];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  tier.accent.withOpacity(0.12), AppColors.surfaceRaised),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tier.accent, width: 2),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'MOST POPULAR',
                      style: TextStyle(
                        color: AppColors.onAccentDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                if (tier.popular) const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        tier.name,
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      tier.price,
                      style: TextStyle(
                        color: tier.accent,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tier.tagline,
                  style: TextStyle(color: AppColors.mut, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Best for: ${tier.bestFor}',
                    style: TextStyle(
                      color: AppColors.mut,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            "What's Included",
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...tier.highlights.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, color: tier.accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        h,
                        style: TextStyle(
                          color: AppColors.txt.withOpacity(0.8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 32),
          Text(
            'Why Choose Reperi',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
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
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(f.$1, color: const Color(0xFFD4A017), size: 24),
                          const SizedBox(height: 10),
                          Text(
                            f.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.txt,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                const Icon(Icons.chat_bubble_rounded,
                    color: Color(0xFF25D366), size: 32),
                const SizedBox(height: 12),
                Text(
                  'Still Not Sure?',
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Our Service Advisors are here to help',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mut, fontSize: 13),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openWhatsApp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('Chat on WhatsApp',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STICKY BOOK NOW BAR ──
  Widget _buildStickyBar(_Tier tier) {
    return GestureDetector(
      onTap: () => _goToPayment(tier),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
          ),
          borderRadius: BorderRadius.circular(20),
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
            Icon(Icons.calendar_month, color: AppColors.onAccentDark, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'BOOK ${tier.name} • ${tier.price}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.onAccentDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
