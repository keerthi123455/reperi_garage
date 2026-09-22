import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data — same idea as TwoWheelerServicingScreen,
/// deliberately NOT fetched from Supabase. Unlike that screen's tiers
/// (identical checklist, price-only difference), these two wash plans each
/// have their own feature list.
class _WashTier {
  final String label;
  final String tagline;
  final int price;
  final bool popular;
  final List<String> features;

  const _WashTier({
    required this.label,
    required this.tagline,
    required this.price,
    required this.features,
    this.popular = false,
  });
}

const _tiers = [
  _WashTier(
    label: 'QUICK WASH',
    tagline: 'Everyday clean',
    price: 149,
    features: [
      'Foam Wash',
      'Pressure Rinse',
      'Hand Wash',
      'Tyre & Rim Clean',
      'Microfiber Dry',
    ],
  ),
  _WashTier(
    label: 'PREMIUM WASH',
    tagline: 'Deep clean & shine',
    price: 299,
    popular: true,
    features: [
      'Premium Foam',
      'Deep Rim Clean',
      'Chain Clean & Lube',
      'Tyre Dressing',
      'Plastic Polish',
      'Microfiber Finish',
    ],
  ),
];

/// Formatting helper — every price in this screen is well under a lakh, so
/// a single thousands-comma is all Indian grouping actually needs here.
String _rupees(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return '₹$digits';
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  return '₹$head,$tail';
}

class TwoWheelerWashingScreen extends StatefulWidget {
  final String vehicleId;

  const TwoWheelerWashingScreen({super.key, required this.vehicleId});

  @override
  State<TwoWheelerWashingScreen> createState() =>
      _TwoWheelerWashingScreenState();
}

class _TwoWheelerWashingScreenState extends State<TwoWheelerWashingScreen> {
  // Default to Premium Wash, matching its "⭐" pick in the source content.
  int _selectedTier = 1;
  // Open by default on the pre-selected tier — the checklist is the whole
  // point of this screen, so nobody should have to discover the tap first.
  bool _expanded = true;

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

  void _onTierTap(int i) {
    setState(() {
      if (_selectedTier == i) {
        _expanded = !_expanded;
      } else {
        _selectedTier = i;
        _expanded = true;
      }
    });
  }

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the two-wheeler washing packages.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _bookNow() {
    final tier = _tiers[_selectedTier];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: tier.label,
          price: _rupees(tier.price),
          duration: '30-45 mins',
          vehicleId: widget.vehicleId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              Text(
                'Choose Your Wash',
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a plan to see what\'s included.',
                style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              ..._tiers.asMap().entries.map((e) => _buildTierCard(e.key, e.value)),
              const SizedBox(height: 8),
              _buildCompareSection(),
              const SizedBox(height: 20),
              _buildWhatsAppCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _buildStickyBar(),
        ),
      ),
    );
  }

  // ── HEADER ──
  Widget _buildHeader() {
    return Row(
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
              child: Icon(Icons.arrow_back, color: AppColors.txt, size: 20),
            ),
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
                'Keep Your Bike Spotless',
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── PRICE TIER CARD (tap to select + expand its checklist) ──
  Widget _buildTierCard(int i, _WashTier tier) {
    final isSelected = i == _selectedTier;
    final isOpen = isSelected && _expanded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? Color.alphaBlend(
                  const Color(0xFFD4A017).withOpacity(0.10), AppColors.surfaceRaised)
              : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4A017) : AppColors.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _onTierTap(i),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: isSelected ? const Color(0xFFD4A017) : AppColors.mut,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  tier.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.txt,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (tier.popular) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.star_rounded,
                                    color: Color(0xFFD4A017), size: 16),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tier.tagline,
                            style: TextStyle(color: AppColors.mut, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _rupees(tier.price),
                      style: const TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.mut,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState:
                  isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: AppColors.line, height: 1),
                    const SizedBox(height: 12),
                    Text(
                      "What's Included",
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...tier.features.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Color(0xFFD4A017), size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    color: AppColors.txt.withOpacity(0.8),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  // ── COMPARE CHART (side-by-side, since the two plans genuinely differ) ──
  Widget _buildCompareSection() {
    final allFeatures = <String>[];
    for (final tier in _tiers) {
      for (final feature in tier.features) {
        if (!allFeatures.contains(feature)) allFeatures.add(feature);
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compare Plans',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 16,
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
                1: FixedColumnWidth(110),
                2: FixedColumnWidth(110),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line, width: 2)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Feature',
                        style: TextStyle(color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    ..._tiers.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            children: [
                              Text(
                                t.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _rupees(t.price),
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
                for (final feature in allFeatures)
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.line.withOpacity(0.4))),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          feature,
                          style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 12),
                        ),
                      ),
                      ..._tiers.map((t) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: t.features.contains(feature)
                                  ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                                  : Icon(Icons.close, color: Colors.red.shade600, size: 18),
                            ),
                          )),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── WHATSAPP HELP CARD ──
  Widget _buildWhatsAppCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366), size: 32),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Chat on WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // ── STICKY BOOK NOW BAR ──
  Widget _buildStickyBar() {
    final tier = _tiers[_selectedTier];
    return GestureDetector(
      onTap: _bookNow,
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
            const Icon(Icons.calendar_month, color: Colors.black, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'BOOK ${tier.label} • ${_rupees(tier.price)}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
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
