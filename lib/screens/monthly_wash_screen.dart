import 'package:flutter/material.dart';
import 'payment_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../services/address_service.dart';
import '../services/apple_review_assignment_override.dart';
import '../widgets/error_display.dart';

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
  }

  /// Save the enrolled wash plan to the database after successful payment.
  ///
  /// This runs as PaymentScreen's onSuccess callback — Razorpay has
  /// already charged the customer by the time this is called, so a
  /// failure here used to mean they were charged with no plan record
  /// ever created and no indication anything went wrong (this caught its
  /// own error and only printed it). It now surfaces an honest message —
  /// payment succeeded, saving the record didn't — with a retry that
  /// re-attempts just this insert using the same orderId/paymentId,
  /// rather than charging them again.
  Future<void> _savePlanToDatabase(
    String orderId,
    String paymentId,
  ) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debugPrint('Error: User not authenticated');
        return;
      }

      final planDetails = _getPlanDetails();
      final endDate = DateTime.now().add(const Duration(days: 30));
      final defaultAddr = await AddressService().getDefaultAddress();
      // No production code assigns a washer to a new subscription at all
      // today (washer_id is only ever set by hand in Supabase) — this
      // only fills it in during Apple review, so the demo subscription
      // shows up on the review washer's dashboard automatically instead
      // of needing a manual database edit for every test run.
      final reviewWasherId = await AppleReviewAssignmentOverride.resolveWasherId(
        customerEmail: user.email,
      );

      await Supabase.instance.client.from('monthlywash_table').insert({
        'user_id': user.id,
        'vehicle_id': widget.vehicleId,
        'plan_type': selectedPlan,
        'plan_title': planDetails['title'],
        'price': double.parse(planDetails['price']!),
        'status': 'active',
        'start_date': DateTime.now().toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'payment_id': paymentId,
        'order_id': orderId,
        'pickup_address': defaultAddr?['address'],
        'pickup_latitude': defaultAddr?['latitude'],
        'pickup_longitude': defaultAddr?['longitude'],
        'pickup_address_name': defaultAddr?['name'],
        if (reviewWasherId != null) 'washer_id': reviewWasherId,
      });

      debugPrint('✅ Wash plan saved to database');
    } catch (e) {
      debugPrint('❌ Error saving wash plan: $e');
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage:
            'Your payment went through, but we couldn\'t save your wash plan (ref: $paymentId). Tap retry, or contact support with that reference if it keeps failing.',
        onRetry: () => _savePlanToDatabase(orderId, paymentId),
      );
    }
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
                            _buildPlanCard(
                              title: 'Hatchback / Small Cars',
                              price: '₹600',
                              vehicles:
                                  'Maruti Alto K10, Hyundai i20, Tata Punch, etc',
                              isSelected: selectedPlan == 'hatchback',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'hatchback'),
                            ),
                            const SizedBox(height: 16),
                            _buildPlanCard(
                              title: 'SUV / XUV / SEDAN',
                              price: '₹1000',
                              vehicles:
                                  'Mahindra XUV500, Hyundai Creta, Tata Nexon, etc',
                              isSelected: selectedPlan == 'suv',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'suv'),
                            ),
                            const SizedBox(height: 16),
                            _buildPlanCard(
                              title: 'Luxury Cars',
                              price: '₹1200',
                              vehicles: 'Audi, BMW, Mercedes-Benz, etc',
                              isSelected: selectedPlan == 'luxury',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'luxury'),
                            ),
                            const SizedBox(height: 16),
                            _buildPlanCard(
                              title: 'Bike',
                              price: '₹500',
                              vehicles: 'All bikes & scooters',
                              isSelected: selectedPlan == 'bike',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'bike'),
                            ),
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
                                final planDetails = _getPlanDetails();
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentScreen(
                                      title: planDetails['title']!,
                                      price: planDetails['price']!,
                                      duration: '1 Month',
                                      vehicleId: widget.vehicleId,
                                      onSuccess: _savePlanToDatabase,
                                      showPickupDropOption: false,
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

  /// Get plan details (title and price) based on selectedPlan
  Map<String, String> _getPlanDetails() {
    switch (selectedPlan) {
      case 'hatchback':
        return {
          'title': 'Monthly Wash Plan - Hatchback / Small Cars',
          'price': '600',
        };
      case 'suv':
        return {
          'title': 'Monthly Wash Plan - SUV / XUV / SEDAN',
          'price': '1000',
        };
      case 'luxury':
        return {
          'title': 'Monthly Wash Plan - Luxury Cars',
          'price': '1200',
        };
      case 'bike':
        return {
          'title': 'Monthly Wash Plan - Bike',
          'price': '500',
        };
      default:
        return {
          'title': 'Monthly Wash Plan',
          'price': '0',
        };
    }
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
