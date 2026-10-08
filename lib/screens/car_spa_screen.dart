import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/catalog_gate.dart';

class CarSpaScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  /// When set (matches one of the package titles below, case-insensitive),
  /// that package is pre-selected and scrolled into view on open.
  final String? highlightPackage;

  const CarSpaScreen({
    super.key,
    required this.vehicle,
    this.highlightPackage,
  });

  @override
  State<CarSpaScreen> createState() => _CarSpaScreenState();
}

class _CarSpaScreenState extends State<CarSpaScreen> {
  int selectedPackage = -1;
  final List<GlobalKey> _cardKeys = [];

  static const Color _gold = Color(0xFFD4A017);

  // Card icons by position — purely visual, so they stay in the app.
  static const _icons = <IconData>[
    Icons.water_drop_outlined,
    Icons.chair_outlined,
    Icons.diamond_outlined,
  ];

  /// The packages, live from the Supabase `services` table (screen
  /// 'car_spa') — same objects until the catalog changes.
  List<Map<String, dynamic>>? _packagesCache;
  int _packagesRevision = -1;
  List<Map<String, dynamic>> get packages {
    if (_packagesCache == null || _packagesRevision != CatalogService.revision.value) {
      final items = CatalogService.forScreen('car_spa').where((i) => !i.isAddon).toList();
      _packagesCache = [
        for (var i = 0; i < items.length; i++)
          <String, dynamic>{
            'key': items[i].key,
            'title': items[i].name.toUpperCase(),
            'subtitle': items[i].detail('subtitle'),
            'price': items[i].priceText,
            'duration': items[i].duration,
            'details': items[i].description,
            'features': items[i].features,
            'icon': _icons[i % _icons.length],
          },
      ];
      _packagesRevision = CatalogService.revision.value;
    }
    return _packagesCache!;
  }

  @override
  void initState() {
    super.initState();
    // Packages come from the catalog, which may still be loading.
    CatalogService.ensureLoaded().then((_) {
      if (mounted) _applyHighlight();
    }).catchError((_) {});
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  /// Scroll target for card [i] — grows with the catalog.
  GlobalKey _cardKey(int i) {
    while (_cardKeys.length <= i) {
      _cardKeys.add(GlobalKey());
    }
    return _cardKeys[i];
  }

  void _applyHighlight() {
    if (widget.highlightPackage == null || packages.isEmpty) return;
    final target = widget.highlightPackage!.toLowerCase();
    final match = packages.indexWhere(
        (p) => (p['title'] as String).toLowerCase() == target);
    if (match == -1) return;
    setState(() => selectedPackage = match);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cardKey(selectedPackage).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    });
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }


  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  // ── Proceed to payment — the doorstep pickup/drop add-on is now asked
  // on PaymentScreen itself, not here.
  void _proceedToPayment() {
    final selectedPkg = packages[(selectedPackage < 0 ? 0 : (selectedPackage >= packages.length ? packages.length - 1 : selectedPackage))];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: selectedPkg['title'] as String,
          duration: selectedPkg['duration'] as String,
          vehicleId: widget.vehicle['id'].toString(),
          serviceKeys: [selectedPkg['key'] as String],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogGate(builder: (context) {
    if (packages.isEmpty) return const CatalogEmpty();

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Stack(
              children: [
                // ── Scrollable Content ──
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// HERO SECTION (IMPROVED)
                      Stack(
                        children: [
                          // ── Hero Image ──
                          SizedBox(
                            height: 400,
                            width: double.infinity,
                            child: Image.asset(
                              'assets/images/carspa_hero.jpeg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surfaceRaised,
                                child: const Center(
                                  child: Icon(
                                    Icons.directions_car,
                                    color: _gold,
                                    size: 80,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── Gradient Overlay ──
                          // Built from AppColors.ink rather than a literal
                          // black so it flips to a light scrim in light
                          // mode instead of staying a dark hue the white
                          // hero text can't sit on.
                          Container(
                            height: 400,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.ink.withOpacity(0.3),
                                  AppColors.ink.withOpacity(0.75),
                                ],
                                stops: const [0.3, 1.0],
                              ),
                            ),
                          ),

                          // ── Hero Content ──
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // ── Back Button ──
                                Semantics(
                                  button: true,
                                  label: 'Back',
                                  child: GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.55),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white30),
                                      ),
                                      child: const Icon(
                                        Icons.arrow_back,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),

                                // ── Content at Bottom ──
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _gold,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'PREMIUM DETAILING',
                                        style: TextStyle(
                                          color: AppColors.onAccentDark,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Car Spa',
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
                                      'Premium detailing and restoration to keep your car looking showroom-new.',
                                      style: TextStyle(
                                        color: AppColors.txt.withOpacity(0.7),
                                        fontSize: 15,
                                        height: 1.4,
                                      ),
                                      maxLines: 3,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      /// PACKAGE CARDS (FULL WIDTH, STACKED VERTICALLY)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: List.generate(packages.length, (index) {
                            final pkg = packages[index];
                            final isSelected = index == selectedPackage;

                            return Padding(
                              key: _cardKey(index),
                              padding: EdgeInsets.only(
                                bottom: index == packages.length - 1 ? 0 : 16,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => selectedPackage = index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceRaised,
                                    border: Border.all(
                                      color: isSelected ? _gold : AppColors.line,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: _gold.withOpacity(0.2),
                                              blurRadius: 20,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // ── Header: Icon + Title + Price ──
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: _gold.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                pkg['icon'] as IconData,
                                                color: _gold,
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    pkg['title'] as String,
                                                    style: TextStyle(
                                                      color: AppColors.txt,
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    pkg['subtitle'] as String,
                                                    style: TextStyle(
                                                      color: AppColors.mut,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        pkg['price'] as String,
                                                        style: const TextStyle(
                                                          color: _gold,
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w900,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.chipBg,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          pkg['duration'] as String,
                                                          style: TextStyle(
                                                            color: AppColors.mut,
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 20),

                                        // ── Divider ──
                                        Container(
                                          height: 1,
                                          color: AppColors.line,
                                        ),

                                        const SizedBox(height: 20),

                                        // ── What's Included ──
                                        Text(
                                          'What\'s included',
                                          style: TextStyle(
                                            color: AppColors.txt,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        Column(
                                          children: (pkg['features'] as List<String>)
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: entry.key <
                                                        (pkg['features'] as List).length - 1
                                                    ? 10
                                                    : 0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    margin: const EdgeInsets.only(top: 5),
                                                    width: 5,
                                                    height: 5,
                                                    decoration: const BoxDecoration(
                                                      color: _gold,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      entry.value,
                                                      style: TextStyle(
                                                        color: AppColors.txt.withOpacity(0.7),
                                                        fontSize: 14,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),

                                        const SizedBox(height: 20),

                                        // ── Divider ──
                                        Container(
                                          height: 1,
                                          color: AppColors.line,
                                        ),

                                        const SizedBox(height: 20),

                                        // ── Details ──
                                        Text(
                                          'Details',
                                          style: TextStyle(
                                            color: AppColors.txt,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        Text(
                                          pkg['details'] as String,
                                          style: TextStyle(
                                            color: AppColors.txt.withOpacity(0.7),
                                            fontSize: 14,
                                            height: 1.7,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ));
                          }),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),

                // ── STICKY BOOK NOW BAR (BOTTOM) ──
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
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
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedPackage == -1
                                ? AppColors.chipBg
                                : _gold,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          onPressed: selectedPackage == -1
                              ? null
                              : _proceedToPayment,
                          child: Text(
                            selectedPackage == -1 ? 'Select a package' : 'Book Now',
                            style: TextStyle(
                              color: selectedPackage == -1
                                  ? AppColors.mut
                                  : AppColors.onAccentDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    });
  }
}