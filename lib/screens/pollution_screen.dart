import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/address_service.dart';
import '../services/delivery_partner_assignment_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Pollution-certificate pickup/drop-off offer screen.
///
/// [vehicleId] identifies which vehicle this booking is for (mirrors the
/// pattern used by ServicingPackageScreen/WashingPackageScreen etc.).
/// [onAvail] overrides the default "Book Now" behaviour (push
/// PaymentScreen, then record the booking in `pollution_booking`) —
/// left as a callback rather than hardcoding it as the only option, the
/// same way other package screens are awaited with `.then(...)`.
class PollutionScreen extends StatefulWidget {
  const PollutionScreen({
    super.key,
    required this.vehicleId,
    this.onAvail,
  });

  final String vehicleId;
  final VoidCallback? onAvail;

  static const _heroAsset = 'assets/images/pollution.jpeg';
  static const _price = '₹299';

  @override
  State<PollutionScreen> createState() => _PollutionScreenState();
}

class _PollutionScreenState extends State<PollutionScreen> {
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

  Future<void> _callSupport() async {
    await launchUrl(Uri(scheme: 'tel', path: '9353094672'));
  }

  /// Records the completed booking in its own table rather than the
  /// generic `bookings` one — a pollution certificate check isn't a
  /// pickup/drop package booking, so it gets its own home.
  Future<void> _savePollutionBooking(String orderId, String paymentId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final defaultAddr = await AddressService().getDefaultAddress();
    // Alternates between delivery partner 1 and 2 for every booking.
    final deliveryPartnerId =
        await DeliveryPartnerAssignmentService.getNextDeliveryPartnerId('pollution_booking');

    await Supabase.instance.client.from('pollution_booking').insert({
      'user_id': user.id,
      'vehicle_id': widget.vehicleId,
      'price': PollutionScreen._price,
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'pickup_address': defaultAddr?['address'],
      'pickup_latitude': defaultAddr?['latitude'],
      'pickup_longitude': defaultAddr?['longitude'],
      'dropoff_address': defaultAddr?['address'],
      'dropoff_latitude': defaultAddr?['latitude'],
      'dropoff_longitude': defaultAddr?['longitude'],
      'delivery_partner_id': deliveryPartnerId,
      // Always yes — a pollution certificate check is doorstep
      // pickup/drop by nature, no opt-out toggle for this service.
      'pickupdrop': 'yes',
      'status': 'booked',
    });
  }

  void _bookNow() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: 'Pollution Certificate Check',
          price: PollutionScreen._price,
          duration: 'Same day',
          vehicleId: widget.vehicleId,
          showPickupDropOption: false,
          onSuccess: _savePollutionBooking,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Hero()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How it works',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.txt,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _StepTimeline(steps: [
                    _Step(
                      icon: Symbols.directions_car,
                      text: 'Our person comes to your doorstep and picks up your car.',
                    ),
                    _Step(
                      icon: Symbols.photo_camera,
                      text: 'We send you a photo of it getting inspected.',
                    ),
                    _Step(
                      icon: Symbols.verified,
                      text: 'We deliver your car back with the pollution certificate.',
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    "IT'S THAT SIMPLE",
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _PriceCard(
                    price: PollutionScreen._price,
                    onAvail: widget.onAvail ?? _bookNow,
                    onCall: _callSupport,
                  ),
                  const SizedBox(height: 18),
                  const _TrackingCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed hero image with the headline overlaid on a bottom gradient,
/// plus a floating back button — keeps the top of the screen feeling like
/// one image rather than an image-then-text stack.
class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.asset(
            PollutionScreen._heroAsset,
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.ink.withOpacity(0.55),
                  AppColors.ink,
                ],
                stops: const [0.35, 0.75, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            bottom: false,
            child: _BackButton(),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 22,
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.manrope(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: AppColors.txt,
              ),
              children: [
                const TextSpan(text: 'Get the pollution certificate\nto avoid a '),
                TextSpan(
                  text: '₹2000 fine',
                  style: TextStyle(color: AppColors.accent),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink.withOpacity(0.55),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.maybePop(context),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Symbols.arrow_back, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _Step {
  const _Step({required this.icon, required this.text});
  final IconData icon;
  final String text;
}

/// Numbered steps connected by a thin vertical line, so the sequence
/// reads as one continuous "handover" rather than three unrelated cards.
class _StepTimeline extends StatelessWidget {
  const _StepTimeline({required this.steps});
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            index: i + 1,
            step: steps[i],
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step, required this.isLast});
  final int index;
  final _Step step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 1.4),
                ),
                child: Text(
                  '$index',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.4,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: isLast ? 0 : 22),
              child: Row(
                children: [
                  Icon(step.icon, size: 18, color: AppColors.mut),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.text,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: AppColors.txt,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Elevated, isolated price + CTA — kept visually separate from the
/// explanatory content above so it reads as "the offer" rather than
/// just another line of text.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.price, required this.onAvail, required this.onCall});
  final String price;
  final VoidCallback onAvail;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Avail this convenience at just',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.mut,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            style: GoogleFonts.manrope(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.txt,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onAvail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.onAccentDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Book Now',
                      style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 50,
                height: 50,
                child: OutlinedButton(
                  onPressed: onCall,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: AppColors.accent, width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Icon(Symbols.call, color: AppColors.accent, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Safety/trust reassurance — deliberately styled softer than the price
/// card (outline instead of solid fill, icon-led) since its job is to
/// ease "handing my car to a stranger" anxiety, not to sell.
class _TrackingCard extends StatelessWidget {
  const _TrackingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Symbols.location_on, color: AppColors.accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'See where your vehicle is at all times',
                  style: GoogleFonts.manrope(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.txt,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Live tracking keeps you posted from pickup to drop-off, so your car is never out of sight.',
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mut,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
