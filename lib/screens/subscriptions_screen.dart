import 'package:flutter/material.dart';
import 'payment_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionsScreen extends StatefulWidget {
  final String vehicleId;

  const SubscriptionsScreen({
    super.key,
    required this.vehicleId,
  });

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  String? selectedPlan;



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C0C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFD4A017)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Car Wash Subscriptions',
          style: TextStyle(
            color: Colors.white,
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
                  // Header


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

                  // Subscribe Button
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
                      child: const Center(
                        child: Text(
                          'SUBSCRIBE',
                          style: TextStyle(
                            color: Colors.black,
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

  /// Save subscription to database after successful payment
  Future<void> _saveSubscriptionToDatabase(
    String orderId,
    String paymentId,
  ) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        print('Error: User not authenticated');
        return;
      }

      final planDetails = _getPlanDetails();
      final endDate = DateTime.now().add(const Duration(days: 30));

      await Supabase.instance.client.from('subscriptions').insert({
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
      });

      print('✅ Subscription saved to database');
    } catch (e) {
      print('❌ Error saving subscription: $e');
    }
  }

  void _showPlanSelectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF0C0C0C),
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
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20),
                      child: const Text(
                        'All prices are per month',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Scrollable Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            _buildSubscriptionCard(
                              title: 'Hatchback / Small Cars',
                              price: '₹600',
                              vehicles:
                                  'Maruti Alto K10, Hyundai i20, Tata Punch, etc',
                              isSelected: selectedPlan == 'hatchback',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'hatchback'),
                            ),
                            const SizedBox(height: 16),
                            _buildSubscriptionCard(
                              title: 'SUV / XUV / SEDAN',
                              price: '₹1000',
                              vehicles:
                                  'Mahindra XUV500, Hyundai Creta, Tata Nexon, etc',
                              isSelected: selectedPlan == 'suv',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'suv'),
                            ),
                            const SizedBox(height: 16),
                            _buildSubscriptionCard(
                              title: 'Luxury Cars',
                              price: '₹1200',
                              vehicles: 'Audi, BMW, Mercedes-Benz, etc',
                              isSelected: selectedPlan == 'luxury',
                              onTap: () =>
                                  setDialogState(() => selectedPlan = 'luxury'),
                            ),
                            const SizedBox(height: 16),
                            _buildSubscriptionCard(
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
                                      onSuccess: _saveSubscriptionToDatabase,
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
                                  ? 'SUBSCRIBE NOW'
                                  : 'SELECT A PLAN',
                              style: TextStyle(
                                color: selectedPlan != null
                                    ? Colors.black
                                    : Colors.black54,
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
          'title': 'Car Wash Subscription - Hatchback / Small Cars',
          'price': '600',
        };
      case 'suv':
        return {
          'title': 'Car Wash Subscription - SUV / XUV / SEDAN',
          'price': '1000',
        };
      case 'luxury':
        return {
          'title': 'Car Wash Subscription - Luxury Cars',
          'price': '1200',
        };
      case 'bike':
        return {
          'title': 'Car Wash Subscription - Bike',
          'price': '500',
        };
      default:
        return {
          'title': 'Car Wash Subscription',
          'price': '0',
        };
    }
  }

  Widget _buildSubscriptionCard({
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
              : const Color(0xFF1C1C1C),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    vehicles,
                    style: const TextStyle(
                      color: Color(0xFF888888),
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
                const Text(
                  '/month',
                  style: TextStyle(
                    color: Color(0xFF888888),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF888888),
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