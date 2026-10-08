import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../services/catalog_service.dart';
import '../widgets/catalog_gate.dart';
import '../models/catalog_item.dart';

class MonthlyWashScreen extends StatefulWidget {
  final String vehicleId;

  /// This screen represents a single service with no sub-packages to
  /// select between, so there's nothing further to highlight — accepted
  /// only so callers that pass it (see buildPackageScreenFor) compile.
  final String? highlightPackage;

  const MonthlyWashScreen({
    super.key,
    required this.vehicleId,
    this.highlightPackage,
  });

  @override
  State<MonthlyWashScreen> createState() => _MonthlyWashScreenState();
}

class _MonthlyWashScreenState extends State<MonthlyWashScreen> {
  /// Filled in by PaymentScreen when this screen was opened before the
  /// customer had a vehicle (see PaymentScreen.onVehicleResolved), so the
  /// booking saved below is attached to the right vehicle.
  String? _resolvedVehicleId;
  String get _vehicleId => _resolvedVehicleId ?? widget.vehicleId;

  String? selectedPlan;

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
    return CatalogGate(builder: (context) {
    if (_plans.isEmpty) {
      return const CatalogEmpty(message: 'Monthly wash plans aren\'t available right now. Please check back soon.');
    }

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.accent),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Monthly Wash Plans',
          style: TextStyle(
            color: AppColors.txt,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What You Get Section (TOP)
                  const Text(
                    'Services You Get',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Benefits
                  _buildBenefitItem(
                    icon: Icons.water_drop,
                    title: '6 Water Washes / Week',
                    description: 'Professional exterior cleaning',
                  ),
                  const SizedBox(height: 16),
                  _buildBenefitItem(
                    icon: Icons.cleaning_services,
                    title: '2 Interior Washes / Week',
                    description: 'Complete interior cabin cleaning',
                  ),
                  const SizedBox(height: 16),
                  _buildBenefitItem(
                    icon: Icons.notifications_active,
                    title: 'Daily App Updates',
                    description: 'Real-time notifications everyday',
                  ),
                  const SizedBox(height: 16),
                  _buildBenefitItem(
                    icon: Icons.card_giftcard,
                    title: 'Free Shampoo Wash',
                    description:
                        'If no update given on a particular day, get free shampoo wash',
                  ),
                  const SizedBox(height: 16),
                  _buildBenefitItem(
                    icon: Icons.schedule,
                    title: 'Flexible Timings',
                    description: '4 AM - 9 AM (Except Wednesdays)',
                  ),
                  const SizedBox(height: 16),
                  _buildBenefitItem(
                    icon: Icons.person_off,
                    title: 'No Contact Required',
                    description:
                        'We pick up & drop your vehicle at your convenience',
                  ),
                  const SizedBox(height: 40),

                  // Enroll Button
                  GestureDetector(
                    onTap: () => _showPlanSelectionDialog(),
                    child: Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFD4A017),
                            Color(0xFFF5C842)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4A017).withOpacity(0.45),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'ENROLL',
                          style: TextStyle(
                            color: AppColors.onAccentDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    ));
    });
  }


  void _showPlanSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: AppColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                  maxWidth: double.infinity,
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Your Plan',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: AppColors.txt),
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All prices are per month',
                            style: TextStyle(
                              color: AppColors.mut,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'One-time payment, valid for 30 days — renew manually, no auto-billing.',
                            style: TextStyle(
                              color: AppColors.mut,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Scrollable Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            // One card per active plan in the services
                            // table (screen 'monthly_wash').
                            for (final plan in _plans) ...[
                              _buildPlanCard(
                                title: plan.detail('plan_label', plan.name),
                                price: plan.priceText,
                                vehicles: plan.detail('vehicles'),
                                isSelected: selectedPlan == plan.detail('plan_type'),
                                onTap: () => setDialogState(
                                    () => selectedPlan = plan.detail('plan_type')),
                              ),
                              const SizedBox(height: 16),
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    // Confirm Button (Sticky at bottom)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: GestureDetector(
                        onTap: selectedPlan != null
                            ? () {
                                final plan = _selectedPlanItem;
                                if (plan == null) return;
                                // Grab the navigator BEFORE popping — `context`
                                // here is this dialog's own, which is on its way
                                // out once pop runs, so pushing from it after is
                                // unsafe.
                                final navigator = Navigator.of(context);
                                navigator.pop();
                                navigator.push(
                                  MaterialPageRoute(
                                    builder: (_) => PaymentScreen(
                                      title: plan.bookingName,
                                      duration: plan.duration,
                                      vehicleId: _vehicleId,
                                      onVehicleResolved: (id) => _resolvedVehicleId = id,
                                      // Saved to monthlywash_table by the server
                                      // (30-day plan, no pickup & drop).
                                      serviceKeys: [plan.key],
                                      bookingSection: 'subscription',
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: selectedPlan != null
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFFD4A017),
                                      Color(0xFFF5C842)
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  )
                                : LinearGradient(
                                    colors: [
                                      const Color(0xFFD4A017).withOpacity(0.5),
                                      const Color(0xFFF5C842).withOpacity(0.5)
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: selectedPlan != null
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFD4A017)
                                          .withOpacity(0.45),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Center(
                            child: Text(
                              selectedPlan != null
                                  ? 'ENROLL NOW'
                                  : 'SELECT A PLAN',
                              style: TextStyle(
                                color: selectedPlan != null
                                    ? AppColors.onAccentDark
                                    : AppColors.onAccentDark.withOpacity(0.6),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
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
          },
        );
      },
    );
  }

  /// Every active monthly plan, live from the services table.
  List<CatalogItem> get _plans => CatalogService.forScreen('monthly_wash');

  /// The plan picked in the dialog (by details.plan_type), if still active.
  CatalogItem? get _selectedPlanItem {
    for (final plan in _plans) {
      if (plan.detail('plan_type') == selectedPlan) return plan;
    }
    return null;
  }


  Widget _buildPlanCard({
    required String title,
    required String price,
    required String vehicles,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFD4A017).withOpacity(0.15)
              : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4A017)
                : const Color(0xFFD4A017).withOpacity(0.25),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.txt,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vehicles,
                    style: TextStyle(
                      color: AppColors.mut,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '/month',
                  style: TextStyle(
                    color: AppColors.mut,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFD4A017).withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFD4A017),
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.mut,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
