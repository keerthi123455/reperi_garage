import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class DentingTinkeringScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  const DentingTinkeringScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<DentingTinkeringScreen> createState() => _DentingTinkeringScreenState();
}

class _DentingTinkeringScreenState extends State<DentingTinkeringScreen> {
  static Color get _bg => AppColors.ink;
  static Color get _card => AppColors.surfaceRaised;
  static const Color _gold = Color(0xFFD4A84B);
  static Color get _white => AppColors.txt;
  static Color get _grey => AppColors.mut;
  static Color get _cardBorder => AppColors.line;

  int selectedPackage = -1;

  List<Map<String, dynamic>> packages = [
    {
      'title': 'BASIC INSPECTION',
      'subtitle': 'Damage Assessment & Estimate',
      'price': '₹99',
      'duration': '20 mins',
      'icon': Icons.search,
      'features': [
        'Dent inspection',
        'Paint damage check',
        'Panel alignment check',
        'Repair estimate',
        'Insurance guidance',
      ],
      'details':
          'Professional inspection and repair consultation for dents, scratches, and accident damage.',
    },
    {
      'title': 'QUICK DENT FIX',
      'subtitle': 'Minor Dent & Scratch Repair',
      'price': '₹1499',
      'duration': '2 hrs',
      'icon': Icons.build_circle_outlined,
      'features': [
        'Minor dent removal',
        'Scratch correction',
        'Panel finishing',
        'Basic touch-up',
        'FREE inspection',
        'FREE polish',
      ],
      'details':
          'Perfect for small dents and scratches caused by daily driving and parking incidents.',
    },
    {
      'title': 'PANEL RESTORE',
      'subtitle': 'Single Panel Restoration',
      'price': '₹3999',
      'duration': '5 hrs',
      'icon': Icons.car_repair_outlined,
      'features': [
        'Deep dent repair',
        'Paint blending',
        'Panel reshaping',
        'Machine polishing',
        'FREE inspection',
        'FREE polish',
      ],
      'details':
          'Advanced restoration package focused on restoring damaged doors, bumpers, and side panels.',
    },
    {
      'title': 'BODY LINE CORRECTION',
      'subtitle': 'Multi-Panel Alignment',
      'price': '₹4999',
      'duration': '6 hrs',
      'icon': Icons.auto_fix_high_outlined,
      'features': [
        'Multi-panel correction',
        'Bumper alignment',
        'Precision reshaping',
        'Machine finishing',
        'Paint refinement',
        'FREE inspection',
        'FREE polish',
      ],
      'details':
          'Premium body correction service for restoring factory body lines and alignment.',
    },
    {
      'title': 'ACCIDENT RESTORATION',
      'subtitle': 'Major Damage Recovery',
      'price': '₹7999',
      'duration': '1 day',
      'icon': Icons.car_crash_outlined,
      'features': [
        'Structural correction',
        'Deep restoration',
        'Paint correction',
        'Body alignment',
        'Insurance assistance',
        'FREE inspection',
        'FREE polish',
      ],
      'details':
          'Comprehensive accident repair package for heavily damaged vehicles requiring structural correction.',
    },
    {
      'title': 'SIGNATURE RESTORATION+',
      'subtitle': 'Luxury Finish Restoration',
      'price': '₹10999',
      'duration': '2 days',
      'icon': Icons.diamond_outlined,
      'features': [
        'Complete body rejuvenation',
        'Luxury paint finishing',
        'Advanced paint refinement',
        'Ceramic finishing',
        'Premium detailing',
        'Insurance support',
        'FREE inspection',
        'FREE polish',
      ],
      'details':
          'Ultimate showroom-level restoration package with luxury finishing and advanced detailing.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchPackageData();
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

  Future<void> _fetchPackageData() async {
    try {
      final rows = await CatalogService.fetchByCategory('Denting & Tinkering');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      const keyOrder = [
        'dent_basic_inspection',
        'dent_quick_fix',
        'dent_panel_restore',
        'dent_body_line_correction',
        'dent_accident_restoration',
        'dent_signature_restoration_plus',
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

  void _bookSelected() {
    if (selectedPackage == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a package',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
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
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(),
                    _buildPackages(),
                    _buildWhyUs(),
                    _buildLiveTracking(),
                    const SizedBox(height: 140),
                  ],
                ),
              ),
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
            'assets/images/denting_hero.jpeg',
            fit: BoxFit.cover,
          ),
        ),
        // Gradient: dark bottom → lighter top, for text legibility over the
        // photo. Built from AppColors.ink rather than a literal black so it
        // flips to a light scrim in light mode instead of staying a dark
        // hue the white hero text can't sit on.
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                const SizedBox(height: 90),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'DENTING & TINKERING',
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
                  'Denting & Tinkering',
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
                  'Precision body restoration and premium finish repair.',
                  style: TextStyle(
                    color: AppColors.txt.withOpacity(0.7),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _gold.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Premium body studio',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Luxury-grade denting, tinkering, and accident restoration using precision tools and expert craftsmanship.',
                        style: TextStyle(
                          color: AppColors.txt,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── RESTORATION PACKAGES ─────────────────────────────────────────
  Widget _buildPackages() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Restoration packages',
            style: TextStyle(
              color: _white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a package to see what\'s included and book',
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                  fontSize: 20,
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
                        const SizedBox(width: 8),
                        Text(
                          p['price'],
                          style: TextStyle(
                            color: _gold,
                            fontSize: 26,
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
                                style: TextStyle(color: _white, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.chipBg,
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
                          const SizedBox(height: 10),
                          Text(
                            p['details'],
                            style: TextStyle(
                              color: _white,
                              height: 1.6,
                              fontSize: 15,
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
                        border: Border.all(color: selected ? _gold : _cardBorder),
                      ),
                      child: Center(
                        child: Text(
                          selected ? 'Selected' : 'Select',
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
      (Icons.construction_outlined, 'Paint-safe\nTools'),
      (Icons.verified_user_outlined, 'Insurance\nSupport'),
      (Icons.diamond_outlined, 'OEM\nFinish'),
      (Icons.engineering_outlined, 'Expert\nTechnicians'),
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
          const SizedBox(height: 20),
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
  Widget _buildLiveTracking() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.track_changes, color: _gold, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Live tracking included',
                style: TextStyle(
                  color: _white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _trackItem(Icons.camera_alt_outlined, 'Before/after photos'),
                    const SizedBox(height: 14),
                    _trackItem(Icons.list_alt_outlined, 'Repair progress'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _trackItem(Icons.notifications_outlined, 'Real-time updates'),
                    const SizedBox(height: 14),
                    _trackItem(Icons.history_outlined, 'Digital repair history'),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _gold, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: _white, fontSize: 14),
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
          onTap: _bookSelected,
          child: Container(
            width: double.infinity,
            height: 56,
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
              child: Text(
                hasSelection ? 'Book Now' : 'Select a package',
                style: TextStyle(
                  color: hasSelection ? AppColors.onAccentDark : _grey,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
