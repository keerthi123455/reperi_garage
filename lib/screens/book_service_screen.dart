import 'package:flutter/material.dart';

import 'payment_screen.dart';
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/catalog_gate.dart';

class BookServiceScreen extends StatefulWidget {

  final Map<String, dynamic> vehicle;

  /// When set (matches one of the tile titles below, e.g. "Quick Service"),
  /// that tile is pre-selected and scrolled into view on open.
  final String? highlightPackage;

  const BookServiceScreen({
    super.key,
    required this.vehicle,
    this.highlightPackage,
  });

  @override
  State<BookServiceScreen> createState() =>
      _BookServiceScreenState();
}

class _BookServiceScreenState
    extends State<BookServiceScreen> {

  int selectedIndex = 0;
  final List<GlobalKey> _cardKeys = [];

  // Card icons by position — purely visual, so they stay in the app.
  static const _icons = <IconData>[
    Icons.build_rounded,
    Icons.car_repair,
    Icons.ac_unit_rounded,
    Icons.settings,
  ];

  /// The packages, live from the Supabase `services` table (screen
  /// 'book_service') — same objects until the catalog changes.
  List<Map<String, dynamic>>? _servicesCache;
  int _servicesRevision = -1;
  List<Map<String, dynamic>> get services {
    if (_servicesCache == null || _servicesRevision != CatalogService.revision.value) {
      final items = CatalogService.forScreen('book_service').where((i) => !i.isAddon).toList();
      _servicesCache = [
        for (var i = 0; i < items.length; i++)
          <String, dynamic>{
            'key': items[i].key,
            'title': items[i].name,
            'price': items[i].priceText,
            'time': items[i].duration,
            'features': items[i].features,
            'details': items[i].description,
            'icon': _icons[i % _icons.length],
          },
      ];
      _servicesRevision = CatalogService.revision.value;
    }
    return _servicesCache!;
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
    if (widget.highlightPackage == null || services.isEmpty) return;
    final target = widget.highlightPackage!.toLowerCase();
    final match = services.indexWhere(
        (s) => (s['title'] as String).toLowerCase() == target);
    if (match == -1) return;
    setState(() => selectedIndex = match);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cardKey(selectedIndex).currentContext;
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
    if (services.isEmpty) return;
    final selectedService = services[(selectedIndex < 0 ? 0 : (selectedIndex >= services.length ? services.length - 1 : selectedIndex))];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: selectedService['title'] as String,
          duration: selectedService['time'] as String,
          vehicleId: widget.vehicle['id'].toString(),
          serviceKeys: [selectedService['key'] as String],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CatalogGate(builder: (context) {
    if (services.isEmpty) return const CatalogEmpty();


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
                              'assets/images/service_hero.png',
                              fit: BoxFit.cover,
                            ),
                          ),

                          // Gradient: solid page-bg color at the bottom
                          // fading to transparent at the top, for text
                          // legibility over the photo. Built from
                          // AppColors.ink rather than a literal black so it
                          // flips to a light scrim in light mode instead of
                          // staying a dark hue the white hero text can't
                          // sit on.
                          Container(
                            height: 400,
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
                                    // ── Premium Badge ──
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'PREMIUM CARE',
                                        style: TextStyle(
                                          color: AppColors.onAccentDark,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 14),

                                    // ── Title ──
                                    Text(
                                      'Book Service',
                                      style: TextStyle(
                                        color: AppColors.txt,
                                        fontSize: 44,
                                        fontWeight: FontWeight.w900,
                                        height: 1.05,
                                        letterSpacing: -0.5,
                                      ),
                                    ),

                                    const SizedBox(height: 10),

                                    // ── Description ──
                                    Text(
                                      'Professional servicing for your vehicle, handled by our skilled technicians.',
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

                      /// SERVICE CARDS (FULL WIDTH, STACKED VERTICALLY)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: List.generate(services.length, (index) {
                            final service = services[index];
                            final isSelected = index == selectedIndex;

                            return Padding(
                              key: _cardKey(index),
                              padding: EdgeInsets.only(
                                bottom: index == services.length - 1 ? 0 : 16,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => selectedIndex = index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceRaised,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.accent
                                          : AppColors.line,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.accent.withOpacity(0.2),
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
                                                color: AppColors.accent.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                service['icon'] as IconData,
                                                color: AppColors.accent,
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    service['title'] as String,
                                                    style: TextStyle(
                                                      color: AppColors.txt,
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        service['price'] as String,
                                                        style: const TextStyle(
                                                          color: AppColors.accent,
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
                                                          service['time'] as String,
                                                          style: TextStyle(
                                                            color: AppColors.mut,
                                                            fontSize: 13,
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

                                        // ── What's included ──
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
                                          children: (service['features'] as List<String>)
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: entry.key <
                                                        (service['features'] as List)
                                                                .length -
                                                            1
                                                    ? 10
                                                    : 0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Container(
                                                    margin: const EdgeInsets.only(top: 5),
                                                    width: 5,
                                                    height: 5,
                                                    decoration: const BoxDecoration(
                                                      color: AppColors.accent,
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
                                          service['details'] as String,
                                          style: TextStyle(
                                            color: AppColors.txt.withOpacity(0.7),
                                            fontSize: 14,
                                            height: 1.6,
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

                // ── Sticky book bar ──
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                    child: SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _proceedToPayment,
                        child: Text(
                          'Book Now',
                          style: TextStyle(
                            color: AppColors.onAccentDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
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