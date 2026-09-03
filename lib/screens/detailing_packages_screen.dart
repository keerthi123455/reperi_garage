import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DetailingPackagesScreen extends StatefulWidget {
  const DetailingPackagesScreen({super.key});

  @override
  State<DetailingPackagesScreen> createState() =>
      _DetailingPackagesScreenState();
}

class _DetailingPackagesScreenState extends State<DetailingPackagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedCategory = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF262626),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── HERO SECTION ──
            _buildHeroSection(),

            // ── QUICK STATS ──
            _buildQuickStats(),

            const SizedBox(height: 32),

            // ── SERVICE CATEGORIES ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Your Service',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCategoryTabs(),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── PACKAGES CONTENT ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildServiceContent(),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── HERO SECTION ──
  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1C1C1C),
            const Color(0xFF262626),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              const Text(
                'Professional',
                style: TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Detailing Services',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Premium protection for your vehicle',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 16),

              // PAY AFTER DELIVERY & BENEFITS SECTION
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFD4A017).withOpacity(0.15),
                      const Color(0xFFD4A017).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFD4A017),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    // Main Banner
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFD4A017),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'PAY AFTER DELIVERY',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Divider
                    Container(
                      height: 1,
                      color: const Color(0xFFD4A017).withOpacity(0.3),
                    ),

                    const SizedBox(height: 16),

                    // Benefit 1: 24hr Updates
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.image_rounded,
                            color: Color(0xFFD4A017),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Get 24hr Updates',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Real-time updates with images',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Benefit 2: 24/7 Assistance
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.phone_in_talk_rounded,
                            color: Color(0xFFD4A017),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '24/7 Assistance',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Expert support anytime on call',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  // ── QUICK STATS ──
  Widget _buildQuickStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatCard(
                icon: Icons.schedule,
                value: '2-5 Days',
                label: 'Turnaround',
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.shield_rounded,
                value: '8 Years',
                label: 'Max Warranty',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.verified_outlined,
                value: 'Free',
                label: 'Inspection After Week',
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.check_circle_rounded,
                value: 'Free',
                label: 'Post-Service Wash',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF2A2A2A),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFD4A017), size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CATEGORY TABS ──
  Widget _buildCategoryTabs() {
    final categories = ['PPF', 'Ceramic', 'Graphene', 'Sun Film'];
    
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = index),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          const Color(0xFFFFE6B3),
                          const Color(0xFFF0C65A),
                          const Color(0xFFE8B92A),
                        ],
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF151515),
                borderRadius: BorderRadius.circular(12),
                border: !isSelected
                    ? Border.all(
                        color: const Color(0xFF2A2A2A),
                        width: 1,
                      )
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFD4A017).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                categories[index],
                style: TextStyle(
                  color: isSelected ? Colors.black87 : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── SERVICE CONTENT ──
  Widget _buildServiceContent() {
    switch (_selectedCategory) {
      case 0:
        return _buildPPFContent();
      case 1:
        return _buildCeramicContent();
      case 2:
        return _buildGrapheneContent();
      case 3:
        return _buildSunFilmContent();
      default:
        return const SizedBox();
    }
  }

  // ── PPF CONTENT ──
  Widget _buildPPFContent() {
    final packages = [
      {
        'brand': 'PPF Premium',
        'price': '₹55,000',
        'coverage': '400 sq ft base',
        'warranty': '3-5 Years',
        'turnaround': '3 Days (New)',
        'pricePerSqFt': '₹400/sq ft',
        'isPremium': false,
      },
      {
        'brand': 'Garware Pro',
        'price': '₹75,000 - ₹1,00,000',
        'coverage': 'Full Coverage',
        'warranty': '8 Years',
        'turnaround': '5 Days (Used)',
        'pricePerSqFt': 'Premium Pricing',
        'isPremium': true,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Paint Protection Film',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ultimate protection against scratches, chips & UV',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        ...packages.map((pkg) => _buildPackageCard(pkg)).toList(),
        const SizedBox(height: 20),
        _buildInfoBox(
          title: 'Service Timeline',
          items: [
            '• New Car PPF: 3 Days',
            '• Used Car PPF: 5 Days (includes polish)',
            '• Peel & Redo: 7-10 Days',
            '• Free wash after completion',
          ],
        ),
      ],
    );
  }

  // ── CERAMIC CONTENT ──
  Widget _buildCeramicContent() {
    final packages = [
      {
        'brand': 'Ceramic Coating',
        'price': '₹16,000',
        'coverage': 'Full Vehicle',
        'warranty': '1 Year',
        'turnaround': '2 Days',
        'feature': 'Glossy Finish',
        'isPremium': false,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ceramic Coating',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hydrophobic protection with stunning gloss',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        ...packages.map((pkg) => _buildPackageCard(pkg)).toList(),
        const SizedBox(height: 20),
        _buildInfoBox(
          title: 'What You Get',
          items: [
            '✓ Water beading effect',
            '✓ Enhanced glossiness',
            '✓ Easy maintenance',
            '✓ Professional application',
          ],
        ),
      ],
    );
  }

  // ── GRAPHENE CONTENT ──
  Widget _buildGrapheneContent() {
    final packages = [
      {
        'brand': 'Graphene Coating',
        'price': '₹22,000',
        'coverage': 'Full Vehicle',
        'warranty': '3 Years',
        'turnaround': '2 Days',
        'feature': 'Advanced Protection',
        'isPremium': true,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Graphene Coating',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Next-gen protection with nano-technology',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        ...packages.map((pkg) => _buildPackageCard(pkg)).toList(),
        const SizedBox(height: 20),
        _buildInfoBox(
          title: 'Advanced Features',
          items: [
            '✓ Graphene nano-particles',
            '✓ Superior durability',
            '✓ Self-cleaning properties',
            '✓ UV protection included',
          ],
        ),
      ],
    );
  }

  // ── SUN FILM CONTENT ──
  Widget _buildSunFilmContent() {
    final packages = [
      {
        'brand': 'Sun Film - Standard',
        'price': '₹20,000 - ₹45,000',
        'coverage': 'Variable',
        'warranty': '5 Years',
        'turnaround': '2 Days',
        'feature': 'Heat Rejection',
        'isPremium': false,
      },
      {
        'brand': 'Stek Brand Premium',
        'price': '₹25,000',
        'coverage': 'Full Body',
        'warranty': '5-10 Years',
        'turnaround': '2 Days',
        'feature': 'Maximum Protection',
        'isPremium': true,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sun Film Protection',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Beat the heat with premium UV blocking',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        ...packages.map((pkg) => _buildPackageCard(pkg)).toList(),
        const SizedBox(height: 20),
        _buildCoverageOptions(),
      ],
    );
  }

  // ── PACKAGE CARD ──
  Widget _buildPackageCard(Map<String, dynamic> package) {
    return _InteractiveCard(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: package['isPremium'] == true
                ? const Color(0xFFD4A017)
                : const Color(0xFF2A2A2A),
            width: package['isPremium'] == true ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package['brand'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package['feature'] ?? package['coverage'],
                      style: const TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (package['isPremium'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'RECOMMENDED',
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

          const SizedBox(height: 12),

          // Divider
          Container(
            height: 1,
            color: const Color(0xFF2A2A2A),
          ),

          const SizedBox(height: 12),

          // Details Grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Price',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package['price'],
                      style: const TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Warranty',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package['warranty'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Timeline',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package['turnaround'],
                      style: const TextStyle(
                        color: Colors.white,
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

          // Book Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: _AnimatedBookButton(
              onPressed: () => _showBookingConfirmation(package),
            ),
          ),
        ],
      ),
    ),
  );
  }

  // ── INFO BOX ──
  Widget _buildInfoBox({
    required String title,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFD4A017),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  item,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.6,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  // ── COVERAGE OPTIONS (Sun Film) ──
  Widget _buildCoverageOptions() {
    final coverageOptions = [
      {'area': 'Front', 'price': '₹8,000'},
      {'area': 'Sides', 'price': '₹8,000'},
      {'area': 'Front + Sides', 'price': '₹15,000'},
      {'area': 'Full Coverage', 'price': '₹20,000+'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Coverage Options',
            style: TextStyle(
              color: Color(0xFFD4A017),
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: coverageOptions.map((option) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2A2A2A),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        option['area']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option['price']!,
                        style: const TextStyle(
                          color: Color(0xFFD4A017),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── BOOKING CONFIRMATION DIALOG ──
  void _showBookingConfirmation(Map<String, dynamic> package) {
    final serviceName = package['brand'] ?? 'Service';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Check icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: const Color(0xFFD4A017),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFFD4A017),
                  size: 40,
                ),
              ),

              const SizedBox(height: 20),

              // Service name (no "Booking Confirmed!" title)
              Text(
                serviceName,
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 20),

              // Message box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2A2A2A),
                    width: 1,
                  ),
                ),
                child: const Text(
                  'On confirming, our expert will have a discussion with you and go ahead with the further processes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Confirm button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showSuccessAnimation(serviceName, package: package);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'DISCUSS',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Cancel button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF2A2A2A),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'MAYBE LATER',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.5,
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

  // ── SUCCESS ANIMATION DIALOG ──
  void _showSuccessAnimation(String serviceName, {Map<String, dynamic>? package}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated check icon
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFD4A017).withOpacity(0.1),
                            border: Border.all(
                              color: const Color(0xFFD4A017),
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Color(0xFFD4A017),
                            size: 50,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Animated message
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeIn,
                    builder: (context, opacity, child) {
                      return Opacity(
                        opacity: opacity,
                        child: Column(
                          children: [
                            Text(
                              serviceName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFD4A017),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),

                            const SizedBox(height: 16),

                            const Text(
                              'WE WILL CONNECT WITH YOU SHORTLY',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                height: 1.4,
                              ),
                            ),

                            const SizedBox(height: 12),

                            const Text(
                              'Our expert will reach out to discuss your requirements and schedule the service',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Loading dots animation
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeIn,
                    builder: (context, opacity, child) {
                      return Opacity(
                        opacity: opacity,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildAnimatedDot(0),
                            const SizedBox(width: 8),
                            _buildAnimatedDot(1),
                            const SizedBox(width: 8),
                            _buildAnimatedDot(2),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Auto-close dialog and save booking after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && Navigator.canPop(context)) {
        _saveBookingToDatabase(serviceName, package: package);
        Navigator.pop(context);
      }
    });
  }

  // ── ANIMATED DOT HELPER ──
  Widget _buildAnimatedDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return AnimatedBuilder(
          animation: AlwaysStoppedAnimation(DateTime.now().millisecond / 1000),
          builder: (context, child) {
            double animValue = (DateTime.now().millisecondsSinceEpoch / 500 + index) % 2 / 1;
            if (animValue > 1) animValue = 2 - animValue;

            return Transform.scale(
              scale: 0.6 + (animValue * 0.4),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD4A017).withOpacity(0.6 + (animValue * 0.4)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── SAVE BOOKING TO DATABASE ──
  Future<void> _saveBookingToDatabase(
    String serviceName, {
    Map<String, dynamic>? package,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        print('❌ User not authenticated');
        return;
      }

      // Get name from profiles table
      final profileResponse = await supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .single();

      final userName = profileResponse['name'] ?? 'Guest';
      
      // Get phone from user metadata
      final userPhone = user.userMetadata?['phone'] ?? '';

      // Get service category
      final serviceCategory = _getServiceCategory(serviceName);
      final servicePrice = package?['price'] ?? 'Contact for price';
      final serviceWarranty = package?['warranty'] ?? 'Contact for details';

      // Insert into detailing_bookings table
      final response = await supabase.from('detailing_bookings').insert({
        'user_id': user.id,
        'user_name': userName,
        'user_email': user.email,
        'user_phone': userPhone,
        'service_name': serviceName,
        'service_category': serviceCategory,
        'service_price': servicePrice,
        'service_warranty': serviceWarranty,
      }).select();

      if (response != null && response.isNotEmpty) {
        print('✅ Booking saved: ${response[0]['id']}');
      }
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  // ── HELPER METHOD TO GET SERVICE CATEGORY ──
  String _getServiceCategory(String serviceName) {
    if (serviceName.contains('PPF') || serviceName.contains('Garware')) {
      return 'PPF';
    } else if (serviceName.contains('Ceramic')) {
      return 'Ceramic';
    } else if (serviceName.contains('Graphene')) {
      return 'Graphene';
    } else if (serviceName.contains('Sun Film') || serviceName.contains('Stek')) {
      return 'Sun Film';
    }
    return 'Other';
  }
}

// ── ANIMATED BOOK BUTTON ──
class _AnimatedBookButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _AnimatedBookButton({required this.onPressed});

  @override
  State<_AnimatedBookButton> createState() => _AnimatedBookButtonState();
}

class _AnimatedBookButtonState extends State<_AnimatedBookButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: const Color(0xFFD4A017),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4A017).withOpacity(_pressed ? 0.3 : 0.5),
              blurRadius: _pressed ? 6 : 12,
              spreadRadius: _pressed ? 0 : 1,
              offset: Offset(0, _pressed ? 2 : 6),
            ),
          ],
        ),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: const Center(
            child: Text(
              'DISCUSS',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── INTERACTIVE CARD WRAPPER WITH 3D EFFECTS ──
class _InteractiveCard extends StatefulWidget {
  final Widget child;

  const _InteractiveCard({
    required this.child,
  });

  @override
  State<_InteractiveCard> createState() => _InteractiveCardState();
}

class _InteractiveCardState extends State<_InteractiveCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_pressed ? 0.15 : 0.25),
              blurRadius: _pressed ? 8 : 16,
              spreadRadius: _pressed ? 0 : 2,
              offset: Offset(0, _pressed ? 2 : 8),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(_pressed ? 0.05 : 0.1),
              blurRadius: _pressed ? 4 : 8,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
        ),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}