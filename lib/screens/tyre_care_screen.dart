import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class TyreCareScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  /// When set (matches one of the package names below, case-insensitive),
  /// the screen scrolls to that package and opens its detail sheet on open.
  final String? highlightPackage;

  const TyreCareScreen({
    super.key,
    required this.vehicle,
    this.highlightPackage,
  });

  @override
  State<TyreCareScreen> createState() => _TyreCareScreenState();
}

class _TyreCareScreenState extends State<TyreCareScreen> {
  // ── State ────────────────────────────────────────────────────────
  String? selectedTyreBrand;
  int? selectedWheelSize;

  final GlobalKey _packagesKey = GlobalKey();
  final List<GlobalKey> _packageCardKeys = [];

  // ── Data ─────────────────────────────────────────────────────────
  // Alloy wheels have their own dedicated screen elsewhere in the app —
  // nothing alloy-related belongs on a plain tyre-care screen, so it's
  // gone from every list below (the packages, the request builder).
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

  final List<int> _wheelSizes = [15, 16, 17, 18, 19, 20];

  // Index 0 ('featured': true) is the combo package — shown as its own
  // large tile above the horizontal scroll of the other three, rather
  // than mixed in among them (see _buildPackagesSection).
  List<Map<String, dynamic>> _packages = [
    {
      'name': 'WHEEL ALIGNMENT AND BALANCING',
      'price': '₹799',
      'duration': '60 mins',
      'description':
          'Our most complete wheel care combo — precise computerized alignment and dynamic balancing together, in one visit.',
      'icon': Icons.architecture_rounded,
      'featured': true,
      'hasExtraCharge': true,
      'features': [
        'Computerized alignment',
        'Dynamic balancing',
        'Steering correction',
        'Wheel weight calibration',
        'Road stability testing',
      ],
    },
    {
      'name': 'QUICK AIR & CHECK',
      'price': '₹299',
      'duration': '20 mins',
      'description': 'Perfect for routine tyre maintenance and maximizing tyre life.',
      'icon': Icons.air_rounded,
      'featured': false,
      'hasExtraCharge': false,
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
      'price': '₹499',
      'duration': '45 mins',
      'description':
          'Recommended if your vehicle pulls to one side or steering feels off-center.',
      'icon': Icons.architecture_rounded,
      'featured': false,
      'hasExtraCharge': false,
      'features': [
        'Computerized alignment',
        'Steering correction',
        'Camber adjustment',
        'Wheel angle optimization',
        'Road stability testing',
      ],
    },
    {
      'name': 'WHEEL BALANCING',
      'price': '₹299',
      'duration': '30 mins',
      'description': 'Improves ride quality and tyre longevity through precise dynamic balancing.',
      'icon': Icons.balance_rounded,
      'featured': false,
      'hasExtraCharge': true,
      'features': [
        'Dynamic balancing',
        'Wheel weight calibration',
        'Vibration reduction',
        'High-speed balancing',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _packageCardKeys.addAll(List.generate(_packages.length, (_) => GlobalKey()));
    _fetchPackageData();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);

    if (widget.highlightPackage != null) {
      final target = widget.highlightPackage!.toLowerCase();
      final idx = _packages.indexWhere(
          (p) => (p['name'] as String).toLowerCase() == target);
      if (idx != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final sectionCtx = _packagesKey.currentContext;
          if (sectionCtx != null) {
            await Scrollable.ensureVisible(
              sectionCtx,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          }
          final cardCtx = _packageCardKeys[idx].currentContext;
          if (cardCtx != null) {
            await Scrollable.ensureVisible(
              cardCtx,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
          if (mounted) _showPackageSheet(_packages[idx]);
        });
      }
    }
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

      // Positional against _packages above. Most entries are `null` —
      // the combo tile and the new standalone Wheel Alignment (₹499) /
      // Wheel Balancing (₹299) prices were just fixed deliberately, so a
      // stale catalog row from before this pricing change must not
      // silently overwrite them. Only Quick Air & Check is unchanged
      // from before and still safe to sync from the catalog.
      const List<String?> keyOrder = [
        null, // WHEEL ALIGNMENT AND BALANCING
        'tyre_quick_air_check',
        null, // WHEEL ALIGNMENT
        null, // WHEEL BALANCING
      ];

      setState(() {
        for (var i = 0; i < keyOrder.length && i < _packages.length; i++) {
          final key = keyOrder[i];
          if (key == null) continue;
          final row = byKey[key];
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

  /// This is a custom-quote request, not a fixed price — there is no
  /// amount for Razorpay to charge, so it goes to WhatsApp (carrying
  /// whatever brand/size the customer picked) instead of PaymentScreen,
  /// matching how every other "Custom Quote" item in the catalog behaves.
  Future<void> _requestTyreQuote() async {
    final brand = selectedTyreBrand != null
        ? _tyreBrandLabels[_tyreBrands.indexOf(selectedTyreBrand!)]
        : null;
    final details = [
      if (brand != null) 'Brand: $brand',
      if (selectedWheelSize != null) 'Wheel size: $selectedWheelSize"',
    ].join(', ');
    final message = details.isEmpty
        ? "Hi, I'd like a quote for a tyre change."
        : "Hi, I'd like a quote for a tyre change. $details.";
    final uri = Uri.parse(
      'https://wa.me/919353094672?text=${Uri.encodeComponent(message)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                        _FadeSlideIn(index: 0, child: _buildPackagesSection()),
                        _FadeSlideIn(index: 1, child: _buildTyreChangeSection()),
                        _FadeSlideIn(index: 2, child: _buildWhyChooseUs()),
                        _FadeSlideIn(index: 3, child: _buildLiveTracking()),
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
                Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
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

  // ── PACKAGES ─────────────────────────────────────────────────────
  Widget _buildPackagesSection() {
    final featuredIndex = _packages.indexWhere((p) => p['featured'] == true);
    final otherIndices = [
      for (var i = 0; i < _packages.length; i++)
        if (i != featuredIndex) i,
    ];

    return Padding(
      key: _packagesKey,
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
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
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Tap a card to see what\'s included and book',
              style: TextStyle(color: AppColors.mut, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 14),
          if (featuredIndex != -1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FeaturedPackageTile(
                key: _packageCardKeys[featuredIndex],
                package: _packages[featuredIndex],
                onTap: () => _showPackageSheet(_packages[featuredIndex]),
              ),
            ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'More tyre care options',
              style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 236,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: otherIndices.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (_, i) {
                final packageIndex = otherIndices[i];
                return _FadeSlideIn(
                  index: i,
                  child: _PackageCard(
                    key: _packageCardKeys[packageIndex],
                    package: _packages[packageIndex],
                    onTap: () => _showPackageSheet(_packages[packageIndex]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── REQUEST A TYRE CHANGE ────────────────────────────────────────
  // Its own card-based "quote builder" — deliberately styled apart from
  // the packages strip above, since this is a custom-quote request, not
  // a fixed-price tier.
  Widget _buildTyreChangeSection() {
    final hasBrand = selectedTyreBrand != null;
    final hasSize = selectedWheelSize != null;
    final hasSelection = hasBrand || hasSize;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.accent.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(Icons.local_shipping_outlined, color: AppColors.accent, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request a Tyre Change',
                        style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tell us your preference — we\'ll send a quote',
                        style: TextStyle(color: AppColors.mut, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStepLabel('1', 'Choose a tyre brand'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_tyreBrands.length, (i) {
                final selected = selectedTyreBrand == _tyreBrands[i];
                return GestureDetector(
                  onTap: () => setState(() => selectedTyreBrand = _tyreBrands[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent : AppColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? AppColors.accent : AppColors.line),
                    ),
                    child: Text(
                      _tyreBrandLabels[i],
                      style: TextStyle(
                        color: selected ? AppColors.onAccentDark : AppColors.txt,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            _buildStepLabel('2', 'Wheel size (inches)'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _wheelSizes.map((size) {
                final selected = selectedWheelSize == size;
                return GestureDetector(
                  onTap: () => setState(() => selectedWheelSize = size),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 58,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent : AppColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? AppColors.accent : AppColors.line),
                    ),
                    child: Text(
                      '$size"',
                      style: TextStyle(
                        color: selected ? AppColors.onAccentDark : AppColors.txt,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: hasSelection ? AppColors.accent.withOpacity(0.1) : AppColors.chipBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasSelection ? AppColors.accent.withOpacity(0.4) : AppColors.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    size: 18,
                    color: hasSelection ? AppColors.accent : AppColors.mut,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasSelection
                          ? '${hasBrand ? _tyreBrandLabels[_tyreBrands.indexOf(selectedTyreBrand!)] : 'Any brand'} · ${hasSize ? '$selectedWheelSize"' : 'Any size'}'
                          : 'Pick a brand and size for a faster quote',
                      style: TextStyle(
                        color: hasSelection ? AppColors.txt : AppColors.mut,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _requestTyreQuote,
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get My Quote',
                        style: TextStyle(color: AppColors.onAccentDark, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.onAccentDark, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepLabel(String step, String label) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.15), shape: BoxShape.circle),
          child: Text(
            step,
            style: TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ── WHY CHOOSE US ────────────────────────────────────────────────
  Widget _buildWhyChooseUs() {
    final items = [
      {'icon': Icons.gps_fixed, 'title': 'Laser alignment systems'},
      {'icon': Icons.speed, 'title': 'High-speed balancing'},
      {'icon': Icons.verified_outlined, 'title': 'Genuine, branded tyres'},
      {'icon': Icons.engineering, 'title': 'Expert wheel technicians'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why choose us',
            style: TextStyle(color: AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: items.map((item) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item['icon'] as IconData, color: AppColors.accent, size: 26),
                    const SizedBox(height: 12),
                    Flexible(
                      child: Text(
                        item['title'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.txt,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.3,
                        ),
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
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.accent.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.track_changes, color: AppColors.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Live tracking included',
                  style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
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

/// Fades + rises a section (or card) into place — each successive [index]
/// takes a little longer to finish, so a column of these started at once
/// reads as a gentle top-to-bottom (or left-to-right) cascade rather than
/// everything popping in together.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 22),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ── Package Card (Horizontal Carousel) ──────────────────────────────
class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;

  const _PackageCard({super.key, required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = package['name'] as String;
    final price = package['price'] as String;
    final features = package['features'] as List<String>;
    final icon = package['icon'] as IconData? ?? Icons.tire_repair;
    final hasExtraCharge = package['hasExtraCharge'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: AppColors.accent.withOpacity(0.08),
        child: Container(
          width: 280,
          height: 236,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.accent, size: 17),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w900, height: 1.2),
              ),
              const SizedBox(height: 5),
              Text(
                price,
                style: TextStyle(color: AppColors.accent, fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: features.take(2).map((f) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(color: AppColors.mut, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),
              if (hasExtraCharge) ...[
                const SizedBox(height: 6),
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: TextStyle(color: AppColors.mut, fontSize: 10.5, height: 1.3),
                    children: [
                      const TextSpan(text: 'Up to '),
                      TextSpan(
                        text: '₹200',
                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900),
                      ),
                      const TextSpan(text: ' extra may apply'),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '+${features.length - 2 > 0 ? features.length - 2 : 0} more',
                    style: TextStyle(color: AppColors.mut, fontSize: 11.5),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View & Book',
                        style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.accent, size: 14),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prominent, full-width "combo" package tile above the horizontal
/// scroll of other packages — visually distinct (gradient background,
/// larger type, a RECOMMENDED COMBO ribbon) since it's the primary
/// recommendation rather than one option among equals.
class _FeaturedPackageTile extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;

  const _FeaturedPackageTile({super.key, required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = package['name'] as String;
    final price = package['price'] as String;
    final duration = package['duration'] as String;
    final features = package['features'] as List<String>;
    final icon = package['icon'] as IconData? ?? Icons.architecture_rounded;
    final hasExtraCharge = package['hasExtraCharge'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        splashColor: AppColors.accent.withOpacity(0.08),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent.withOpacity(0.16), AppColors.surfaceRaised],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 1.5),
            boxShadow: [
              BoxShadow(color: AppColors.accent.withOpacity(0.18), blurRadius: 22, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'RECOMMENDED COMBO',
                      style: TextStyle(
                        color: AppColors.onAccentDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: AppColors.accent, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: TextStyle(color: AppColors.txt, fontSize: 21, fontWeight: FontWeight.w900, height: 1.15),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: TextStyle(color: AppColors.accent, fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, color: AppColors.mut, size: 14),
                        const SizedBox(width: 4),
                        Text(duration, style: TextStyle(color: AppColors.mut, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: features.take(4).map((f) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(f, style: TextStyle(color: AppColors.txt, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  );
                }).toList(),
              ),
              if (hasExtraCharge) ...[
                const SizedBox(height: 12),
                const _ExtraChargeNote(),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tap to view full details', style: TextStyle(color: AppColors.mut, fontSize: 12.5)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View & Book',
                        style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.accent, size: 15),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Extra charges may apply, up to ₹200" — shown on packages whose
/// `hasExtraCharge` flag is set (Wheel Balancing, and the combo tile),
/// with the ₹200 figure visually called out rather than buried in prose.
class _ExtraChargeNote extends StatelessWidget {
  const _ExtraChargeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: AppColors.mut, fontSize: 11.5, height: 1.45),
                children: [
                  const TextSpan(text: "Extra charges may apply based on your tyre's condition — up to "),
                  TextSpan(
                    text: '₹200',
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 12.5),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
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
    final icon = package['icon'] as IconData? ?? Icons.tire_repair;
    final isFeatured = package['featured'] == true;
    final hasExtraCharge = package['hasExtraCharge'] == true;

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
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(icon, color: AppColors.accent, size: 26),
                      ),
                      const SizedBox(width: 14),
                      if (isFeatured)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'RECOMMENDED COMBO',
                            style: TextStyle(
                              color: AppColors.onAccentDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 27,
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
                  const SizedBox(height: 24),
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
                  if (hasExtraCharge) ...[
                    const SizedBox(height: 14),
                    const _ExtraChargeNote(),
                  ],
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
