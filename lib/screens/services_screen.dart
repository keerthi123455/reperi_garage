import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/bottom_nav_actions.dart';
import '../widgets/bottom_nav_bar.dart';
import 'book_service_screen.dart';
import 'car_spa_screen.dart';
import 'denting_tinkering_screen.dart';
import 'detailing_packages_screen.dart';
import 'fleet_management_screen.dart';
import 'insurance_claim_screen.dart';
import 'paint_care_package_screen.dart';
import 'paint_care_screen.dart';
import 'payment_screen.dart';
import 'profile_screen.dart';
import 'roadside_assistance_screen.dart';
import 'servicing_package_screen.dart';
import 'subscriptions_screen.dart';
import 'tyre_care_screen.dart';
import 'washing_package_screen.dart';
import 'wheel_management_package_screen.dart';

const String _expertPhone = '9353094672';

/// Builds the "More Details" / "Book Now" destination screen for a
/// [_Package], given the account's active vehicle (may be null).
typedef _ScreenBuilder = Widget Function(Map<String, dynamic>? vehicle);

/// One bookable line item in the unified catalog — every tier from every
/// package screen in the app (Servicing, Washing, Wheel Management, Paint
/// Care Package, Tyre Care, Book Service, Paint Care, Denting & Tinkering,
/// Car Spa, Detailing, Insurance, Subscriptions, Roadside Assistance),
/// flattened so it's all searchable and browsable from one screen.
class _Package {
  final String category;
  final String name;
  final String price;
  final String duration;
  final String tagline;
  final List<String> features;
  final bool popular;
  final bool comingSoon;
  final bool vehicleRequired;
  // Whether "Book Now" can jump straight to PaymentScreen with this
  // package's price — false for packages whose real cost depends on a
  // choice only their own screen can make (vehicle type, a quote after
  // inspection, a claim with no fixed price).
  final bool directBook;
  final _ScreenBuilder screenBuilder;

  const _Package({
    required this.category,
    required this.name,
    required this.price,
    required this.duration,
    required this.tagline,
    required this.features,
    required this.screenBuilder,
    this.popular = false,
    this.comingSoon = false,
    this.vehicleRequired = true,
    this.directBook = true,
  });
}

const Map<String, Color> _kCategoryAccent = {
  'Periodic Servicing': Color(0xFF4FA3E3),
  'Car Wash & Cleaning': Color(0xFF26C6DA),
  'Wheels & Tyres': Color(0xFFFF8A65),
  'Paint & Body': Color(0xFFBA68C8),
  'Premium Detailing': Color(0xFFD4A017),
  'Insurance': Color(0xFF66BB6A),
  'Subscriptions': Color(0xFFFFB74D),
  'Roadside Assistance': Color(0xFFEF5350),
  'Business Solutions': Color(0xFF90A4AE),
};

const Map<String, IconData> _kCategoryIcon = {
  'Periodic Servicing': Icons.build_rounded,
  'Car Wash & Cleaning': Icons.local_car_wash_rounded,
  'Wheels & Tyres': Icons.tire_repair_rounded,
  'Paint & Body': Icons.format_paint_rounded,
  'Premium Detailing': Icons.auto_awesome_rounded,
  'Insurance': Icons.verified_user_rounded,
  'Subscriptions': Icons.subscriptions_rounded,
  'Roadside Assistance': Icons.support_agent_rounded,
  'Business Solutions': Icons.business_rounded,
};

const List<String> _kCategoryOrder = [
  'Periodic Servicing',
  'Car Wash & Cleaning',
  'Wheels & Tyres',
  'Paint & Body',
  'Premium Detailing',
  'Insurance',
  'Subscriptions',
  'Roadside Assistance',
  'Business Solutions',
];

Widget _bookService(Map<String, dynamic>? v) => BookServiceScreen(vehicle: v!);
Widget _servicingPkg(Map<String, dynamic>? v) =>
    ServicingPackageScreen(vehicleId: v!['id'].toString());
Widget _washingPkg(Map<String, dynamic>? v) =>
    WashingPackageScreen(vehicleId: v!['id'].toString());
Widget _carSpa(Map<String, dynamic>? v) => CarSpaScreen(vehicle: v!);
Widget _wheelPkg(Map<String, dynamic>? v) =>
    WheelManagementPackageScreen(vehicleId: v!['id'].toString());
Widget _tyreCare(Map<String, dynamic>? v) => TyreCareScreen(vehicle: v!);
Widget _paintPkg(Map<String, dynamic>? v) =>
    PaintCarePackageScreen(vehicleId: v!['id'].toString());
Widget _paintCare(Map<String, dynamic>? v) => PaintCareScreen(vehicle: v!);
Widget _denting(Map<String, dynamic>? v) => DentingTinkeringScreen(vehicle: v!);
Widget _detailing(Map<String, dynamic>? v) => const DetailingPackagesScreen();
Widget _insurance(Map<String, dynamic>? v) => InsuranceClaimScreen(
      vehicleId: v!['id'].toString(),
      carModel: (v['car_model'] ?? '').toString(),
      carBrand: (v['car_brand'] ?? '').toString(),
      carNumber: (v['car_number'] ?? '').toString(),
    );
Widget _subscriptions(Map<String, dynamic>? v) =>
    SubscriptionsScreen(vehicleId: v!['id'].toString());
Widget _roadside(Map<String, dynamic>? v) => const RoadsideAssistanceScreen();
Widget _fleetMgmt(Map<String, dynamic>? v) => const FleetManagementScreen();

/// The full catalog — every tier from every package screen in the app.
final List<_Package> _kCatalog = [
  // ── Periodic Servicing ──────────────────────────────────────────────
  const _Package(
    category: 'Periodic Servicing',
    name: 'Quick Service',
    price: '₹1999',
    duration: '90 mins',
    tagline: 'A fast maintenance package for regular upkeep and smoother daily performance.',
    features: ['Engine oil replacement', 'Oil filter cleaning', 'Brake inspection', 'Fluid top-up', 'Battery check'],
    screenBuilder: _bookService,
  ),
  const _Package(
    category: 'Periodic Servicing',
    name: 'Full Service',
    price: '₹4999',
    duration: '4 hrs',
    tagline: 'Comprehensive servicing covering all major systems for peak performance.',
    features: ['Complete engine inspection', 'Full oil replacement', 'Air filter replacement', 'Wheel balancing', 'Suspension check', 'Brake servicing'],
    screenBuilder: _bookService,
  ),
  const _Package(
    category: 'Periodic Servicing',
    name: 'AC Service',
    price: '₹2499',
    duration: '2 hrs',
    tagline: 'Deep AC inspection and cooling optimization for maximum comfort.',
    features: ['AC gas refill', 'Cooling efficiency check', 'Cabin filter cleaning', 'Vent sanitization', 'Leak inspection'],
    screenBuilder: _bookService,
  ),
  const _Package(
    category: 'Periodic Servicing',
    name: 'Engine Diagnostics',
    price: '₹1499',
    duration: '45 mins',
    tagline: 'Advanced computer diagnostics to find hidden engine and electrical issues.',
    features: ['OBD scan', 'Engine health report', 'Sensor diagnostics', 'Error code detection', 'Performance analysis'],
    screenBuilder: _bookService,
  ),
  const _Package(
    category: 'Periodic Servicing',
    name: 'Essential',
    price: '₹999',
    duration: '3-4 hrs',
    tagline: 'Perfect for routine service.',
    features: ['Engine Oil Change', 'Oil Filter Change', 'Brake Inspection', 'AC Cooling Check', 'Battery Health Test', 'Tyre Inspection', 'Fluid Level Check', '21-Point Diagnostics', 'Digital Health Report'],
    screenBuilder: _servicingPkg,
  ),
  const _Package(
    category: 'Periodic Servicing',
    name: 'Premium Care',
    price: '₹3,999',
    duration: '3-4 hrs',
    tagline: 'Most Popular — everyday maintenance done right.',
    popular: true,
    features: ['Everything in Essential', 'Premium Engine Oil', 'Oil Filter Replacement', 'Brake Fluid Top-up', 'AC Performance Service', 'Air Filter Cleaning', 'Cabin Filter Cleaning', 'Steering Check', 'Suspension Check', 'Car Wash', 'Interior Vacuum', '35-Point Diagnostics'],
    screenBuilder: _servicingPkg,
  ),
  const _Package(
    category: 'Periodic Servicing',
    name: 'Signature Service',
    price: '₹5,999',
    duration: '3-4 hrs',
    tagline: 'Ultimate Protection.',
    features: ['Everything in Premium', 'Synthetic Engine Oil', 'Brake Fluid Replacement', 'Air Filter Replacement', 'Cabin Filter Replacement', 'Battery Load Test', 'Fuel System Check', 'Complete Brake Service', 'Wheel Alignment Check', 'Underbody Inspection', 'Deep Interior Cleaning', 'Foam Exterior Wash', '50+ Point Diagnostics', 'Photo Health Report', 'Priority Support'],
    screenBuilder: _servicingPkg,
  ),

  // ── Car Wash & Cleaning ──────────────────────────────────────────────
  const _Package(
    category: 'Car Wash & Cleaning',
    name: 'Express Wash',
    price: '₹299',
    duration: '1-2 hrs',
    tagline: 'A quick refresh for your car.',
    features: ['High-Pressure Exterior Wash', 'Premium Foam Wash', 'Microfiber Hand Drying', 'Tyre Cleaning', 'Alloy Wheel Cleaning', 'Exterior Glass Cleaning', 'Tyre Shine Dressing', 'Final Quality Inspection'],
    screenBuilder: _washingPkg,
  ),
  const _Package(
    category: 'Car Wash & Cleaning',
    name: 'Premium Wash',
    price: '₹599',
    duration: '1-2 hrs',
    tagline: 'Inside & out, clean and refreshed.',
    popular: true,
    features: ['Everything in Express Wash', 'Interior Vacuum Cleaning', 'Dashboard & Console Cleaning', 'Door Panel Wipe Down', 'Interior Glass Cleaning', 'Floor Mat Cleaning', 'Boot (Trunk) Vacuum', 'Air Freshener Application', 'Plastic Trim Dressing', 'Final Quality Inspection'],
    screenBuilder: _washingPkg,
  ),
  const _Package(
    category: 'Car Wash & Cleaning',
    name: 'Signature Detailing',
    price: '₹2,999',
    duration: '1-2 hrs',
    tagline: "Restore your car's showroom shine.",
    features: ['Everything in Premium Wash', 'Snow Foam Pre-Wash', 'Two-Bucket Safe Hand Wash', 'Bug & Tar Removal', 'Clay Bar Surface Decontamination', 'Machine Wax / Paint Sealant Application', 'Exterior Plastic Trim Restoration', 'Tyre & Alloy Deep Cleaning', 'Engine Bay Surface Cleaning', 'Interior Deep Vacuum', 'Leather/Fabric Seat Cleaning', 'Dashboard UV Protection', 'Door Jamb Cleaning', 'Interior Steam Sanitization (where applicable)', 'Premium Glass Treatment', 'Long-Lasting Air Freshener', 'Final Multi-Point Quality Inspection'],
    screenBuilder: _washingPkg,
  ),
  const _Package(
    category: 'Car Wash & Cleaning',
    name: 'Quick Refresh',
    price: '₹399',
    duration: '30 mins',
    tagline: 'Fast maintenance with essential exterior and basic interior cleaning.',
    features: ['Pressure Water Wash', 'pH Neutral Foam Wash', 'Exterior Hand Wash', 'Microfiber Drying', 'Tyre Cleaning', 'Tyre Polish', 'Wheel Rim Cleaning', 'Exterior Glass Cleaning', 'Dashboard Dusting', 'Interior Vacuum Cleaning', 'Door Jamb Cleaning', 'Final Quality Inspection'],
    screenBuilder: _carSpa,
  ),
  const _Package(
    category: 'Car Wash & Cleaning',
    name: 'Premium Spa',
    price: '₹999',
    duration: '90 mins',
    tagline: 'Everything in Quick Refresh, plus deep interior cleaning and protective treatments.',
    features: ['Pressure Water Wash', 'Premium Foam Wash', 'Exterior Hand Drying', 'Complete Interior Vacuum', 'Dashboard Detailing', 'Door Panel Cleaning', 'Seat Deep Cleaning', 'Floor Mat Cleaning', 'Interior Plastic Dressing', 'Interior Steam Cleaning', 'AC Vent Cleaning', 'Odour Removal Treatment', 'Interior UV Protection', 'Tyre Polish', 'Exterior Glass Cleaning', 'Final Quality Inspection'],
    screenBuilder: _carSpa,
  ),
  const _Package(
    category: 'Car Wash & Cleaning',
    name: 'Signature Spa+',
    price: '₹2499',
    duration: '150 mins',
    tagline: 'Complete restoration with paint treatment, engine bay detailing, and premium finishing.',
    features: ['Premium Foam Wash', 'Paint Decontamination', 'Clay Bar Treatment', 'Machine Wax Polish', 'Paint Gloss Enhancement', 'Exterior Plastic Restoration', 'Wheel Arch Cleaning', 'Alloy Wheel Detailing', 'Tyre Dressing', 'Complete Interior Vacuum', 'Dashboard Restoration', 'Leather / Fabric Seat Cleaning', 'Carpet Shampooing', 'Roof Lining Cleaning', 'Door Panel Restoration', 'Interior Steam Sanitization', 'AC Vent Sanitization', 'Engine Bay Cleaning', 'Exterior Glass Treatment', 'Premium Perfume Finish', 'Final Quality Inspection'],
    screenBuilder: _carSpa,
  ),

  // ── Wheels & Tyres ───────────────────────────────────────────────────
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Precision Alignment',
    price: '₹999',
    duration: '1-2 hrs',
    tagline: 'Better handling, smoother driving, and longer tyre life.',
    features: ['Computerized Wheel Alignment', 'Steering Alignment Check', 'Suspension Geometry Inspection', 'Tyre Pressure Adjustment', 'Front & Rear Tyre Wear Inspection', 'Steering Wheel Centering', 'Road Test After Alignment', 'Digital Alignment Report'],
    screenBuilder: _wheelPkg,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Complete Wheel Care',
    price: '₹1,999',
    duration: '1-2 hrs',
    tagline: 'Maximize tyre life and improve driving comfort.',
    popular: true,
    features: ['Everything in Precision Alignment', 'Computerized Wheel Balancing (All 4 Wheels)', 'Alloy Wheel Inspection', 'Tyre Rotation (if applicable)', 'Valve & Air Leak Check', 'Wheel Nut Torque Check', 'Suspension & Steering Linkage Inspection', 'Brake Disc Visual Inspection', 'Tyre Tread Depth Measurement', 'Tyre Health Report with Replacement Advice', 'Complimentary Tyre Shine'],
    screenBuilder: _wheelPkg,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Quick Air & Check',
    price: '₹299',
    duration: '20 mins',
    tagline: 'Perfect for routine tyre maintenance.',
    features: ['Tyre pressure check', 'Nitrogen refill', 'Air leakage inspection', 'Valve inspection', 'Tread inspection'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Wheel Alignment',
    price: '₹799',
    duration: '45 mins',
    tagline: 'Recommended if your vehicle pulls to one side.',
    features: ['Computerized alignment', 'Steering correction', 'Camber adjustment', 'Wheel angle optimization', 'Road stability testing'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Balancing & Rotation',
    price: '₹1499',
    duration: '60 mins',
    tagline: 'Improves ride quality and tyre longevity.',
    features: ['Dynamic balancing', 'Tyre rotation', 'Wheel weight calibration', 'Vibration reduction', 'High-speed balancing'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Road Grip Package',
    price: '₹2499',
    duration: '90 mins',
    tagline: 'Ideal for highway driving.',
    features: ['Alignment', 'Balancing', 'Rotation', 'Suspension inspection', 'Brake inspection', 'Grip optimization'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Performance Package',
    price: '₹3499',
    duration: '120 mins',
    tagline: 'Designed for enthusiasts.',
    features: ['Performance alignment', 'Precision balancing', 'Suspension tuning check', 'Cornering optimization', 'Road testing'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Premium Wheel Care',
    price: '₹4999',
    duration: '90 mins',
    tagline: 'Restores and protects premium alloy wheels.',
    features: ['Alloy detailing', 'Rim protection coating', 'Deep wheel cleaning', 'Brake dust removal', 'Finish restoration'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Alloy Wheel Studio',
    price: '₹5999',
    duration: '150 mins',
    tagline: 'For customers upgrading to premium alloys.',
    features: ['Alloy installation', 'Fitment inspection', 'Wheel balancing', 'Alignment', 'Styling consultation'],
    screenBuilder: _tyreCare,
  ),
  const _Package(
    category: 'Wheels & Tyres',
    name: 'Track Performance+',
    price: '₹6799',
    duration: '180 mins',
    tagline: 'Ultimate performance package for track-ready cars.',
    features: ['Premium wheel setup', 'High-speed balancing', 'Performance alignment', 'Suspension inspection', 'Brake inspection', 'Grip enhancement', 'Road testing', 'Premium detailing'],
    screenBuilder: _tyreCare,
  ),

  // ── Paint & Body ─────────────────────────────────────────────────────
  const _Package(
    category: 'Paint & Body',
    name: 'Paint Shine Package',
    price: '₹1,999',
    duration: '2-3 hrs',
    tagline: 'Restore gloss and protect your paint.',
    features: ['Premium Snow Foam Wash', 'Surface Decontamination Wash', 'Bug & Tar Removal', 'Paint Gloss Enhancement Polish', 'Machine Wax Application', 'Exterior Plastic Trim Dressing', 'Tyre Shine', 'Exterior Glass Cleaning', 'Paint Condition Inspection'],
    screenBuilder: _paintPkg,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Paint Protection Package',
    price: '₹2,999',
    duration: '2-3 hrs',
    tagline: 'Long-lasting shine with enhanced paint protection.',
    popular: true,
    features: ['Everything in Paint Shine Package', 'One-Step Machine Paint Correction', 'Ceramic Spray Coating', 'Hydrophobic Water-Repellent Protection', 'UV Protection for Paint', 'Minor Scratch & Swirl Reduction', 'Alloy Wheel Protection', 'Exterior Plastic Restoration', 'Rain-Repellent Glass Treatment', 'Final Paint Gloss Inspection'],
    screenBuilder: _paintPkg,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Ceramic Coating',
    price: '₹12,999',
    duration: 'Quoted on inspection',
    tagline: 'Premium add-on upgrade.',
    features: ['1-3 Year Paint Protection', 'Deep Gloss Finish', 'Hydrophobic Water Beading', 'UV Protection', 'Easier Cleaning', 'Chemical Resistance'],
    screenBuilder: _paintPkg,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Graphene Coating',
    price: '₹16,999',
    duration: 'Quoted on inspection',
    tagline: 'Premium add-on upgrade.',
    features: ['Enhanced Ceramic Protection', 'Better Heat Resistance', 'Superior Gloss', 'Water & Dirt Repellency', 'Increased Durability'],
    screenBuilder: _paintPkg,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Paint Protection Film (PPF)',
    price: '₹49,999',
    duration: 'Quoted on inspection',
    tagline: 'Premium add-on upgrade.',
    features: ['Self-Healing Film', 'Stone Chip Protection', 'Scratch Resistance', 'UV Protection', 'High Gloss or Matte Finish', 'Long-Term Paint Preservation'],
    screenBuilder: _paintPkg,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Paint Correction',
    price: '₹7,999',
    duration: 'Quoted on inspection',
    tagline: 'Premium add-on upgrade.',
    features: ['Multi-Stage Machine Polishing', 'Removes Swirl Marks', 'Removes Oxidation', 'Restores Paint Clarity', 'High Gloss Finish'],
    screenBuilder: _paintPkg,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Quick Polish',
    price: '₹599',
    duration: '45 mins',
    tagline: 'Perfect for restoring daily shine quickly.',
    features: ['Exterior wash', 'Quick buffing', 'Tyre shine', 'Water spot removal', 'Gloss enhancement'],
    screenBuilder: _paintCare,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Scratch Control',
    price: '₹1499',
    duration: '2 hrs',
    tagline: 'Removes minor scratches and swirl marks.',
    features: ['Scratch removal', 'Swirl correction', 'Paint enhancement', 'Machine buffing', 'Gloss restoration'],
    screenBuilder: _paintCare,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Rust Control',
    price: '₹2999',
    duration: '3 hrs',
    tagline: 'Advanced anti-rust treatment protecting your vehicle body.',
    features: ['Underbody coating', 'Rust treatment', 'Corrosion prevention', 'Protective sealant', 'Metal protection layer'],
    screenBuilder: _paintCare,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Premium Paint Restore',
    price: '₹4999',
    duration: '5 hrs',
    tagline: 'Restores dull, oxidized, faded paint to a premium glossy finish.',
    features: ['Paint correction', 'Multi-stage polishing', 'Deep gloss enhancement', 'Oxidation removal', 'Premium machine finish'],
    screenBuilder: _paintCare,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Vinyl & Wrap Studio',
    price: '₹7999',
    duration: '1 day',
    tagline: 'Premium wrapping for luxury styling and customization.',
    features: ['Vinyl wrap installation', 'Gloss/matte finish', 'Roof wrap', 'Mirror accents', 'Color customization', 'Paint-safe removal'],
    screenBuilder: _paintCare,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Showroom Shine+',
    price: '₹10999',
    duration: '2 days',
    tagline: 'Showroom-level shine, protection and exterior perfection.',
    features: ['Ceramic coating', 'Deep detailing', 'Paint refinement', 'Hydrophobic protection', 'Luxury polishing', 'Exterior rejuvenation', 'PPF enhancement'],
    screenBuilder: _paintCare,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Basic Inspection',
    price: '₹99',
    duration: '20 mins',
    tagline: 'Professional inspection and repair consultation for dents & damage.',
    features: ['Dent inspection', 'Paint damage check', 'Panel alignment check', 'Repair estimate', 'Insurance guidance'],
    screenBuilder: _denting,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Quick Dent Fix',
    price: '₹1499',
    duration: '2 hrs',
    tagline: 'Perfect for small dents and scratches from daily driving.',
    features: ['Minor dent removal', 'Scratch correction', 'Panel finishing', 'Basic touch-up', 'FREE inspection', 'FREE polish'],
    screenBuilder: _denting,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Panel Restore',
    price: '₹3999',
    duration: '5 hrs',
    tagline: 'Restores damaged doors, bumpers, and side panels.',
    features: ['Deep dent repair', 'Paint blending', 'Panel reshaping', 'Machine polishing', 'FREE inspection', 'FREE polish'],
    screenBuilder: _denting,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Body Line Correction',
    price: '₹4999',
    duration: '6 hrs',
    tagline: 'Restores factory body lines and alignment.',
    features: ['Multi-panel correction', 'Bumper alignment', 'Precision reshaping', 'Machine finishing', 'Paint refinement', 'FREE inspection', 'FREE polish'],
    screenBuilder: _denting,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Accident Restoration',
    price: '₹7999',
    duration: '1 day',
    tagline: 'Comprehensive accident repair for heavily damaged vehicles.',
    features: ['Structural correction', 'Deep restoration', 'Paint correction', 'Body alignment', 'Insurance assistance', 'FREE inspection', 'FREE polish'],
    screenBuilder: _denting,
  ),
  const _Package(
    category: 'Paint & Body',
    name: 'Signature Restoration+',
    price: '₹10999',
    duration: '2 days',
    tagline: 'Showroom-level restoration with luxury finishing.',
    features: ['Complete body rejuvenation', 'Luxury paint finishing', 'Advanced paint refinement', 'Ceramic finishing', 'Premium detailing', 'Insurance support', 'FREE inspection', 'FREE polish'],
    screenBuilder: _denting,
  ),

  // ── Premium Detailing (quote-based — no direct payment) ─────────────
  const _Package(
    category: 'Premium Detailing',
    name: 'PPF Premium',
    price: '₹55,000',
    duration: 'New car — 3 days',
    tagline: 'Ultimate protection against scratches, chips & UV.',
    features: ['400 sq ft base coverage', '₹400/sq ft', '3-5 Year Warranty', '3-Day turnaround for new cars'],
    screenBuilder: _detailing,
    vehicleRequired: false,
    directBook: false,
  ),
  const _Package(
    category: 'Premium Detailing',
    name: 'Garware Pro PPF',
    price: '₹75,000 - ₹1,00,000',
    duration: 'Used car — 5 days',
    tagline: 'Premium-grade film for maximum protection.',
    popular: true,
    features: ['Full Coverage', '8-Year Warranty', '5-Day turnaround (includes polish for used cars)'],
    screenBuilder: _detailing,
    vehicleRequired: false,
    directBook: false,
  ),
  const _Package(
    category: 'Premium Detailing',
    name: 'Ceramic Coating (Detailing Studio)',
    price: '₹16,000',
    duration: '2 days',
    tagline: 'Hydrophobic protection with stunning gloss.',
    features: ['Full Vehicle Coverage', '1-Year Warranty', 'Water beading effect', 'Enhanced glossiness', 'Easy maintenance'],
    screenBuilder: _detailing,
    vehicleRequired: false,
    directBook: false,
  ),
  const _Package(
    category: 'Premium Detailing',
    name: 'Graphene Coating (Detailing Studio)',
    price: '₹22,000',
    duration: '2 days',
    tagline: 'Next-gen protection with nano-technology.',
    features: ['Full Vehicle Coverage', '3-Year Warranty', 'Graphene nano-particles', 'Superior durability', 'Self-cleaning properties', 'UV protection included'],
    screenBuilder: _detailing,
    vehicleRequired: false,
    directBook: false,
  ),
  const _Package(
    category: 'Premium Detailing',
    name: 'Sun Film - Standard',
    price: '₹20,000 - ₹45,000',
    duration: '2 days',
    tagline: 'Beat the heat with premium UV blocking.',
    features: ['5-Year Warranty', 'Front only — ₹8,000', 'Sides only — ₹8,000', 'Front + Sides — ₹15,000', 'Full Coverage — ₹20,000+'],
    screenBuilder: _detailing,
    vehicleRequired: false,
    directBook: false,
  ),
  const _Package(
    category: 'Premium Detailing',
    name: 'Stek Brand Premium Film',
    price: '₹25,000',
    duration: '2 days',
    tagline: 'Top-tier heat rejection film, full body.',
    features: ['Full Body Coverage', '5-10 Year Warranty', 'Maximum heat & UV protection'],
    screenBuilder: _detailing,
    vehicleRequired: false,
    directBook: false,
  ),

  // ── Insurance ─────────────────────────────────────────────────────────
  const _Package(
    category: 'Insurance',
    name: 'Insurance Claim Assistance',
    price: 'Free Consultation',
    duration: 'As per claim',
    tagline: 'Cashless accident assistance — we handle the paperwork with your insurer.',
    features: ['Cashless claim assistance', 'Document pickup & digital submission', 'Approved garage network', 'End-to-end claim status tracking'],
    screenBuilder: _insurance,
    directBook: false,
  ),

  // ── Subscriptions ─────────────────────────────────────────────────────
  const _Package(
    category: 'Subscriptions',
    name: 'Car Wash Subscription',
    price: 'From ₹500/month',
    duration: '30-day plan',
    tagline: 'Daily doorstep car wash, billed monthly — price depends on your vehicle type.',
    features: ['Bike — ₹500/month', 'Hatchback / Small Cars — ₹600/month', 'SUV / XUV / Sedan — ₹1000/month', 'Luxury Cars — ₹1200/month', '6 Water Washes / Week', '2 Interior Washes / Week', 'Daily App Updates', 'Free Shampoo Wash on missed days', 'Flexible Timings (4 AM-9 AM, except Wednesdays)', 'No Contact Required'],
    screenBuilder: _subscriptions,
    directBook: false,
  ),

  // ── Roadside Assistance ────────────────────────────────────────────────
  const _Package(
    category: 'Roadside Assistance',
    name: 'Roadside Assistance',
    price: '₹399',
    duration: 'On-demand',
    tagline: '24/7 emergency help, wherever you are — extra charges may apply based on distance.',
    features: ['Flat Tyre change', 'Dead Battery jumpstart', 'Out-of-Fuel delivery', 'Towing assistance', 'Breakdown support', 'Accident support'],
    screenBuilder: _roadside,
    vehicleRequired: false,
  ),

  // ── Business Solutions ─────────────────────────────────────────────────
  const _Package(
    category: 'Business Solutions',
    name: 'Fleet Management',
    price: 'Custom Quote',
    duration: '',
    tagline: 'End-to-end fleet servicing for businesses with multiple vehicles.',
    features: ['Dedicated account manager', 'Priority scheduling', 'Consolidated billing', 'Multi-vehicle tracking'],
    screenBuilder: _fleetMgmt,
    vehicleRequired: false,
    directBook: false,
  ),
  const _Package(
    category: 'Business Solutions',
    name: 'Battery Management',
    price: '',
    duration: '',
    tagline: 'EV & conventional battery care.',
    features: [],
    screenBuilder: _fleetMgmt,
    vehicleRequired: false,
    directBook: false,
    comingSoon: true,
  ),
  const _Package(
    category: 'Business Solutions',
    name: 'Partner Garage Program',
    price: '',
    duration: '',
    tagline: 'Join our garage network.',
    features: [],
    screenBuilder: _fleetMgmt,
    vehicleRequired: false,
    directBook: false,
    comingSoon: true,
  ),
];

class ServicesScreen extends StatefulWidget {
  final Map<String, dynamic>? activeVehicle;

  /// When true, the search field grabs focus (and pops the keyboard open)
  /// as soon as this screen appears — used by the home screen's search
  /// icon, which should land the user ready to type immediately instead
  /// of just showing the catalog.
  final bool autoFocusSearch;

  const ServicesScreen({super.key, this.activeVehicle, this.autoFocusSearch = false});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  static const Color _gold = Color(0xFFD4A017);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    if (widget.autoFocusSearch) {
      // Requested after the first frame — the focus system isn't ready
      // to hand focus to a not-yet-laid-out field during initState itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<_Package> get _filtered {
    if (_searchQuery.isEmpty) return _kCatalog;
    return _kCatalog.where((pkg) {
      if (pkg.name.toLowerCase().contains(_searchQuery)) return true;
      if (pkg.category.toLowerCase().contains(_searchQuery)) return true;
      if (pkg.tagline.toLowerCase().contains(_searchQuery)) return true;
      return pkg.features.any((f) => f.toLowerCase().contains(_searchQuery));
    }).toList();
  }

  // ── Actions ──────────────────────────────────────────────────────────
  Future<void> _callUs() async {
    final uri = Uri(scheme: 'tel', path: _expertPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open dialer. Please call +91 93530 94672'),
          backgroundColor: AppColors.surfaceRaised,
        ),
      );
    }
  }

  void _openMoreDetails(_Package pkg) {
    if (pkg.comingSoon) {
      _comingSoon(pkg.name);
      return;
    }
    if (pkg.vehicleRequired && widget.activeVehicle == null) {
      _showNoVehicleDialog();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => pkg.screenBuilder(widget.activeVehicle)),
    );
  }

  void _bookNow(_Package pkg) {
    if (pkg.comingSoon) {
      _comingSoon(pkg.name);
      return;
    }
    if (pkg.vehicleRequired && widget.activeVehicle == null) {
      _showNoVehicleDialog();
      return;
    }
    if (!pkg.directBook) {
      // No fixed, immediately-payable price — send them to the real
      // screen instead (vehicle type picker, quote, or claim form).
      _openMoreDetails(pkg);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: pkg.name,
          price: pkg.price,
          duration: pkg.duration,
          vehicleId: widget.activeVehicle?['id']?.toString() ?? '',
        ),
      ),
    );
  }

  void _comingSoon(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name coming soon'),
        backgroundColor: AppColors.surfaceRaised,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showNoVehicleDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surfaceRaised,
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
              Text(
                'Please create a profile to book services',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.txt,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Add your vehicle details to continue with premium garage services.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.mut, height: 1.5),
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
                  child: Text(
                    'MAKE PROFILE',
                    style: TextStyle(
                      color: AppColors.onAccentDark,
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

  void _openPackageSheet(_Package pkg) {
    final accent = _kCategoryAccent[pkg.category] ?? _gold;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_kCategoryIcon[pkg.category] ?? Icons.star_rounded,
                        color: accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (pkg.popular)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('MOST POPULAR',
                                style: TextStyle(
                                    color: accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                          ),
                        Text(pkg.name,
                            style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(
                          pkg.duration.isEmpty ? pkg.price : '${pkg.price} • ${pkg.duration}',
                          style: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(pkg.tagline, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.5)),
              const SizedBox(height: 20),
              if (pkg.features.isNotEmpty) ...[
                Text("WHAT'S INCLUDED",
                    style: TextStyle(
                        color: AppColors.txt, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                ...pkg.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, color: accent, size: 17),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(f,
                                style: TextStyle(color: AppColors.txt.withOpacity(0.85), fontSize: 13, height: 1.4)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _openMoreDetails(pkg);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accent.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('MORE DETAILS',
                          style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _callUs,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.call_rounded, color: Color(0xFF25D366), size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: pkg.comingSoon
                      ? null
                      : () {
                          Navigator.pop(context);
                          _bookNow(pkg);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    pkg.comingSoon
                        ? 'COMING SOON'
                        : (pkg.directBook ? 'BOOK NOW' : 'VIEW OPTIONS'),
                    style: TextStyle(
                        color: AppColors.onAccentDark, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final Map<String, List<_Package>> grouped = {};
    for (final pkg in filtered) {
      grouped.putIfAbsent(pkg.category, () => <_Package>[]).add(pkg);
    }

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHero()),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildSearchBar(),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(child: _buildNoResults())
          else
            for (final category in _kCategoryOrder)
              if (grouped.containsKey(category)) ...[
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: _buildSectionHeader(category, _kCategoryIcon[category] ?? Icons.star_rounded,
                          _kCategoryAccent[category] ?? _gold),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        children: grouped[category]!.map((pkg) => _buildPackageCard(pkg)).toList(),
                      ),
                    ),
                  ),
                ),
              ],
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 3,
        onSelect: (i) => handleBottomNavSelect(
          context,
          i,
          currentIndex: 3,
          activeVehicle: widget.activeVehicle,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AskAiButton(
        onTap: () => openAiAdvisor(context, widget.activeVehicle),
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────
  Widget _buildHero() {
    return Stack(
      children: [
        SizedBox(
          height: 200,
          width: double.infinity,
          child: Image.asset(
            'assets/images/service_screen.jpg',
            fit: BoxFit.cover,
          ),
        ),
        Container(
          height: 200,
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
        Positioned(
          bottom: 20,
          left: 24,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _gold.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withOpacity(0.5)),
                ),
                child: const Text(
                  'ALL PACKAGES',
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
                'What does your car need today?',
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
          color: AppColors.surfaceRaised,
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
          focusNode: _searchFocusNode,
          style: TextStyle(color: AppColors.txt, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search any package or keyword…',
            hintStyle: TextStyle(color: AppColors.mut),
            prefixIcon: Icon(Icons.search_rounded,
                color: _gold.withOpacity(0.7), size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(Icons.close_rounded,
                        color: AppColors.mut, size: 20),
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
  Widget _buildSectionHeader(String title, IconData icon, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: AppColors.txt,
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
                  colors: [accent.withOpacity(0.35), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Package card ───────────────────────────────────────────
  Widget _buildPackageCard(_Package pkg) {
    final accent = _kCategoryAccent[pkg.category] ?? _gold;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GestureDetector(
        onTap: () => _openPackageSheet(pkg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(color: accent.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_kCategoryIcon[pkg.category] ?? Icons.star_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pkg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (pkg.comingSoon)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.chipBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('SOON',
                                style: TextStyle(
                                    color: AppColors.mut, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          )
                        else if (pkg.price.isNotEmpty)
                          Text(pkg.price,
                              style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pkg.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.mut, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: accent.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }

  // ── No-results state ──────────────────────────────────────
  Widget _buildNoResults() {
    final suggestions = _kCatalog.where((p) => p.popular).toList();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 52, color: AppColors.mut.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'No packages found for "$_searchQuery"',
              style: TextStyle(color: AppColors.mut, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Text(
              'Try out our:',
              style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: suggestions.map((pkg) {
                final accent = _kCategoryAccent[pkg.category] ?? _gold;
                return GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _openPackageSheet(pkg);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withOpacity(0.35)),
                    ),
                    child: Text(pkg.name,
                        style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
