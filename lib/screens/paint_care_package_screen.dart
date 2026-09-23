import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Static, hardcoded package data for the "Paint Care" (Car360) category —
/// same structural pattern as the other package screens, plus a separate
/// "Premium Add-On Services" section for higher-cost individual upgrades
/// (ceramic coating, graphene coating, PPF, paint correction) that are
/// deliberately NOT bundled into the ₹2,999 package.
class _Tier {
  final String name;
  final String price;
  final String tagline;
  final String protection;
  final String bestFor;
  final Color accent;
  final bool recommended;
  final List<String> highlights;

  const _Tier({
    required this.name,
    required this.price,
    required this.tagline,
    required this.protection,
    required this.bestFor,
    required this.accent,
    required this.highlights,
    this.recommended = false,
  });
}

class _AddOn {
  final String name;
  final String startingPrice;
  final IconData icon;
  final List<String> highlights;

  const _AddOn({
    required this.name,
    required this.startingPrice,
    required this.icon,
    required this.highlights,
  });
}

const _tiers = [
  _Tier(
    name: 'PAINT SHINE PACKAGE',
    price: '₹1,999',
    tagline: 'Restore gloss and protect your paint',
    protection: 'Up to 2–3 months',
    bestFor: "Dull paint, light swirl marks, and maintaining your car's shine.",
    accent: Color(0xFF4FA3E3),
    highlights: [
      'Premium Snow Foam Wash',
      'Surface Decontamination Wash',
      'Bug & Tar Removal',
      'Paint Gloss Enhancement Polish',
      'Machine Wax Application',
      'Exterior Plastic Trim Dressing',
      'Tyre Shine',
      'Exterior Glass Cleaning',
      'Paint Condition Inspection',
    ],
  ),
  _Tier(
    name: 'PAINT PROTECTION PACKAGE',
    price: '₹2,999',
    tagline: 'Long-lasting shine with enhanced paint protection',
    protection: 'Up to 6 months',
    bestFor:
        'Customers wanting better protection and an easier-to-clean finish.',
    accent: Color(0xFFD4A017),
    recommended: true,
    highlights: [
      'Everything in Paint Shine Package',
      'One-Step Machine Paint Correction',
      'Ceramic Spray Coating',
      'Hydrophobic Water-Repellent Protection',
      'UV Protection for Paint',
      'Minor Scratch & Swirl Reduction',
      'Alloy Wheel Protection',
      'Exterior Plastic Restoration',
      'Rain-Repellent Glass Treatment',
      'Final Paint Gloss Inspection',
    ],
  ),
];

const _addOns = [
  _AddOn(
    name: 'Ceramic Coating',
    startingPrice: '₹12,999',
    icon: Icons.shield_rounded,
    highlights: [
      '1–3 Year Paint Protection',
      'Deep Gloss Finish',
      'Hydrophobic Water Beading',
      'UV Protection',
      'Easier Cleaning',
      'Chemical Resistance',
    ],
  ),
  _AddOn(
    name: 'Graphene Coating',
    startingPrice: '₹16,999',
    icon: Icons.diamond_rounded,
    highlights: [
      'Enhanced Ceramic Protection',
      'Better Heat Resistance',
      'Superior Gloss',
      'Water & Dirt Repellency',
      'Increased Durability',
    ],
  ),
  _AddOn(
    name: 'Paint Protection Film (PPF)',
    startingPrice: '₹49,999',
    icon: Icons.layers_rounded,
    highlights: [
      'Self-Healing Film',
      'Stone Chip Protection',
      'Scratch Resistance',
      'UV Protection',
      'High Gloss or Matte Finish',
      'Long-Term Paint Preservation',
    ],
  ),
  _AddOn(
    name: 'Paint Correction',
    startingPrice: '₹7,999',
    icon: Icons.auto_fix_high_rounded,
    highlights: [
      'Multi-Stage Machine Polishing',
      'Removes Swirl Marks',
      'Removes Oxidation',
      'Restores Paint Clarity',
      'High Gloss Finish',
    ],
  ),
];

// (feature, ₹1,999, ₹2,999)
const _comparisonRows = [
  ('Snow Foam Wash', '✅', '✅'),
  ('Paint Polish', '✅', '✅'),
  ('Machine Wax', '✅', '✅'),
  ('Paint Correction', '❌', 'One-Step'),
  ('Ceramic Spray Protection', '❌', '✅'),
  ('UV Protection', '❌', '✅'),
  ('Water Repellency', '❌', '✅'),
  ('Minor Scratch Removal', '❌', '✅'),
  ('Glass Treatment', '❌', '✅'),
  ('Protection Duration', '2–3 Months', 'Up to 6 Months'),
];

class PaintCarePackageScreen extends StatefulWidget {
  final String vehicleId;

  /// When set (matches one of the tier names above, case-insensitive),
  /// that tier is pre-selected and scrolled into view on open.
  final String? highlightPackage;

  const PaintCarePackageScreen({super.key, required this.vehicleId, this.highlightPackage});

  @override
  State<PaintCarePackageScreen> createState() =>
      _PaintCarePackageScreenState();
}

class _PaintCarePackageScreenState extends State<PaintCarePackageScreen> {
  int _selectedTier = 1; // default to Paint Protection Package (recommended)

  // ── Booking selection ───────────────────────────────────────────────
  // Separate from `_selectedTier` above, which only tracks which card is
  // being *viewed* in the horizontal scroller. A package is only actually
  // part of the booking once its own "Add Package" button is tapped, and
  // add-ons are independent of any package — either can be booked alone.
  _Tier? _includedTier;
  final Set<_AddOn> _selectedAddOns = {};

  int _parsePrice(String price) =>
      int.parse(price.replaceAll(RegExp(r'[^0-9]'), ''));

  int get _totalRupees {
    var total = 0;
    if (_includedTier != null) total += _parsePrice(_includedTier!.price);
    for (final addOn in _selectedAddOns) {
      total += _parsePrice(addOn.startingPrice);
    }
    return total;
  }

  int get _bookedItemCount =>
      (_includedTier != null ? 1 : 0) + _selectedAddOns.length;

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
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the paint care packages.")}',
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

  void _toggleTier(_Tier tier) {
    final adding = _includedTier != tier;
    setState(() => _includedTier = adding ? tier : null);
    if (adding) _showAddedPopup(tier.name);
  }

  void _toggleAddOn(_AddOn addOn) {
    final adding = !_selectedAddOns.contains(addOn);
    setState(() {
      if (adding) {
        _selectedAddOns.add(addOn);
      } else {
        _selectedAddOns.remove(addOn);
      }
    });
    if (adding) _showAddedPopup(addOn.name);
  }

  void _showAddedPopup(String name) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Added',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => _AddedConfirmationDialog(name: name),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  void _showPackageDetails(_Tier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _PackageDetailsSheet(
        tier: tier,
        isAdded: _includedTier == tier,
        onAddPackage: () {
          Navigator.pop(sheetContext);
          _toggleTier(tier);
        },
      ),
    );
  }

  /// Simplified summary card — just enough to identify and compare the
  /// package at a glance. Full highlights/best-for copy lives in the detail
  /// sheet ([_showPackageDetails]) instead of crowding this card.
  Widget _buildPackageCard(_Tier tier, Color recommendedCardColor) {
    final isIncluded = _includedTier == tier;
    return GestureDetector(
      onTap: () => _showPackageDetails(tier),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color:
              tier.recommended ? recommendedCardColor : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isIncluded ? tier.accent : tier.accent.withOpacity(0.25),
            width: isIncluded ? 2 : 1,
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
            if (tier.recommended || isIncluded)
              Row(
                children: [
                  if (tier.recommended)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
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
                  if (isIncluded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: tier.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'ADDED',
                        style: TextStyle(
                          color: tier.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
            if (tier.recommended || isIncluded) const SizedBox(height: 14),
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
                'Protection: ${tier.protection}',
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

  void _book() {
    if (_bookedItemCount == 0) return;
    final items = <Map<String, dynamic>>[
      if (_includedTier != null)
        {
          'name': _includedTier!.name,
          'price': _parsePrice(_includedTier!.price),
        },
      for (final addOn in _selectedAddOns)
        {'name': addOn.name, 'price': _parsePrice(addOn.startingPrice)},
    ];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: _includedTier?.name ?? 'Paint Care Add-Ons',
          price: '₹$_totalRupees',
          duration: '2-3 hrs',
          vehicleId: widget.vehicleId,
          billItems: items,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                              'PAINT CARE',
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
                          "Restore Your Car's\nShowroom Shine",
                          style: TextStyle(
                            color: AppColors.txt,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'From a quick gloss refresh to long-lasting paint protection — pick the level of shine your car deserves.',
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
                        'Tap a package below to see full details.',
                        style: TextStyle(color: AppColors.mut, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              // ── STICKY PACKAGE SWITCHER ──
              SliverPersistentHeader(
                pinned: true,
                delegate: _PackageTabBarDelegate(
                  selectedIndex: _selectedTier,
                  onSelect: (i) => setState(() => _selectedTier = i),
                ),
              ),

              // ── SELECTED PACKAGE CARD ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _buildPackageCard(
                      _tiers[_selectedTier], recommendedCardColor),
                ),
              ),

              // ── PREMIUM ADD-ON SERVICES ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Premium Add-On Services',
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Offered as individual upgrades rather than bundled into a package — quoted after inspection.',
                        style: TextStyle(
                            color: AppColors.mut,
                            fontSize: 12.5,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final addOn = _addOns[index];
                    final isAdded = _selectedAddOns.contains(addOn);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4A017)
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(addOn.icon,
                                      color: const Color(0xFFD4A017),
                                      size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        addOn.name,
                                        style: TextStyle(
                                          color: AppColors.txt,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Starting from ${addOn.startingPrice}',
                                        style: const TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: addOn.highlights
                                  .map((h) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppColors.chipBg,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          h,
                                          style: TextStyle(
                                            color: AppColors.txt.withOpacity(0.7),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isAdded
                                      ? const Color(0xFFD4A017)
                                          .withOpacity(0.12)
                                      : null,
                                  side: const BorderSide(
                                      color: Color(0xFFD4A017)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                                onPressed: () => _toggleAddOn(addOn),
                                child: Text(
                                  isAdded ? 'Added to booking' : 'Add On',
                                  style: const TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _addOns.length,
                ),
              ),

              // ── TALK TO ADVISOR ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 140),
                  child: Column(
                    children: [
                      Text('Not sure which option to pick?',
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

          // ── STICKY BOOK BAR ──
          // Enabled once anything is added — a package, add-ons, or both;
          // a package on its own is never required to book add-ons.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GestureDetector(
                  onTap: _bookedItemCount > 0 ? _book : null,
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: _bookedItemCount > 0
                          ? const LinearGradient(
                              colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                            )
                          : null,
                      color: _bookedItemCount > 0 ? null : AppColors.chipBg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: _bookedItemCount > 0
                          ? [
                              BoxShadow(
                                color: const Color(0xFFD4A017).withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _bookedItemCount > 0
                                ? 'BOOK $_bookedItemCount ITEM${_bookedItemCount > 1 ? 'S' : ''} • ₹$_totalRupees'
                                : 'Add a package or add-on to book',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _bookedItemCount > 0
                                  ? AppColors.onAccentDark
                                  : AppColors.mut,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
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
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full package detail sheet, opened by tapping either package card. Carries
// the "Add Package" action itself — the inline card is a tap target only,
// so this is the one and only place that button lives.
// ─────────────────────────────────────────────────────────────────────────────
class _PackageDetailsSheet extends StatelessWidget {
  const _PackageDetailsSheet({
    required this.tier,
    required this.isAdded,
    required this.onAddPackage,
  });

  final _Tier tier;
  final bool isAdded;
  final VoidCallback onAddPackage;

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
                        'Protection: ${tier.protection}',
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
                      backgroundColor:
                          isAdded ? AppColors.chipBg : tier.accent,
                      foregroundColor: isAdded
                          ? AppColors.txt.withOpacity(0.7)
                          : AppColors.onAccentDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: onAddPackage,
                    child: Text(
                      isAdded ? 'Remove Package' : 'Add Package',
                      style: const TextStyle(
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
// The "added to booking" confirmation — a large, centered, self-dismissing
// popup with a bouncy check-mark entrance. Replaces the old plain AlertDialog
// (small text, static appearance, needed a manual OK tap).
// ─────────────────────────────────────────────────────────────────────────────
class _AddedConfirmationDialog extends StatefulWidget {
  const _AddedConfirmationDialog({required this.name});

  final String name;

  @override
  State<_AddedConfirmationDialog> createState() =>
      _AddedConfirmationDialogState();
}

class _AddedConfirmationDialogState extends State<_AddedConfirmationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _iconController;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _iconScale = CurvedAnimation(
      parent: _iconController,
      curve: Curves.elasticOut,
    );
    _iconController.forward();

    // Self-dismissing, same pattern as ErrorDisplay's premium toast — pops
    // this dialog's own route via its own context, so it can never end up
    // popping something else pushed on top of it in the meantime.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _iconScale,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFFD4A017),
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.txt,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Added to your booking',
                style: TextStyle(
                  color: AppColors.mut,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The sticky pill switcher between the two packages, replacing the old
// horizontal-scroll cards + separate comparison table below them.
// ─────────────────────────────────────────────────────────────────────────────
class _PackageTabBarDelegate extends SliverPersistentHeaderDelegate {
  _PackageTabBarDelegate({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

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
          children: List.generate(_tiers.length, (i) {
            final tier = _tiers[i];
            final selected = i == selectedIndex;
            final label = tier.name.replaceAll(' PACKAGE', '');
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
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
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PackageTabBarDelegate oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex;
  }
}
