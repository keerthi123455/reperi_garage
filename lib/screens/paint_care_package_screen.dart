import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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

  const PaintCarePackageScreen({super.key, required this.vehicleId});

  @override
  State<PaintCarePackageScreen> createState() =>
      _PaintCarePackageScreenState();
}

class _PaintCarePackageScreenState extends State<PaintCarePackageScreen> {
  int _selectedTier = 1; // default to Paint Protection Package (recommended)

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent("Hi, I have a question about the paint care packages.")}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _bookTier(_Tier tier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: tier.name,
          price: tier.price,
          duration: '2-3 hrs',
          vehicleId: widget.vehicleId,
        ),
      ),
    );
  }

  void _bookAddOn(_AddOn addOn) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: addOn.name,
          price: addOn.startingPrice,
          duration: 'Quoted on inspection',
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
                        const Text(
                          "Restore Your Car's\nShowroom Shine",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'From a quick gloss refresh to long-lasting paint protection — pick the level of shine your car deserves.',
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
                        'Choose Your Package',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Two levels of paint care, each with a clear protection duration.',
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
                          width: tier.recommended ? 260 : 230,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: tier.recommended
                                ? const Color(0xFF1C1806)
                                : const Color(0xFF141414),
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
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.workspace_premium_rounded,
                                          color: Colors.black, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'RECOMMENDED',
                                        style: TextStyle(
                                          color: Colors.black,
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
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: tier.accent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Protection: ${tier.protection}',
                                  style: TextStyle(
                                    color: tier.accent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
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
                                  onPressed: () => _bookTier(tier),
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
                            0: FixedColumnWidth(180),
                            1: FixedColumnWidth(100),
                            2: FixedColumnWidth(110),
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
                                  child: Text('₹1,999',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Color(0xFF4FA3E3),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text('₹2,999',
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
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── PREMIUM ADD-ON SERVICES ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Premium Add-On Services',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Offered as individual upgrades rather than bundled into a package — quoted after inspection.',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
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
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: const Color(0xFF3A3A3A)),
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
                                        style: const TextStyle(
                                          color: Colors.white,
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
                                          color: Colors.white.withOpacity(
                                              0.05),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          h,
                                          style: const TextStyle(
                                            color: Colors.white70,
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
                                  side: const BorderSide(
                                      color: Color(0xFFD4A017)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                ),
                                onPressed: () => _bookAddOn(addOn),
                                child: Text(
                                  'Book ${addOn.name}',
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
                  onTap: () => _bookTier(selected),
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
                        Expanded(
                          child: Text(
                            'BOOK ${selected.name} • ${selected.price}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black,
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