import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class TyreCareScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  const TyreCareScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<TyreCareScreen> createState() => _TyreCareScreenState();
}

class _TyreCareScreenState extends State<TyreCareScreen> {
  // ── State ────────────────────────────────────────────────────────
  String? selectedTyreBrand;
  String? selectedAlloyBrand;
  int? selectedWheelSize;

  final GlobalKey _packagesKey = GlobalKey();

  // ── Data ─────────────────────────────────────────────────────────
  final List<String> _serviceChips = [
    'Wheel Alignment',
    'Wheel Balancing',
    'Tyre Rotation',
    'Nitrogen Air',
    'Tyre Replacement',
    'Alloy Wheels',
    'Puncture Repair',
    'Suspension Check',
    'Brake Inspection',
    'Road Grip Optimization',
  ];

  final List<String> _tyreBrands = [
    'mrf',
    'ceat',
    'michelin',
    'continental',
    'bridgestone',
  ];

  final List<String> _tyreBrandLabels = [
    'MRF',
    'CEAT',
    'Michelin',
    'Continental',
    'Bridgestone',
  ];

  final List<String> _alloyBrands = [
    'BBS',
    'OZ Racing',
    'Enkei',
    'Rotiform',
    'Rays',
    'Vorsteiner',
    'Fuel',
  ];

  final List<int> _wheelSizes = [15, 16, 17, 18, 19, 20];

  final List<Map<String, dynamic>> _upgradeItems = [
    {
      'image': 'assets/images/upgrade_gloss_black.jpg',
      'title': 'Gloss Black Alloys',
    },
    {
      'image': 'assets/images/upgrade_gunmetal.jpg',
      'title': 'Gunmetal Alloys',
    },
    {
      'image': 'assets/images/upgrade_diamond_cut.jpg',
      'title': 'Diamond Cut Wheels',
    },
    {
      'image': 'assets/images/upgrade_red_calipers.jpg',
      'title': 'Red Caliper Package',
    },
  ];

  List<Map<String, dynamic>> _packages = [
    {
      'name': 'QUICK AIR & CHECK',
      'price': '₹299',
      'duration': '20 mins',
      'description': 'Perfect for routine tyre maintenance and maximizing tyre life.',
      'features': [
        'Tyre pressure check',
        'Nitrogen refill',
        'Air leakage inspection',
        'Valve inspection',
        'Tread inspection',
      ],
    },
    {
      'name': 'WHEEL ALIGNMENT',
      'price': '₹799',
      'duration': '45 mins',
      'description':
          'Recommended if your vehicle pulls to one side or steering feels off-center.',
      'features': [
        'Computerized alignment',
        'Steering correction',
        'Camber adjustment',
        'Wheel angle optimization',
        'Road stability testing',
      ],
    },
    {
      'name': 'BALANCING & ROTATION',
      'price': '₹1499',
      'duration': '60 mins',
      'description': 'Improves ride quality and tyre longevity.',
      'features': [
        'Dynamic balancing',
        'Tyre rotation',
        'Wheel weight calibration',
        'Vibration reduction',
        'High-speed balancing',
      ],
    },
    {
      'name': 'ROAD GRIP PACKAGE',
      'price': '₹2499',
      'duration': '90 mins',
      'description': 'Ideal for highway driving and enhanced stability.',
      'features': [
        'Alignment',
        'Balancing',
        'Rotation',
        'Suspension inspection',
        'Brake inspection',
        'Grip optimization',
      ],
    },
    {
      'name': 'PERFORMANCE PACKAGE',
      'price': '₹3499',
      'duration': '120 mins',
      'description': 'Designed for enthusiasts seeking sharper handling and control.',
      'features': [
        'Performance alignment',
        'Precision balancing',
        'Suspension tuning check',
        'Cornering optimization',
        'Road testing',
      ],
    },
    {
      'name': 'PREMIUM WHEEL CARE',
      'price': '₹4999',
      'duration': '90 mins',
      'description': 'Restores and protects premium alloy wheels.',
      'features': [
        'Alloy detailing',
        'Rim protection coating',
        'Deep wheel cleaning',
        'Brake dust removal',
        'Finish restoration',
      ],
    },
    {
      'name': 'ALLOY WHEEL STUDIO',
      'price': '₹5999',
      'duration': '150 mins',
      'description': 'For customers upgrading to premium alloys.',
      'features': [
        'Alloy installation',
        'Fitment inspection',
        'Wheel balancing',
        'Alignment',
        'Styling consultation',
      ],
    },
    {
      'name': 'TRACK PERFORMANCE+',
      'price': '₹6799',
      'duration': '180 mins',
      'description': 'Ultimate performance package inspired by motorsport setups.',
      'features': [
        'Premium wheel setup',
        'High-speed balancing',
        'Performance alignment',
        'Suspension inspection',
        'Brake inspection',
        'Grip enhancement',
        'Road testing',
        'Premium detailing',
      ],
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
      final rows = await CatalogService.fetchByCategory('Tyre Care');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      const keyOrder = [
        'tyre_quick_air_check',
        'tyre_wheel_alignment',
        'tyre_balancing_rotation',
        'tyre_road_grip',
        'tyre_performance',
        'tyre_premium_wheel_care',
        'tyre_alloy_wheel_studio',
        'tyre_track_performance_plus',
      ];

      setState(() {
        for (var i = 0; i < keyOrder.length && i < _packages.length; i++) {
          final row = byKey[keyOrder[i]];
          if (row != null) {
            _packages[i]['price'] = row['price'];
            _packages[i]['duration'] = row['duration'];
            _packages[i]['description'] = row['details'] ?? _packages[i]['description'];
            _packages[i]['features'] = List<String>.from(row['services']);
          }
        }
      });
    } catch (e) {
      // Keep the hardcoded fallback values above if the fetch fails.
    }
  }

  void _showPackageSheet(Map<String, dynamic> package) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PackageSheet(
        package: package,
        vehicleId: widget.vehicle['id'].toString(),
      ),
    );
  }

  Future<void> _callExpert() async {
    await launchUrl(Uri.parse('tel:9353094672'));
  }

  void _scrollToPackages() {
    final ctx = _packagesKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return Scaffold(
      backgroundColor: AppColors.ink,
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
                        _buildServicesStrip(),
                        _buildPackagesSection(),
                        _buildTyreChangeSection(),
                        _buildWhyChooseUs(),
                        _buildLiveTracking(),
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
          width: double.infinity,
          height: 380,
          child: Image.asset(
            'assets/images/tyre_hero.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.photoPlaceholder,
              child: Center(
                child: Icon(Icons.tire_repair, color: AppColors.accent, size: 80),
              ),
            ),
          ),
        ),
        // Gradient: dark bottom → transparent top, for text legibility
        // over the photo. Built from AppColors.ink rather than a literal
        // black so it flips to a light scrim in light mode instead of
        // staying a dark hue the flipped (dark) hero text can't sit on.
        Container(
          width: double.infinity,
          height: 380,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.ink,
                AppColors.ink.withOpacity(0.8),
                AppColors.ink.withOpacity(0.0),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
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
                const SizedBox(height: 130),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'TYRE & WHEEL CARE',
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
                  'Tyre Care',
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
                  'Alignment, balancing and premium wheel care — done right.',
                  style: TextStyle(
                    color: AppColors.txt.withOpacity(0.7),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── SERVICES STRIP ───────────────────────────────────────────────
  Widget _buildServicesStrip() {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Services included',
              style: TextStyle(
                color: AppColors.txt,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _serviceChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.accent.withOpacity(0.4)),
                ),
                child: Text(
                  _serviceChips[i],
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PERFORMANCE PACKAGES ─────────────────────────────────────────
  Widget _buildPackagesSection() {
    return Padding(
      key: _packagesKey,
      padding: const EdgeInsets.fromLTRB(0, 36, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Choose a package',
              style: TextStyle(
                color: AppColors.txt,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Tap a card to see what\'s included and book',
              style: TextStyle(color: AppColors.mut, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 210,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _packages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _PackageCard(
                package: _packages[i],
                onTap: () => _showPackageSheet(_packages[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TYRE CHANGE SECTION ──────────────────────────────────────────
  Widget _buildTyreChangeSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tyre change & upgrades',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 26),

          // TYRE BRAND SELECTOR
          Text(
            'Select a tyre brand',
            style: TextStyle(
              color: AppColors.mut,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tyreBrands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final selected = selectedTyreBrand == _tyreBrands[i];
                return GestureDetector(
                  onTap: () => setState(() => selectedTyreBrand = _tyreBrands[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 118,
                    height: 92,
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppColors.accent : AppColors.line,
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withOpacity(0.25),
                                blurRadius: 14,
                              )
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tire_repair,
                            color: selected ? AppColors.accent : AppColors.mut,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _tyreBrandLabels[i],
                            style: TextStyle(
                              color: selected ? AppColors.accent : AppColors.mut,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 26),

          Text(
            'Alloy wheel brand',
            style: TextStyle(
              color: AppColors.mut,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.chipBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedAlloyBrand,
                hint: Text(
                  'Select alloy brand',
                  style: TextStyle(color: AppColors.mut, fontSize: 15),
                ),
                dropdownColor: AppColors.surfaceRaised,
                icon: Icon(Icons.keyboard_arrow_down, color: AppColors.accent),
                isExpanded: true,
                items: _alloyBrands
                    .map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(
                            b,
                            style: TextStyle(color: AppColors.txt, fontSize: 15),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => selectedAlloyBrand = v),
              ),
            ),
          ),

          const SizedBox(height: 26),

          Text(
            'Wheel size (inches)',
            style: TextStyle(
              color: AppColors.mut,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: _wheelSizes.map((size) {
              final selected = selectedWheelSize == size;
              return GestureDetector(
                onTap: () => setState(() => selectedWheelSize = size),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.line,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    '$size"',
                    style: TextStyle(
                      color: selected ? AppColors.onAccentDark : AppColors.txt,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 26),

          Text(
            'Popular upgrades',
            style: TextStyle(
              color: AppColors.mut,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _upgradeItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final item = _upgradeItems[i];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: 220,
                        height: 160,
                        child: Image.asset(
                          item['image'] as String,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 220,
                            height: 160,
                            color: AppColors.photoPlaceholder,
                            child: Icon(Icons.auto_awesome, color: AppColors.accent, size: 36),
                          ),
                        ),
                      ),
                      Container(
                        width: 220,
                        height: 160,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xDD000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        left: 14,
                        right: 14,
                        child: Text(
                          item['title'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 28),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    title: 'Tyre Change',
                    price: 'Custom Quote',
                    duration: 'TBD',
                    vehicleId: widget.vehicle['id'].toString(),
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Request a Tyre Change',
                  style: TextStyle(
                    color: AppColors.onAccentDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── WHY CHOOSE US ────────────────────────────────────────────────
  Widget _buildWhyChooseUs() {
    final items = [
      {'icon': Icons.gps_fixed, 'title': 'Laser alignment systems'},
      {'icon': Icons.auto_awesome, 'title': 'Premium alloy options'},
      {'icon': Icons.speed, 'title': 'High-speed balancing'},
      {'icon': Icons.engineering, 'title': 'Expert wheel technicians'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why choose us',
            style: TextStyle(
              color: AppColors.txt,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: items.map((item) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item['icon'] as IconData, color: AppColors.accent, size: 26),
                    const SizedBox(height: 10),
                    Text(
                      item['title'] as String,
                      style: TextStyle(
                        color: AppColors.txt,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
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
    final items = [
      {'icon': Icons.compare, 'label': 'Before / after inspection'},
      {'icon': Icons.bar_chart, 'label': 'Alignment reports'},
      {'icon': Icons.sync, 'label': 'Real-time updates'},
      {'icon': Icons.history, 'label': 'Digital wheel history'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accent.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.track_changes, color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Live tracking included',
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item['icon'] as IconData, color: AppColors.mut, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        item['label'] as String,
                        style: TextStyle(color: AppColors.txt, fontSize: 15),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── STICKY BOTTOM BAR ────────────────────────────────────────────
  Widget _buildStickyBar() {
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
        child: Row(
          children: [
            GestureDetector(
              onTap: _callExpert,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Icon(Icons.call_rounded, color: AppColors.accent, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _scrollToPackages,
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'View Packages',
                      style: TextStyle(
                        color: AppColors.onAccentDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
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
}

// ── Package Card (Horizontal Carousel) ──────────────────────────────
class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;

  const _PackageCard({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = package['name'] as String;
    final price = package['price'] as String;
    final features = package['features'] as List<String>;

    final isTopPick = name.contains('TRACK') || name.contains('ALLOY');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 330,
        height: 200,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isTopPick ? AppColors.accent.withOpacity(0.6) : AppColors.line,
            width: isTopPick ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isTopPick)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'TOP PICK',
                  style: TextStyle(
                    color: AppColors.onAccentDark,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  price,
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: features.take(3).map((f) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      color: AppColors.mut,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '+${features.length - 3 > 0 ? features.length - 3 : 0} more',
                  style: TextStyle(color: AppColors.mut, fontSize: 12),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'View & Book',
                    style: TextStyle(
                      color: AppColors.onAccentDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Package Bottom Sheet ─────────────────────────────────────────────
class _PackageSheet extends StatelessWidget {
  final Map<String, dynamic> package;
  final String vehicleId;

  const _PackageSheet({required this.package, required this.vehicleId});

  @override
  Widget build(BuildContext context) {
    final name = package['name'] as String;
    final price = package['price'] as String;
    final duration = package['duration'] as String;
    final description = package['description'] as String;
    final features = package['features'] as List<String>;
    final isTopPick = name.contains('TRACK') || name.contains('ALLOY');

    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isTopPick)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'TOP PICK',
                        style: TextStyle(
                          color: AppColors.onAccentDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined, color: AppColors.mut, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              duration,
                              style: TextStyle(color: AppColors.mut, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'What we do',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      description,
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Features',
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check, color: AppColors.accent, size: 14),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              f,
                              style: TextStyle(color: AppColors.txt, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                      title: name,
                      price: price,
                      duration: duration,
                      vehicleId: vehicleId,
                    ),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Book Now',
                    style: TextStyle(
                      color: AppColors.onAccentDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
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
