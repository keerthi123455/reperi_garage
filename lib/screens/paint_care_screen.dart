import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class PaintCareScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  const PaintCareScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<PaintCareScreen> createState() => _PaintCareScreenState();
}

class _PaintCareScreenState extends State<PaintCareScreen> {
  static Color get _bg => AppColors.ink;

  static Color get _card => AppColors.surfaceRaised;

  static const Color _gold = Color(0xFFD4A84B);

  // Pure white/black inside _buildHero() stay literal (photo-overlay
  // legibility, not page theme) — this getter is only for page text.
  static Color get _white => AppColors.txt;

  static Color get _grey => AppColors.mut;

  static Color get _cardBorder => AppColors.line;

  int selectedPackage = -1;

  List<Map<String, dynamic>> packages = [
    {
      'title': 'QUICK POLISH',
      'subtitle': 'Basic Shine Enhancement',
      'price': '₹599',
      'duration': '45 mins',
      'icon': Icons.auto_awesome_outlined,
      'features': [
        'Exterior wash',
        'Quick buffing',
        'Tyre shine',
        'Water spot removal',
        'Gloss enhancement',
      ],
      'details':
          'Perfect for restoring daily shine and improving overall exterior appearance quickly.',
    },
    {
      'title': 'SCRATCH CONTROL',
      'subtitle': 'Scratch & Swirl Correction',
      'price': '₹1499',
      'duration': '2 hrs',
      'icon': Icons.cleaning_services_outlined,
      'features': [
        'Scratch removal',
        'Swirl correction',
        'Paint enhancement',
        'Machine buffing',
        'Gloss restoration',
      ],
      'details':
          'Designed to remove minor scratches, swirl marks and restore paint smoothness.',
    },
    {
      'title': 'RUST CONTROL',
      'subtitle': 'Anti-Rust Protection',
      'price': '₹2999',
      'duration': '3 hrs',
      'icon': Icons.shield_outlined,
      'features': [
        'Underbody coating',
        'Rust treatment',
        'Corrosion prevention',
        'Protective sealant',
        'Metal protection layer',
      ],
      'details':
          'Advanced anti-rust treatment protecting your vehicle body from corrosion and damage.',
    },
    {
      'title': 'PREMIUM PAINT RESTORE',
      'subtitle': 'Paint Correction & Restoration',
      'price': '₹4999',
      'duration': '5 hrs',
      'icon': Icons.format_paint_outlined,
      'features': [
        'Paint correction',
        'Multi-stage polishing',
        'Deep gloss enhancement',
        'Oxidation removal',
        'Premium machine finish',
      ],
      'details':
          'Restores dull paint, oxidation and faded surfaces back to premium glossy finish.',
    },
    {
      'title': 'VINYL & WRAP STUDIO',
      'subtitle': 'Exterior Customization',
      'price': '₹7999',
      'duration': '1 day',
      'icon': Icons.layers_outlined,
      'features': [
        'Vinyl wrap installation',
        'Gloss/matte finish',
        'Roof wrap',
        'Mirror accents',
        'Color customization',
        'Paint-safe removal',
      ],
      'details':
          'Premium wrapping solutions for luxury styling, customization and exterior transformation.',
    },
    {
      'title': 'SHOWROOM SHINE+',
      'subtitle': 'Luxury Exterior Restoration',
      'price': '₹10999',
      'duration': '2 days',
      'icon': Icons.diamond_outlined,
      'features': [
        'Ceramic coating',
        'Deep detailing',
        'Paint refinement',
        'Hydrophobic protection',
        'Luxury polishing',
        'Exterior rejuvenation',
        'PPF enhancement',
      ],
      'details':
          'Ultimate luxury package delivering showroom-level shine, protection and exterior perfection.',
    },
  ];

  @override
  void initState() {
    super.initState();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
    _fetchPackageData();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _fetchPackageData() async {
    try {
      final rows = await CatalogService.fetchByCategory('Paint Care');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      const keyOrder = [
        'paint_quick_polish',
        'paint_scratch_control',
        'paint_rust_control',
        'paint_premium_restore',
        'paint_vinyl_wrap_studio',
        'paint_showroom_shine_plus',
      ];

      setState(() {
        for (var i = 0; i < keyOrder.length && i < packages.length; i++) {
          final row = byKey[keyOrder[i]];
          if (row != null) {
            packages[i]['price'] = row['price'];
            packages[i]['duration'] = row['duration'];
            packages[i]['details'] = row['details'] ?? packages[i]['details'];
            packages[i]['features'] = List<String>.from(row['services']);
          }
        }
      });
    } catch (e) {
      // Keep the hardcoded fallback values above if the fetch fails.
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPackages(),
                        _buildWhyUs(),
                        _buildTracking(),
                        const SizedBox(height: 140),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyBar(),
          ),
        ],
      ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────
  Widget _buildHero() {
    return Stack(
      children: [
        SizedBox(
          height: 420,
          width: double.infinity,
          child: Image.asset(
            'assets/images/paint_hero.png',
            fit: BoxFit.cover,
          ),
        ),
        // Gradient scrim over the photo. Built from AppColors.ink rather
        // than a literal black so it flips to a light scrim in light mode
        // instead of staying a dark hue the white hero text can't sit on.
        Container(
          height: 420,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.ink,
                AppColors.ink.withOpacity(0.25),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(height: 110),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PAINT & EXTERIOR CARE',
                    style: TextStyle(
                      color: AppColors.onAccentDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Paint Care',
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Luxury exterior restoration, protection and finish enhancement.',
                  style: TextStyle(
                    color: AppColors.txt.withOpacity(0.7),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _gold.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Advanced polishing, ceramic coating, wraps, PPF and luxury paint restoration using premium-grade products.',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── EXTERIOR PACKAGES ────────────────────────────────────────────
  Widget _buildPackages() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exterior packages',
            style: TextStyle(
              color: _white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a card to select and book your service',
            style: TextStyle(color: _grey, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          ...List.generate(packages.length, (index) {
            final p = packages[index];
            final selected = selectedPackage == index;

            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedPackage = index;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 18),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? _gold : _cardBorder,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _gold.withOpacity(0.35),
                            blurRadius: 18,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(p['icon'] as IconData, color: _gold),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p['title'],
                                style: TextStyle(
                                  color: _white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p['subtitle'],
                                style: TextStyle(color: _grey, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          p['price'],
                          style: TextStyle(
                            color: _gold,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ...(p['features'] as List<String>).map((f) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: _gold, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                f,
                                style: TextStyle(color: _white, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _gold.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What we do',
                            style: TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            p['details'],
                            style: TextStyle(
                              color: _white,
                              height: 1.6,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected ? _gold : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? _gold : _cardBorder,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          selected ? 'Selected' : 'Select this package',
                          style: TextStyle(
                            color: selected ? AppColors.onAccentDark : _white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── WHY CHOOSE US ────────────────────────────────────────────────
  Widget _buildWhyUs() {
    final items = [
      (Icons.verified_outlined, 'Paint-safe\nProducts'),
      (Icons.shield_outlined, 'Imported\nCoatings'),
      (Icons.diamond_outlined, 'OEM\nFinish'),
      (Icons.engineering_outlined, 'Certified\nDetailers'),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why choose us',
            style: TextStyle(
              color: _white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: items.map((item) {
              return Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: _gold.withOpacity(0.3)),
                      ),
                      child: Icon(item.$1, color: _gold, size: 24),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _white,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── LIVE TRACKING ────────────────────────────────────────────────
  Widget _buildTracking() {
    // A warm, gold-tinted card — blended over the current mode's surface so
    // it stays subtle in both themes instead of a fixed near-black tint.
    final trackingBg = Color.alphaBlend(
      _gold.withOpacity(0.12),
      AppColors.surfaceRaised,
    );

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: trackingBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            'Live tracking included',
            style: TextStyle(
              color: _gold,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _trackItem(Icons.camera_alt_outlined, 'Before/after photos'),
                    const SizedBox(height: 10),
                    _trackItem(Icons.list_alt_outlined, 'Process updates'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _trackItem(Icons.notifications_outlined, 'Exterior inspection'),
                    const SizedBox(height: 10),
                    _trackItem(Icons.history_outlined, 'Digital service history'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trackItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: _gold, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: _white, fontSize: 13),
          ),
        ),
      ],
    );
  }

  // ── STICKY BOTTOM BAR ────────────────────────────────────────────
  Widget _buildStickyBar() {
    final hasSelection = selectedPackage != -1;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () {
            if (selectedPackage == -1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select a package'),
                ),
              );
              return;
            }

            final selected = packages[selectedPackage];

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentScreen(
                  title: selected['title'],
                  price: selected['price'],
                  duration: selected['duration'],
                  vehicleId: widget.vehicle['id'].toString(),
                ),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              color: hasSelection ? _gold : AppColors.chipBg,
              borderRadius: BorderRadius.circular(16),
              border: hasSelection ? null : Border.all(color: AppColors.line),
              boxShadow: hasSelection
                  ? [
                      BoxShadow(
                        color: _gold.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    hasSelection ? 'Book Now' : 'Select a package first',
                    style: TextStyle(
                      color: hasSelection ? AppColors.onAccentDark : AppColors.mut,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (hasSelection) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right, color: AppColors.onAccentDark),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
