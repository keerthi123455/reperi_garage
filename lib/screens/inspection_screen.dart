import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/address_service.dart';
import '../services/delivery_partner_assignment_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/placeholder_box.dart';
import 'payment_screen.dart';

/// One of the 10 inspection categories shown in "What we check".
class _Category {
  const _Category({
    required this.icon,
    required this.title,
    required this.summary,
    required this.checks,
    required this.howWeCheck,
    required this.score,
  });

  final IconData icon;
  final String title;

  /// Short "Scratches • Dents • Panels" line shown collapsed.
  final String summary;
  final List<String> checks;
  final String howWeCheck;

  /// Sample score out of 10 — illustrative only, shown as part of the
  /// "what a finished report looks like" preview, not a live reading.
  final double score;
}

const List<_Category> _kCategories = [
  _Category(
    icon: Symbols.directions_car,
    title: 'Exterior & Body',
    summary: 'Scratches • Dents • Panels • Alignment',
    checks: [
      'Scratches', 'Dents', 'Body panels', 'Panel alignment',
      'Bumpers', 'Mirrors', 'Glass', 'Doors', 'Bonnet', 'Boot',
    ],
    howWeCheck: 'Professional visual and functional inspection.',
    score: 8.0,
  ),
  _Category(
    icon: Symbols.format_paint,
    title: 'Paint Condition',
    summary: 'Major panels • Consistency • Variation',
    checks: ['Major body panels', 'Paint consistency', 'Panel variations'],
    howWeCheck: 'Professional paint thickness meter.',
    score: 9.1,
  ),
  _Category(
    icon: Icons.memory,
    title: 'Computer Diagnostics',
    summary: 'Engine • ECU • ABS • Airbags',
    checks: ['Engine', 'ECU', 'ABS', 'Airbags', 'Transmission', 'Other supported modules'],
    howWeCheck: 'Professional OBD scanner.',
    score: 8.5,
  ),
  _Category(
    icon: Icons.settings,
    title: 'Engine Bay',
    summary: 'Leaks • Oil • Coolant • Wiring',
    checks: ['Visible leaks', 'Oil', 'Coolant', 'Brake fluid', 'Hoses', 'Wiring', 'Connections'],
    howWeCheck: 'Physical inspection of the engine bay.',
    score: 7.9,
  ),
  _Category(
    icon: Symbols.tire_repair,
    title: 'Tyres & Wheels',
    summary: 'Wear • Cuts • Bulges • Rim condition',
    checks: [
      'Tyre wear', 'Uneven wear', 'Cuts', 'Cracks',
      'Bulges', 'Rim condition', 'Spare tyre',
    ],
    howWeCheck: 'Physical inspection of every tyre and wheel.',
    score: 7.4,
  ),
  _Category(
    icon: Symbols.car_repair,
    title: 'Brakes & Suspension',
    summary: 'Discs • Suspension • Leaks • Wear',
    checks: [
      'Accessible brake components', 'Brake disc condition',
      'Suspension components', 'Visible leaks', 'Visible wear',
    ],
    howWeCheck: 'Physical inspection of accessible components.',
    score: 8.2,
  ),
  _Category(
    icon: Icons.electrical_services,
    title: 'Electrical Systems',
    summary: 'Lights • Horn • Wipers • Locks',
    checks: [
      'Headlights', 'Indicators', 'Brake lights', 'Reverse lights',
      'Horn', 'Wipers', 'Windows', 'Locks', 'Mirrors',
    ],
    howWeCheck: 'Functional check of every electrical system.',
    score: 9.0,
  ),
  _Category(
    icon: Symbols.ac_unit,
    title: 'AC & Interior',
    summary: 'Cooling • Dashboard • Seats • Infotainment',
    checks: [
      'AC cooling', 'Blower', 'Dashboard', 'Seats', 'Seatbelts',
      'Controls', 'Infotainment', 'Cameras', 'Parking sensors',
    ],
    howWeCheck: 'Functional check of cabin systems.',
    score: 8.7,
  ),
  _Category(
    icon: Icons.speed,
    title: 'Functional Check',
    summary: 'Starting • Steering • Braking • Noises',
    checks: [
      'Starting', 'Engine idle', 'Steering', 'Braking',
      'Acceleration', 'Transmission', 'Vibrations', 'Unusual noises',
    ],
    howWeCheck: 'On-road and stationary functional assessment.',
    score: 8.1,
  ),
  _Category(
    icon: Symbols.verified,
    title: 'Final Condition',
    summary: 'Dashboard alerts • Overall condition',
    checks: ['Dashboard alerts', 'Key functions', 'Exterior', 'Interior', 'Overall condition'],
    howWeCheck: 'Final quality verification before handover.',
    score: 8.6,
  ),
];

double get _kOverallScore =>
    _kCategories.map((c) => c.score).reduce((a, b) => a + b) / _kCategories.length;

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
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

  /// Brief explanation sheet for the 3 benefit cards — an optional image
  /// (Advanced Scan/Paint Analysis have one, Digital Report doesn't) plus
  /// a short title and description.
  void _showBenefitSheet({String? imagePath, required String title, required String description}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (imagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            PlaceholderBox(label: imagePath.split('/').last, borderRadius: 0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  title,
                  style: GoogleFonts.manrope(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.txt),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: GoogleFonts.manrope(fontSize: 14, height: 1.6, color: AppColors.mut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Records the completed booking in its own table rather than the
  /// generic `bookings` one — a vehicle health check isn't a pickup/drop
  /// package booking, so it gets its own home.
  Future<void> _saveInspectionBooking(String orderId, String paymentId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final defaultAddr = await AddressService().getDefaultAddress();
    // Alternates between delivery partner 1 and 2 for every booking.
    final deliveryPartnerId =
        await DeliveryPartnerAssignmentService.getNextDeliveryPartnerId('inspection_booking');

    await Supabase.instance.client.from('inspection_booking').insert({
      'user_id': user.id,
      'vehicle_id': widget.vehicleId,
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'pickup_address': defaultAddr?['address'],
      'pickup_latitude': defaultAddr?['latitude'],
      'pickup_longitude': defaultAddr?['longitude'],
      'pickup_address_name': defaultAddr?['name'],
      'dropoff_address': defaultAddr?['address'],
      'dropoff_latitude': defaultAddr?['latitude'],
      'dropoff_longitude': defaultAddr?['longitude'],
      'dropoff_address_name': defaultAddr?['name'],
      'delivery_partner_id': deliveryPartnerId,
      // Always yes — a vehicle health check is doorstep pickup/drop by
      // nature, no opt-out toggle for this service.
      'pickupdrop': 'yes',
      'status': 'booked',
    });
  }

  void _planInspection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: 'Vehicle Health Check',
          price: 'Get Quote',
          duration: 'Report in 30 min',
          vehicleId: widget.vehicleId,
          showPickupDropOption: false,
          onSuccess: _saveInspectionBooking,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          SingleChildScrollView(
            // Bottom padding keeps the last card clear of the sticky bar.
            padding: const EdgeInsets.only(bottom: 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hero(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Everything your vehicle needs. One complete check.'),
                      const SizedBox(height: 10),
                      Text(
                        'Our comprehensive vehicle health check examines your vehicle '
                        'across critical categories — from diagnostics and paint '
                        'condition to tyres, brakes, electronics and more.',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          height: 1.6,
                          color: AppColors.mut,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _BenefitCard(
                              icon: Icons.memory,
                              label: 'Advanced\nScan',
                              onTap: () => _showBenefitSheet(
                                imagePath: 'assets/images/obd.jpeg',
                                title: 'Advanced Computer Diagnostics',
                                description:
                                    'We plug in a professional OBD scanner and read '
                                    'supported electronic systems — engine, ABS, '
                                    'airbags, transmission and more — for fault codes '
                                    'and alerts your dashboard might not show.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _BenefitCard(
                              icon: Symbols.format_paint,
                              label: 'Paint\nAnalysis',
                              onTap: () => _showBenefitSheet(
                                imagePath: 'assets/images/paintthickness.jpeg',
                                title: 'Professional Paint Analysis',
                                description:
                                    'Using a paint thickness meter, we measure '
                                    'readings across every major body panel to spot '
                                    'inconsistencies that can point to a past repaint '
                                    'or repair.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _BenefitCard(
                              icon: Symbols.description,
                              label: 'Digital\nReport',
                              onTap: () => _showBenefitSheet(
                                title: 'Your Digital Report',
                                description:
                                    'Within 30 minutes of the inspection, you get a '
                                    'digital report with your REPERI Score, a score '
                                    'for every category, diagnostic and paint '
                                    'readings, photos, and our recommendations.',
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 34),
                      _ReperiScoreCard(score: _kOverallScore),

                      const SizedBox(height: 34),
                      _sectionTitle('What we check'),
                      const SizedBox(height: 6),
                      Text(
                        'Tap a category to see exactly what\'s covered.',
                        style: GoogleFonts.manrope(fontSize: 13, color: AppColors.mut),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      for (var i = 0; i < _kCategories.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CategoryCard(
                            index: i,
                            category: _kCategories[i],
                            expanded: _expanded.contains(i),
                            onTap: () => setState(() {
                              if (!_expanded.add(i)) _expanded.remove(i);
                            }),
                          ),
                        ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: _FeatureImageSection(
                    assetPath: 'assets/images/obd.jpeg',
                    eyebrow: 'ADVANCED COMPUTER DIAGNOSTICS',
                    title: 'Understand what your car is telling you.',
                    description:
                        'Using a professional OBD scanner, we inspect supported '
                        'electronic systems and identify diagnostic alerts.',
                    checks: const [
                      'Engine', 'ABS', 'Airbags', 'Transmission', 'Steering', 'TPMS',
                    ],
                    scoreLabel: 'Diagnostics Health',
                    score: 8.5,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
                  child: _FeatureImageSection(
                    assetPath: 'assets/images/paintthickness.jpeg',
                    eyebrow: 'PROFESSIONAL PAINT ANALYSIS',
                    title: 'Know more about your vehicle\'s paint condition.',
                    description:
                        'Using a paint thickness measuring meter, we measure paint '
                        'readings across major body panels.',
                    checks: const [
                      'Bonnet', 'Roof', 'Front fenders', 'Doors', 'Rear panels', 'Boot',
                    ],
                    scoreLabel: 'Paint Condition',
                    score: 8.8,
                    footnote: 'Paint thickness readings help identify variations between '
                        'panels. Areas with significant variation may require further '
                        'inspection.',
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 34, 20, 0),
                  child: _DigitalReportCard(overallScore: _kOverallScore),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _StickyPlanBar(onTap: _planInspection),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: AppColors.txt,
      ),
    );
  }
}

// ── HERO ───────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 340,
          child: Image.asset(
            'assets/images/inspection_hero.jpeg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const PlaceholderBox(label: 'inspection_hero.jpeg', borderRadius: 0),
          ),
        ),
        // Gradient built from AppColors.ink rather than a literal black so
        // it flips to a light scrim in light mode instead of staying a
        // dark hue the text can't sit on.
        Container(
          width: double.infinity,
          height: 340,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.ink,
                AppColors.ink.withOpacity(0.75),
                AppColors.ink.withOpacity(0.0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.maybePop(context),
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
                Text(
                  'COMPLETE VEHICLE\nHEALTH CHECK',
                  style: GoogleFonts.manrope(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -0.5,
                    color: AppColors.txt,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Know your vehicle. Before you drive.',
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    color: AppColors.txt.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, color: AppColors.onAccentDark, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'DIGITAL REPORT READY IN 30 MINUTES',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: AppColors.onAccentDark,
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
}

// ── BENEFIT CARD ─────────────────────────────────────────────────────
class _BenefitCard extends StatelessWidget {
  const _BenefitCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.accent, size: 26),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── REPERI SCORE CARD ────────────────────────────────────────────────
class _ReperiScoreCard extends StatelessWidget {
  const _ReperiScoreCard({required this.score});
  final double score;

  String _statusFor(double s) {
    if (s >= 8) return 'GOOD VEHICLE HEALTH';
    if (s >= 5) return 'ATTENTION RECOMMENDED';
    return 'FURTHER INSPECTION RECOMMENDED';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            'REPERI SCORE',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: score / 10,
                    strokeWidth: 8,
                    backgroundColor: AppColors.line,
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score.toStringAsFixed(1),
                      style: GoogleFonts.manrope(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: AppColors.txt,
                      ),
                    ),
                    Text(
                      '/ 10',
                      style: GoogleFonts.manrope(fontSize: 14, color: AppColors.mut),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _statusFor(score),
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: AppColors.txt,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Every inspection category receives an individual Vehicle Health '
            'Score. All category scores are combined to generate your overall '
            'REPERI Score out of 10.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 12.5, height: 1.6, color: AppColors.mut),
          ),
        ],
      ),
    );
  }
}

// ── EXPANDABLE CATEGORY CARD ─────────────────────────────────────────
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.index,
    required this.category,
    required this.expanded,
    required this.onTap,
  });

  final int index;
  final _Category category;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: expanded ? AppColors.accent.withOpacity(0.5) : AppColors.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(category.icon, color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(index + 1).toString().padLeft(2, '0')}  ${category.title}',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.txt,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            category.summary,
                            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.mut),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: expanded ? 0.25 : 0,
                      child: Icon(Symbols.chevron_right, color: AppColors.mut),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 16),
                  Container(height: 1, color: AppColors.line),
                  const SizedBox(height: 16),
                  Text(
                    'WHAT WE CHECK',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: category.checks.map((c) => _checkChip(c)).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'HOW WE CHECK',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    category.howWeCheck,
                    style: GoogleFonts.manrope(fontSize: 13, height: 1.5, color: AppColors.txt),
                  ),
                  const SizedBox(height: 16),
                  _scoreRow('${category.title} Score', category.score),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _checkChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.txt),
      ),
    );
  }
}

/// Shared "Xyz Score  ████████░░  8.2/10" row used in category details and
/// the feature image sections below.
Widget _scoreRow(String label, double score) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.txt),
          ),
          Text(
            '${score.toStringAsFixed(1)} / 10',
            style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.accent),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: score / 10,
          minHeight: 8,
          backgroundColor: AppColors.line,
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      ),
    ],
  );
}

// ── FEATURE IMAGE SECTION (OBD / Paint) ──────────────────────────────
class _FeatureImageSection extends StatelessWidget {
  const _FeatureImageSection({
    required this.assetPath,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.checks,
    required this.scoreLabel,
    required this.score,
    this.footnote,
  });

  final String assetPath;
  final String eyebrow;
  final String title;
  final String description;
  final List<String> checks;
  final String scoreLabel;
  final double score;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  PlaceholderBox(label: assetPath.split('/').last, borderRadius: 0),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          eyebrow,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.manrope(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.txt),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: GoogleFonts.manrope(fontSize: 13.5, height: 1.6, color: AppColors.mut),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: checks
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 13, color: AppColors.accent),
                        const SizedBox(width: 5),
                        Text(
                          c,
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.txt,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: _scoreRow(scoreLabel, score),
        ),
        if (footnote != null) ...[
          const SizedBox(height: 12),
          Text(
            footnote!,
            style: GoogleFonts.manrope(fontSize: 11.5, height: 1.5, color: AppColors.mut),
          ),
        ],
      ],
    );
  }
}

// ── DIGITAL REPORT SECTION ───────────────────────────────────────────
class _DigitalReportCard extends StatelessWidget {
  const _DigitalReportCard({required this.overallScore});
  final double overallScore;

  static const _includes = [
    'Overall REPERI Score / 10',
    'Score for every category',
    'OBD diagnostic findings',
    'Paint thickness readings',
    'Vehicle condition summary',
    'Inspection observations',
    'Relevant photos',
    'Technician notes',
    'Recommendations',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accent.withOpacity(0.18), AppColors.accent.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.accent.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              Icon(Icons.bar_chart, color: AppColors.accent, size: 34),
              const SizedBox(height: 12),
              Text(
                'YOUR DIGITAL\nVEHICLE HEALTH REPORT',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'READY IN 30 MINUTES',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your report includes',
                style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.txt),
              ),
              const SizedBox(height: 12),
              for (final item in _includes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(Symbols.check_circle, size: 16, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.txt),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Sample report preview — illustrative mock-up of the finished
        // report, not a live reading for this vehicle.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SAMPLE REPORT PREVIEW',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.mut,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'REPERI SCORE',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent),
              ),
              const SizedBox(height: 4),
              Text(
                '${overallScore.toStringAsFixed(1)} / 10',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.txt),
              ),
              const SizedBox(height: 18),
              Container(height: 1, color: AppColors.line),
              const SizedBox(height: 14),
              for (final c in _kCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        c.title,
                        style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.txt),
                      ),
                      Text(
                        '${c.score.toStringAsFixed(1)} / 10',
                        style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.mut),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── STICKY BOTTOM BAR ────────────────────────────────────────────────
class _StickyPlanBar extends StatelessWidget {
  const _StickyPlanBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(AppColors.isDark ? 0.25 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccentDark,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              'PLAN INSPECTION',
              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
