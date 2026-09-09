import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

class FleetManagementScreen extends StatefulWidget {
  const FleetManagementScreen({super.key});

  @override
  State<FleetManagementScreen> createState() => _FleetManagementScreenState();
}

class _FleetManagementScreenState extends State<FleetManagementScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        slivers: [

          // ── HERO SLIVER APP BAR ──────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.txt,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gold glow
                  Positioned(
                    top: -60,
                    right: -60,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD4A017).withOpacity(.13),
                      ),
                    ),
                  ),
                  // Large faint truck icon
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: Icon(
                      Icons.local_shipping_rounded,
                      size: 110,
                      color: AppColors.txt.withOpacity(.05),
                    ),
                  ),
                  // Text content
                  Positioned(
                    left: 20,
                    bottom: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017).withOpacity(.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: const Color(0xFFD4A017).withOpacity(.35)),
                          ),
                          child: const Text(
                            'FLEET PROGRAM',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 10,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Fleet\nManagement',
                          style: TextStyle(
                            color: AppColors.txt,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      const SizedBox(height: 20),

                      // ── STAT ROW ─────────────────────────────
                      Row(
                        children: [
                          _statCard('21', 'STEP CHECK'),
                          const SizedBox(width: 10),
                          _statCard('<1hr', 'REPORT TIME'),
                          const SizedBox(width: 10),
                          _statCard('6', 'CATEGORIES'),
                        ],
                      ),

                      const SizedBox(height: 28),

                      _sectionLabel('ABOUT THE PROGRAM'),
                      const SizedBox(height: 14),

                      // ── INFO CARD ────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Standardized care across every vehicle',
                              style: TextStyle(
                                color: AppColors.txt,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Every vehicle undergoes the same 21-step inspection regardless of location, garage, or mechanic. Digital findings shared within 1 hour of pickup.',
                              style: TextStyle(
                                color: AppColors.mut,
                                height: 1.6,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      _sectionLabel('INSPECTION CATEGORIES'),
                      const SizedBox(height: 14),

                      // ── INSPECTION GRID ──────────────────────
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.1,
                        children: [
                          _inspectionCard(
                            context,
                            icon: Icons.shield_outlined,
                            title: 'Safety',
                            count: 5,
                            gold: true,
                            items: ['Brake Pads', 'Brake Discs', 'Brake Fluid',
                                'Parking Brake', 'Horn'],
                          ),
                          _inspectionCard(
                            context,
                            icon: Icons.build_circle_outlined,
                            title: 'Engine',
                            count: 3,
                            gold: true,
                            items: ['Engine Oil Level', 'Oil Condition', 'Air Filter'],
                          ),
                          _inspectionCard(
                            context,
                            icon: Icons.battery_charging_full,
                            title: 'Battery',
                            count: 2,
                            gold: true,
                            items: ['Battery Health', 'Battery Terminals'],
                          ),
                          _inspectionCard(
                            context,
                            icon: Icons.electrical_services,
                            title: 'Electrical',
                            count: 2,
                            gold: true,
                            items: ['Alternator', 'Starter Motor'],
                          ),
                          _inspectionCard(
                            context,
                            icon: Icons.opacity,
                            title: 'Fluids',
                            count: 3,
                            gold: true,
                            items: ['Coolant Level', 'Leak Check', 'Fluid Inspection'],
                          ),
                          _inspectionCard(
                            context,
                            icon: Icons.tire_repair,
                            title: 'Tyres',
                            count: 5,
                            gold: true,
                            items: ['Tread Depth', 'Tyre Pressure', 'Sidewall Condition',
                                'Wheel Alignment', 'Wheel Balance'],
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      _sectionLabel('SERVICE WORKFLOW'),
                      const SizedBox(height: 14),

                      // ── WORKFLOW ─────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          children: [
                            _workflowStep('1', 'Vehicle Pickup',
                                'Doorstep collection'),
                            _workflowStep('2', '21-Step Inspection',
                                'With photo documentation'),
                            _workflowStep('3', 'Digital Report',
                                'Delivered within 1 hour'),
                            _workflowStep('4', 'Repair Estimate',
                                'Transparent pricing'),
                            _workflowStep('5', 'Approval & Execution',
                                'Your sign-off, then we work',
                                last: true),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── CTA ──────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri(scheme: 'tel', path: '9353094672');
                            await launchUrl(uri);
                          },
                          icon: Icon(Icons.call_rounded, color: AppColors.onAccentDark),
                          label: Text(
                            'CALL US NOW',
                            style: TextStyle(
                              color: AppColors.onAccentDark,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A017),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFD4A017),
        fontSize: 10,
        letterSpacing: 2.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFFD4A017),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.mut,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inspectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required bool gold,
    required List<String> items,
  }) {
    final bg = gold ? const Color(0xFFD4A017) : AppColors.surfaceRaised;
    final titleColor = gold ? AppColors.onAccentDark : AppColors.txt;
    final subtitleColor =
        gold ? const Color(0xFF3A2800) : AppColors.mut;
    final iconColor = gold ? AppColors.onAccentDark : const Color(0xFFD4A017);

    return GestureDetector(
      onTap: () => _showInspectionSheet(context, title, items),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: gold ? null : Border.all(color: AppColors.line),
          boxShadow: gold
              ? [
                  BoxShadow(
                    color: const Color(0xFFD4A017).withOpacity(.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count checkpoints',
              style: TextStyle(
                color: subtitleColor,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workflowStep(String num, String title, String sub,
      {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD4A017).withOpacity(.12),
              border: Border.all(
                  color: const Color(0xFFD4A017).withOpacity(.3)),
            ),
            child: Center(
              child: Text(
                num,
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(
                  color: AppColors.mut,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showInspectionSheet(
      BuildContext context, String title, List<String> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.txt,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...items.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Color(0xFFD4A017),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      e,
                      style: TextStyle(
                        color: AppColors.mut,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
