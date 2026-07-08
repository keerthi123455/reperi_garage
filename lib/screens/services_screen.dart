import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'book_service_screen.dart';
import 'car_spa_screen.dart';
import 'denting_tinkering_screen.dart';
import 'paint_care_screen.dart';
import 'tyre_care_screen.dart';
import 'roadside_assistance_screen.dart';
import 'fleet_management_screen.dart';
import 'service_details_screen.dart';
import 'profile_screen.dart';
import '../services/catalog_service.dart';

class ServicesScreen extends StatefulWidget {
  final Map<String, dynamic>? activeVehicle;

  const ServicesScreen({super.key, this.activeVehicle});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Map<String, Map<String, dynamic>> _packageData = {};

  static const Color _gold = Color(0xFFD4A017);
  static const Color _bg = Color(0xFF121212);
  static const Color _cardBg = Color(0xFF1B1B1B);

@override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _fetchPackageData();
  }

  Future<void> _fetchPackageData() async {
    try {
      final rows = await CatalogService.fetchByKeys([
        '21_step_inspection',
        'quick_care',
        'wheelzcare',
        'car360_pack',
      ]);

      if (!mounted) return;

      setState(() {
        _packageData = {for (final row in rows) row['key'] as String: row};
      });
    } catch (e) {
      // Keep default hardcoded fallback values below if fetch fails.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Navigation helper ──────────────────────────────────────
  void _navigate(Widget Function() builder, {bool vehicleRequired = true}) {
    if (vehicleRequired && widget.activeVehicle == null) {
      _showNoVehicleDialog();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => builder()));
  }

  void _comingSoon(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name coming soon'),
        backgroundColor: const Color(0xFF1B1B1B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showNoVehicleDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF111111),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_alt_1, color: _gold, size: 44),
              ),
              const SizedBox(height: 24),
              const Text(
                'Please create a profile to book services',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Add your vehicle details to continue with premium garage services.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: const Text(
                    'MAKE PROFILE',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── All service entries (used for search filtering too) ────
  List<_ServiceEntry> get _allEntries => [
        // Maintenance
        _ServiceEntry(
          section: 'Maintenance',
          name: 'Book Service',
          subtitle: 'Oil • Filters • Full Checkup',
          image: 'assets/images/tile_book_service.jpg',
          onTap: () => _navigate(
            () => BookServiceScreen(vehicle: widget.activeVehicle!),
          ),
        ),
        _ServiceEntry(
          section: 'Maintenance',
          name: '21 Step Inspection',
          subtitle: 'Comprehensive vehicle health check',
          image: 'assets/images/21pointinspection.JPG',
          onTap: () => _navigate(
            () => ServiceDetailsScreen(
              title: '21 STEP\nINSPECTION',
              image: 'assets/images/21pointinspection.JPG',
              price: _packageData['21_step_inspection']?['price'] ?? '₹599',
              duration: _packageData['21_step_inspection']?['duration'] ?? '45 mins',
              vehicleId: widget.activeVehicle?['id'] ?? '',
              services: _packageData['21_step_inspection'] != null
                  ? List<String>.from(_packageData['21_step_inspection']!['services'])
                  : ['Engine Check', 'Brake Inspection', 'Battery Health'],
              benefits: _packageData['21_step_inspection'] != null
                  ? List<String>.from(_packageData['21_step_inspection']!['benefits'])
                  : ['Prevent breakdowns', 'Vehicle health report'],
            ),
          ),
        ),
        _ServiceEntry(
          section: 'Maintenance',
          name: 'Quick Care',
          subtitle: 'Exterior wash & interior vacuum',
          image: 'assets/images/quickcare.JPG',
          onTap: () => _navigate(
            () => ServiceDetailsScreen(
              title: 'QUICK CARE',
              image: 'assets/images/quickcare.JPG',
              price: _packageData['quick_care']?['price'] ?? '₹399',
              duration: _packageData['quick_care']?['duration'] ?? '30 mins',
              vehicleId: widget.activeVehicle?['id'] ?? '',
              services: _packageData['quick_care'] != null
                  ? List<String>.from(_packageData['quick_care']!['services'])
                  : ['Exterior Wash', 'Interior Vacuum'],
              benefits: _packageData['quick_care'] != null
                  ? List<String>.from(_packageData['quick_care']!['benefits'])
                  : ['Cleaner interiors', 'Quick refresh'],
            ),
          ),
        ),
        // Care & Detailing
        _ServiceEntry(
          section: 'Care & Detailing',
          name: 'Car Spa',
          subtitle: 'Interior + exterior deep clean',
          image: 'assets/images/tile_car_spa.jpg',
          onTap: () => _navigate(
            () => CarSpaScreen(vehicle: widget.activeVehicle!),
          ),
        ),
        _ServiceEntry(
          section: 'Care & Detailing',
          name: 'Car360 Pack',
          subtitle: 'Detailing & paint protection',
          image: 'assets/images/car360.JPG',
          onTap: () => _navigate(
            () => ServiceDetailsScreen(
              title: 'CAR360 PACK',
              image: 'assets/images/car360.JPG',
              price: _packageData['car360_pack']?['price'] ?? '₹1599',
              duration: _packageData['car360_pack']?['duration'] ?? '3 hrs',
              vehicleId: widget.activeVehicle?['id'] ?? '',
              services: _packageData['car360_pack'] != null
                  ? List<String>.from(_packageData['car360_pack']!['services'])
                  : ['Detailing', 'Paint Protection'],
              benefits: _packageData['car360_pack'] != null
                  ? List<String>.from(_packageData['car360_pack']!['benefits'])
                  : ['Showroom finish', 'Premium shine'],
            ),
          ),
        ),
        _ServiceEntry(
          section: 'Care & Detailing',
          name: 'Detailing',
          subtitle: 'Gloss & ceramic coat',
          image: 'assets/images/tile_detailing.jpg',
          onTap: () => _comingSoon('Detailing'),
          comingSoon: true,
        ),
        // Wheels & Tyres
        _ServiceEntry(
          section: 'Wheels & Tyres',
          name: 'Tyre Care',
          subtitle: 'Alignment, balancing & rotation',
          image: 'assets/images/tile_tyre.jpg',
          onTap: () => _navigate(
            () => TyreCareScreen(vehicle: widget.activeVehicle!),
          ),
        ),
        _ServiceEntry(
          section: 'Wheels & Tyres',
          name: 'WheelzCare',
          subtitle: 'Wheel alignment & balancing',
          image: 'assets/images/WheelzCare.JPG',
          onTap: () => _navigate(
            () => ServiceDetailsScreen(
              title: 'WHEELZCARE',
              image: 'assets/images/WheelzCare.JPG',
              price: _packageData['wheelzcare']?['price'] ?? '₹599',
              duration: _packageData['wheelzcare']?['duration'] ?? '45 mins',
              vehicleId: widget.activeVehicle?['id'] ?? '',
              services: _packageData['wheelzcare'] != null
                  ? List<String>.from(_packageData['wheelzcare']!['services'])
                  : ['Wheel Alignment', 'Wheel Balancing'],
              benefits: _packageData['wheelzcare'] != null
                  ? List<String>.from(_packageData['wheelzcare']!['benefits'])
                  : ['Smoother driving', 'Longer tyre life'],
            ),
          ),
        ),
        // Body & Paint
        _ServiceEntry(
          section: 'Body & Paint',
          name: 'Paint Care',
          subtitle: 'Scratch & surface repair',
          image: 'assets/images/tile_paint.jpg',
          onTap: () => _navigate(
            () => PaintCareScreen(vehicle: widget.activeVehicle!),
          ),
        ),
        _ServiceEntry(
          section: 'Body & Paint',
          name: 'Denting & Tinkering',
          subtitle: 'Body repair & finish',
          image: 'assets/images/tile_denting.jpg',
          onTap: () => _navigate(
            () => DentingTinkeringScreen(vehicle: widget.activeVehicle!),
          ),
        ),
        _ServiceEntry(
          section: 'Body & Paint',
          name: 'Insurance Claims',
          subtitle: 'Cashless accident assistance',
          image: 'assets/images/tile_insurance.jpg',
          onTap: () => _comingSoon('Insurance Claims'),
          comingSoon: true,
        ),
        // Business Solutions
        _ServiceEntry(
          section: 'Business Solutions',
          name: 'Fleet Management',
          subtitle: 'End-to-end fleet servicing',
          image: 'assets/images/fleet.jpg',
          onTap: () => _navigate(
            () => const FleetManagementScreen(),
            vehicleRequired: false,
          ),
        ),
        _ServiceEntry(
          section: 'Business Solutions',
          name: 'Battery Management',
          subtitle: 'EV & conventional battery care',
          image: 'assets/images/battery.jpg',
          onTap: () => _comingSoon('Battery Management'),
          comingSoon: true,
        ),
        _ServiceEntry(
          section: 'Business Solutions',
          name: 'Partner Garage Program',
          subtitle: 'Join our garage network',
          image: 'assets/images/garage.jpg',
          onTap: () => _comingSoon('Partner Garage Program'),
          comingSoon: true,
        ),
      ];

  List<_ServiceEntry> get _filtered {
    if (_searchQuery.isEmpty) return _allEntries;
    return _allEntries
        .where((e) =>
            e.name.toLowerCase().contains(_searchQuery) ||
            e.subtitle.toLowerCase().contains(_searchQuery) ||
            e.section.toLowerCase().contains(_searchQuery))
        .toList();
  }

  // ── Section order ──────────────────────────────────────────
  static const List<String> _sectionOrder = [
    'Maintenance',
    'Care & Detailing',
    'Wheels & Tyres',
    'Body & Paint',
    'Business Solutions',
  ];

  static const Map<String, IconData> _sectionIcons = {
    'Maintenance': Icons.build_rounded,
    'Care & Detailing': Icons.local_car_wash_rounded,
    'Wheels & Tyres': Icons.tire_repair_rounded,
    'Body & Paint': Icons.format_paint_rounded,
    'Business Solutions': Icons.business_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    // Group by section
    final Map<String, List<_ServiceEntry>> grouped = {};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.section, () => <_ServiceEntry>[]).add(entry);
    }

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          // ── Hero banner ──────────────────────────────────────
          SliverToBoxAdapter(child: _buildHero()),

          // ── Search bar ───────────────────────────────────────
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildSearchBar(),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────
          if (_searchQuery.isEmpty) ...[
            // Sections in order
            for (final section in _sectionOrder)
              if (grouped.containsKey(section)) ...[
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: _buildSectionHeader(
                        section,
                        _sectionIcons[section] ?? Icons.star_rounded,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        children: grouped[section]!
                            .map((entry) => _buildServiceCard(entry))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ],
            // Emergency banner
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _buildEmergencyBanner(),
                ),
              ),
            ),
          ] else ...[
            // Flat search results
            if (filtered.isEmpty)
              SliverFillRemaining(child: _buildEmptySearch())
            else
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children:
                          filtered.map((entry) => _buildServiceCard(entry)).toList(),
                    ),
                  ),
                ),
              ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────
  Widget _buildHero() {
    return Stack(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: Image.asset(
            'assets/images/service_screen.jpg',
            fit: BoxFit.cover,
          ),
        ),
        // Gradient overlay
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.black.withOpacity(0.25),
                Colors.black.withOpacity(0.85),
              ],
            ),
          ),
        ),
        // Safe area top padding
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gold.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Text overlay
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eyebrow
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withOpacity(0.5)),
                ),
                child: const Text(
                  'SERVICES',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Everything your vehicle needs,\nall in one place.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Search bar ───────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: _gold.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search services…',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            prefixIcon: Icon(Icons.search_rounded,
                color: _gold.withOpacity(0.7), size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.close_rounded,
                        color: Colors.white38, size: 20),
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Section header ───────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _gold.withOpacity(0.3)),
            ),
            child: Icon(icon, color: _gold, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _gold.withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Service card (horizontal) ────────────────────────────
  Widget _buildServiceCard(_ServiceEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GestureDetector(
        onTap: entry.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _gold.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: _gold.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                ),
                child: Stack(
                  children: [
                    Image.asset(
                      entry.image,
                      width: 96,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 96,
                        height: 88,
                        color: const Color(0xFF262626),
                        child: const Icon(Icons.image_not_supported_rounded,
                            color: Colors.white24, size: 28),
                      ),
                    ),
                    // Subtle left-edge gold accent line
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _gold,
                              _gold.withOpacity(0.3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Text content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (entry.comingSoon)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'SOON',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.subtitle,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Arrow
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: entry.comingSoon
                        ? Colors.transparent
                        : _gold.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: entry.comingSoon
                          ? Colors.white12
                          : _gold.withOpacity(0.35),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: entry.comingSoon ? Colors.white24 : _gold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Emergency banner (Section 5) ─────────────────────────
  Widget _buildEmergencyBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RoadsideAssistanceScreen()),
        ),
        child: Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _gold.withOpacity(0.4)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/roadside_assistance_banner.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.6)),
                            ),
                            child: const Text(
                              '24/7',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Roadside Assistance',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Emergency support whenever you need it.',
                        style:
                            TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Text(
                          'GET HELP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty search state ───────────────────────────────────
  Widget _buildEmptySearch() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded,
              size: 52, color: Colors.white.withOpacity(0.12)),
          const SizedBox(height: 16),
          Text(
            'No services found for "$_searchQuery"',
            style: const TextStyle(color: Colors.white38, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────
class _ServiceEntry {
  final String section;
  final String name;
  final String subtitle;
  final String image;
  final VoidCallback onTap;
  final bool comingSoon;

  const _ServiceEntry({
    required this.section,
    required this.name,
    required this.subtitle,
    required this.image,
    required this.onTap,
    this.comingSoon = false,
  });
}