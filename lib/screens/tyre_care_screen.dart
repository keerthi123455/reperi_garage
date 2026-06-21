import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'payment_screen.dart';

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
  // ── Theme constants ─────────────────────────────────────────────
  static const Color _bg = Color(0xFF080808);
  static const Color _card = Color(0xFF111111);
  static const Color _gold = Color(0xFFD4A017);
  static const Color _goldLight = Color(0xFFF5C842);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _grey = Color(0xFF888888);
  static const Color _border = Color(0xFF222222);
  static const Color _red = Color(0xFFE53935);

  // ── State ────────────────────────────────────────────────────────
  String? selectedTyreBrand;
  String? selectedAlloyBrand;
  int? selectedWheelSize;

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

  final List<Map<String, dynamic>> _packages = [
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

  // ── Bottom sheet popup ───────────────────────────────────────────
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

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: _buildFloatingButton(),
      body: SingleChildScrollView(
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
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────
  Widget _buildHero() {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 420,
          child: Image.asset(
            'assets/images/tile_tyre.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF0F0F0F),
              child: const Center(
                child: Icon(Icons.tire_repair, color: _gold, size: 80),
              ),
            ),
          ),
        ),
        // Gradient: black bottom → transparent top
        Container(
          width: double.infinity,
          height: 420,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xFF080808),
                Color(0xCC000000),
                Colors.transparent,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Red accent top-right line
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            width: 3,
            height: 180,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_red, Colors.transparent],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(Icons.arrow_back, color: _white, size: 20),
                  ),
                ),
                const SizedBox(height: 160),
                // PERFORMANCE CENTER badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PERFORMANCE CENTER',
                    style: TextStyle(
                      color: _white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // TYRE CARE big text
                const Text(
                  'TYRE\nCARE',
                  style: TextStyle(
                    color: _white,
                    fontSize: 60,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Precision alignment, balancing and premium wheel performance solutions.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Description box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _gold.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Wheel alignment, balancing, tyre replacement, alloy upgrades and performance optimization using premium equipment.',
                    style: TextStyle(
                      color: _white,
                      fontSize: 13,
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

  // ── SERVICES STRIP ───────────────────────────────────────────────
  Widget _buildServicesStrip() {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'SERVICES INCLUDED',
              style: TextStyle(
                color: _grey,
                fontSize: 10,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _serviceChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gold.withOpacity(0.6)),
                ),
                child: Text(
                  _serviceChips[i],
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
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
      padding: const EdgeInsets.fromLTRB(0, 36, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(width: 3, height: 22, color: _gold),
                const SizedBox(width: 10),
                const Text(
                  'PERFORMANCE PACKAGES',
                  style: TextStyle(
                    color: _white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Tap a card to view details and book',
              style: TextStyle(color: _grey, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
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
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with red accent
          Row(
            children: [
              Container(width: 3, height: 22, color: _red),
              const SizedBox(width: 10),
              const Text(
                'TYRE CHANGE & UPGRADES',
                style: TextStyle(
                  color: _white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // TYRE BRAND SELECTOR
          const Text(
            'SELECT TYRE BRAND',
            style: TextStyle(
              color: _grey,
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tyreBrands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final selected = selectedTyreBrand == _tyreBrands[i];
                return GestureDetector(
                  onTap: () => setState(() => selectedTyreBrand = _tyreBrands[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 120,
                    height: 90,
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? _gold : _border,
                        width: selected ? 2 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: _gold.withOpacity(0.3),
                                blurRadius: 16,
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
                            color: selected ? _gold : _grey,
                            size: 28,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _tyreBrandLabels[i],
                            style: TextStyle(
                              color: selected ? _gold : _grey,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
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

          const SizedBox(height: 28),

          // ALLOY BRAND DROPDOWN
          const Text(
            'ALLOY WHEEL BRAND',
            style: TextStyle(
              color: _grey,
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedAlloyBrand,
                hint: const Text(
                  'Select alloy brand',
                  style: TextStyle(color: _grey, fontSize: 14),
                ),
                dropdownColor: const Color(0xFF1A1A1A),
                icon: const Icon(Icons.keyboard_arrow_down, color: _gold),
                isExpanded: true,
                items: _alloyBrands
                    .map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(
                            b,
                            style: const TextStyle(color: _white, fontSize: 14),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => selectedAlloyBrand = v),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // WHEEL SIZE SELECTOR
          const Text(
            'WHEEL SIZE (INCHES)',
            style: TextStyle(
              color: _grey,
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: _wheelSizes.map((size) {
              final selected = selectedWheelSize == size;
              return GestureDetector(
                onTap: () => setState(() => selectedWheelSize = size),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? _gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected ? _gold : _border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    '$size"',
                    style: TextStyle(
                      color: selected ? Colors.black : _white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // POPULAR UPGRADES
          const Text(
            'POPULAR UPGRADES',
            style: TextStyle(
              color: _grey,
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
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
                            color: const Color(0xFF1A1A1A),
                            child: const Icon(Icons.auto_awesome, color: _gold, size: 36),
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
                            color: _white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 30),

          // REQUEST TYRE CHANGE button
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
              height: 60,
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'REQUEST TYRE CHANGE',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 1.5,
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
      {'icon': Icons.gps_fixed, 'title': 'Laser Alignment\nSystems'},
      {'icon': Icons.auto_awesome, 'title': 'Premium Alloy\nOptions'},
      {'icon': Icons.speed, 'title': 'High-Speed\nBalancing'},
      {'icon': Icons.engineering, 'title': 'Expert Wheel\nTechnicians'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 22, color: _gold),
              const SizedBox(width: 10),
              const Text(
                'WHY CHOOSE US',
                style: TextStyle(
                  color: _white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.5,
            children: items.map((item) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item['icon'] as IconData, color: _gold, size: 26),
                    const SizedBox(height: 10),
                    Text(
                      item['title'] as String,
                      style: const TextStyle(
                        color: _white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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
      {'icon': Icons.compare, 'label': 'Before / After Inspection'},
      {'icon': Icons.bar_chart, 'label': 'Alignment Reports'},
      {'icon': Icons.sync, 'label': 'Real-time Updates'},
      {'icon': Icons.history, 'label': 'Digital Wheel History'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _gold.withOpacity(0.25)),
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
                  child: const Icon(Icons.track_changes, color: _gold, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'LIVE TRACKING INCLUDED',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
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
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item['icon'] as IconData, color: _grey, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        item['label'] as String,
                        style: const TextStyle(color: _white, fontSize: 14),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── FLOATING BUTTON ──────────────────────────────────────────────
  Widget _buildFloatingButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        // TODO: WhatsApp / Phone call / Emergency support
      },
      backgroundColor: _red,
      icon: const Icon(Icons.headset_mic, color: _white),
      label: const Text(
        'CALL OUR EXPERT',
        style: TextStyle(
          color: _white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 1,
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

  static const Color _gold = Color(0xFFD4A017);
  static const Color _card = Color(0xFF111111);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _grey = Color(0xFF888888);
  static const Color _border = Color(0xFF222222);
  static const Color _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final name = package['name'] as String;
    final price = package['price'] as String;
    final features = package['features'] as List<String>;

    // Give top packages a red accent
    final isTopTier = (package['name'] as String).contains('TRACK') ||
        (package['name'] as String).contains('ALLOY');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 320,
        height: 170,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isTopTier ? _red.withOpacity(0.5) : _border,
          ),
          boxShadow: [
            BoxShadow(
              color: isTopTier
                  ? _red.withOpacity(0.08)
                  : Colors.black.withOpacity(0.3),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: _white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  price,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 20,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _gold.withOpacity(0.2)),
                  ),
                  child: Text(
                    f,
                    style: const TextStyle(
                      color: _grey,
                      fontSize: 10,
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
                  style: const TextStyle(color: _grey, fontSize: 11),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isTopTier ? _red : _gold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'VIEW & BOOK',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
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

  static const Color _bg = Color(0xFF0F0F0F);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _gold = Color(0xFFD4A017);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _grey = Color(0xFF888888);
  static const Color _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final name = package['name'] as String;
    final price = package['price'] as String;
    final duration = package['duration'] as String;
    final description = package['description'] as String;
    final features = package['features'] as List<String>;
    final isTopTier = name.contains('TRACK') || name.contains('ALLOY');

    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge + name
                  if (isTopTier)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PREMIUM',
                        style: TextStyle(
                          color: _white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: _white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Price + duration row
                  Row(
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: _grey, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              duration,
                              style: const TextStyle(color: _grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // WHAT WE DO
                  const Text(
                    'WHAT WE DO',
                    style: TextStyle(
                      color: _grey,
                      fontSize: 10,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      description,
                      style: const TextStyle(
                        color: _white,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // FEATURES
                  const Text(
                    'FEATURES',
                    style: TextStyle(
                      color: _grey,
                      fontSize: 10,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _gold.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: _gold, size: 13),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            f,
                            style: const TextStyle(color: _white, fontSize: 14),
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
          // BOOK NOW button
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
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'BOOK NOW',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
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