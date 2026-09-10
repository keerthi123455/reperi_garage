import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/banner.dart';
import '../models/vehicle.dart';
import '../services/address_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_header.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/auto_banner_strip.dart';
import '../widgets/banner_coverflow.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/dot_indicator_row.dart';
import '../widgets/location_row.dart';
import '../widgets/packages_side_heading.dart';
import '../widgets/promo_banner.dart';
import '../widgets/quick_action_row.dart';
import '../widgets/service_banner_row.dart';
import '../widgets/services_grid.dart';
import '../widgets/toast_banner.dart';
import '../widgets/two_up_banner_row.dart';
import '../widgets/vehicle_carousel.dart';
import 'ac_package_screen.dart';
import 'address_management_screen.dart';
import 'ai_advisor_sheet.dart';
import 'book_service_screen.dart';
import 'car_spa_screen.dart';
import 'denting_tinkering_screen.dart';
import 'detailing_packages_screen.dart';
import 'fleet_dashboard_screen.dart';
import 'fleet_login_sheet.dart';
import 'fleet_management_screen.dart';
import 'inspection_screen.dart';
import 'insurance_claim_screen.dart';
import 'login_screen.dart';
import 'paint_care_package_screen.dart';
import 'paint_care_screen.dart';
import 'pollution_screen.dart';
import 'profile_screen.dart';
import 'roadside_assistance_screen.dart';
import 'services_screen.dart';
import 'servicing_package_screen.dart';
import 'subscriptions_screen.dart';
import 'tyre_care_screen.dart';
import 'vehicle_bookings_screen.dart';
import 'washing_package_screen.dart';
import 'wheel_management_package_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.servicesExpandedByDefault = false,
  });

  /// Mirrors the prototype's `servicesExpanded` design-time prop.
  final bool servicesExpandedByDefault;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedBanner = 0;
  // A ValueNotifier (not plain state + setState) — the coverflow reports its
  // continuous drag/settle position every frame, and routing that through
  // setState would rebuild the entire screen (grid, banners, everything) on
  // every drag pixel. A scoped ValueListenableBuilder below keeps that churn
  // limited to just the side heading's opacity and the dot indicator.
  late final ValueNotifier<double> _coverflowPosition;
  bool _servicesOpen = false;
  String? _toastMessage;
  Timer? _toastTimer;

  List<Vehicle> _vehicles = [];
  bool _vehiclesLoading = true;
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _profileName;
  // The account's currently-default service address, from the
  // AddressManagementScreen — shown in the LocationRow next to "Change".
  // Null while loading or if the account has no saved address yet.
  String? _serviceAddress;
  final AddressService _addressService = AddressService();
  // Which vehicle tile is currently centered/in view in the carousel — that
  // one is "the active vehicle" for anything booked from elsewhere on this
  // screen (Book Service, Book Washing, the coverflow/2D banners, the
  // drawer, ...), not whichever one happens to be first.
  int _activeVehicleIndex = 0;

  Vehicle? get _activeVehicle {
    if (_vehicles.isEmpty) return null;
    return _vehicles[_activeVehicleIndex.clamp(0, _vehicles.length - 1)];
  }

  /// The active vehicle as the plain map shape ServicesScreen, the bottom
  /// nav bar's peer screens, and AiAdvisorSheet all expect.
  Map<String, dynamic>? get _activeVehicleMap {
    final vehicle = _activeVehicle;
    if (vehicle == null) return null;
    return {
      'id': vehicle.id,
      'car_brand': vehicle.brand,
      'car_model': vehicle.model,
      'car_number': vehicle.carNumber,
      'photo_url': vehicle.photoUrl,
    };
  }

  @override
  void initState() {
    super.initState();
    // Looked up by filename rather than a hardcoded index, so this keeps
    // pointing at the right slide even if kCoverflowBanners gets reordered.
    final defaultBanner = kCoverflowBanners.indexOf(kDefaultCoverflowBanner);
    if (defaultBanner >= 0) _selectedBanner = defaultBanner;
    _coverflowPosition = ValueNotifier(_selectedBanner.toDouble());
    _servicesOpen = widget.servicesExpandedByDefault;
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
    _loadVehicles();
    _loadProfile();
    _loadServiceAddress();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  /// Loads the account's default saved address for the LocationRow. Falls
  /// back to a friendly placeholder when the account has none yet.
  Future<void> _loadServiceAddress() async {
    final addr = await _addressService.getDefaultAddress();
    if (!mounted) return;
    setState(() {
      _serviceAddress = addr?['address'] as String?;
    });
  }

  Future<void> _openAddressManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressManagementScreen()),
    );
    if (!mounted) return;
    _loadServiceAddress();
  }

  /// Loads the account's `profiles` row for the drawer's display name.
  /// Independent of [_loadVehicles] — a failure here just leaves the
  /// drawer showing a generic name.
  Future<void> _loadProfile() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
      if (!mounted) return;
      setState(() {
        _profileName = profile?['name'] as String?;
      });
    } catch (_) {
      // Leave the name unset — the drawer falls back to a generic one.
    }
  }

  /// Loads every vehicle on this account plus each one's latest booking
  /// status, so the vehicle tiles reflect the real fleet size instead of a
  /// fixed demo list.
  Future<void> _loadVehicles() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _vehiclesLoading = false);
      return;
    }

    try {
      final vehicleRows = List<Map<String, dynamic>>.from(
        await supabase
            .from('vehicles')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: true),
      );

      final vehicles = await Future.wait(vehicleRows.map((row) async {
        final id = row['id'].toString();
        return Vehicle(
          id: id,
          brand: (row['car_brand'] ?? '').toString(),
          model: (row['car_model'] ?? '').toString(),
          carNumber: (row['car_number'] ?? '').toString(),
          photoUrl: row['photo_url'] as String?,
          bookingStatus: await _fetchLatestBookingStatus(id),
          hasActiveSubscription: await _fetchHasActiveSubscription(id),
        );
      }));

      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _activeVehicleIndex = 0;
        _vehiclesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _vehiclesLoading = false);
    }
  }

  /// Also used to re-check a vehicle's status after returning from a
  /// booking flow (see [_bookService]/[_bookWashing]) — returns `null` both
  /// when there's no booking yet and when the lookup itself fails, so a
  /// tile never gets stuck showing a stale "in progress" status.
  Future<String?> _fetchLatestBookingStatus(String vehicleId) async {
    try {
      final bookingRows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('bookings')
            .select()
            .eq('vehicle_id', vehicleId)
            .order('created_at', ascending: false)
            .limit(1),
      );
      if (bookingRows.isEmpty) return null;
      return bookingRows.first['booking_status'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Whether this specific vehicle — not any vehicle on the account — has
  /// an active subscription, for that vehicle's own "ACTIVE SUB" badge.
  Future<bool> _fetchHasActiveSubscription(String vehicleId) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('subscriptions')
            .select('id')
            .eq('vehicle_id', vehicleId)
            .eq('status', 'active')
            .limit(1),
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshVehicleBookingStatus(String vehicleId) async {
    final status = await _fetchLatestBookingStatus(vehicleId);
    if (!mounted) return;
    setState(() {
      _vehicles = [
        for (final v in _vehicles) v.id == vehicleId ? v.copyWithBookingStatus(status) : v,
      ];
    });
  }

  void _bookService() {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ServicingPackageScreen(vehicleId: vehicle.id)),
    ).then((_) => _refreshVehicleBookingStatus(vehicle.id));
  }

  void _bookWashing() {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WashingPackageScreen(vehicleId: vehicle.id)),
    ).then((_) => _refreshVehicleBookingStatus(vehicle.id));
  }

  /// Maps a coverflow slide's image filename to the package screen it
  /// opens. Tapping a slide that isn't already centered just brings it to
  /// center (see `BannerCoverflow.onSelect`) — this only fires for a
  /// second, deliberate tap on the slide that's already selected.
  void _openCoverflowPackage(String assetPath) {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }

    final WidgetBuilder? builder = switch (assetPath) {
      'assets/images/service.jpg' => (_) => ServicingPackageScreen(vehicleId: vehicle.id),
      'assets/images/washing.jpg' => (_) => WashingPackageScreen(vehicleId: vehicle.id),
      'assets/images/wheelmanagement.jpg' =>
        (_) => WheelManagementPackageScreen(vehicleId: vehicle.id),
      'assets/images/paintcare.jpg' => (_) => PaintCarePackageScreen(vehicleId: vehicle.id),
      'assets/images/ac.jpg' => (_) => AcPackageScreen(vehicleId: vehicle.id),
      _ => null,
    };
    if (builder == null) return;

    Navigator.push(context, MaterialPageRoute(builder: builder))
        .then((_) => _refreshVehicleBookingStatus(vehicle.id));
  }

  /// Maps a "2D" service banner's image filename to the screen it opens.
  void _openServiceBanner(String assetPath) {
    if (assetPath == 'assets/images/spares.jpeg') {
      _flash('Will be available soon');
      return;
    }

    // The only one of these that isn't tied to a specific vehicle.
    if (assetPath == 'assets/images/detailing.jpeg') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DetailingPackagesScreen()),
      );
      return;
    }

    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }

    final WidgetBuilder? builder = switch (assetPath) {
      'assets/images/tyres.jpeg' => (_) => TyreCareScreen(vehicle: {'id': vehicle.id}),
      'assets/images/servicing.jpeg' => (_) => BookServiceScreen(vehicle: {'id': vehicle.id}),
      'assets/images/painting.jpeg' => (_) => PaintCareScreen(vehicle: {'id': vehicle.id}),
      'assets/images/dent.jpeg' => (_) => DentingTinkeringScreen(vehicle: {'id': vehicle.id}),
      'assets/images/carspa.jpeg' => (_) => CarSpaScreen(vehicle: {'id': vehicle.id}),
      'assets/images/insurance.jpeg' => (_) => InsuranceClaimScreen(
          vehicleId: vehicle.id,
          carModel: vehicle.model,
          carBrand: vehicle.brand,
          carNumber: vehicle.carNumber,
        ),
      _ => null,
    };
    if (builder == null) return;

    Navigator.push(context, MaterialPageRoute(builder: builder))
        .then((_) => _refreshVehicleBookingStatus(vehicle.id));
  }

  void _openVehicleBookings(Vehicle vehicle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleBookingsScreen(
          vehicleId: vehicle.id,
          carModel: vehicle.model,
          carBrand: vehicle.brand,
          carNumber: vehicle.carNumber,
        ),
      ),
    );
  }

  void _openMyVehicles() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
        .then((_) => _loadVehicles());
  }

  /// Bound to the "+" tile at the end of the vehicle carousel — same
  /// destination as [_openMyVehicles], but lands straight in the
  /// add-vehicle sheet instead of just the profile screen.
  void _openAddVehicle() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen(autoOpenAddVehicle: true)),
    ).then((_) => _loadVehicles());
  }

  void _openMyBookingsFromDrawer() {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }
    _openVehicleBookings(vehicle);
  }

  void _openRoadsideAssistance() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RoadsideAssistanceScreen()));
  }

  void _openSubscriptions() {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SubscriptionsScreen(vehicleId: vehicle.id)),
    );
  }

  void _openAiAdvisor() {
    if (_activeVehicleMap == null) {
      _flash('Add a vehicle first');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AiAdvisorSheet(vehicle: _activeVehicleMap),
    );
  }

  void _openServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServicesScreen(activeVehicle: _activeVehicleMap),
      ),
    );
  }

  Future<void> _openFleetLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('fleet_logged_in') ?? false;
    if (!mounted) return;

    if (loggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FleetDashboardScreen(
            fleetUser: {
              'id': prefs.getString('fleet_user_id'),
              'company_name': prefs.getString('fleet_company'),
            },
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => const FleetLoginSheet(),
      );
    }
  }

  void _openPollutionScreen() {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PollutionScreen(vehicleId: vehicle.id)),
    );
  }

  void _openInspectionScreen() {
    final vehicle = _activeVehicle;
    if (vehicle == null) {
      _flash('Add a vehicle first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InspectionScreen(vehicleId: vehicle.id)),
    );
  }

  void _openFleetManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FleetManagementScreen()),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      _flash('Could not open link');
    }
  }

  Future<void> _callSupport() async {
    try {
      await launchUrl(Uri.parse('tel:9353094672'));
    } catch (_) {
      if (!mounted) return;
      _flash('Could not start call');
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fleet_logged_in');
    await prefs.remove('fleet_user_id');
    await prefs.remove('fleet_company');
    await prefs.remove('fleet_username');
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _showVehiclePhotoSourceSheet(Vehicle vehicle) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Vehicle Photo',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 6),
              ListTile(
                leading: Icon(Symbols.photo_camera, color: AppColors.accent),
                title: Text(
                  'Take Photo',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: AppColors.txt),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Symbols.photo_library, color: AppColors.accent),
                title: Text(
                  'Choose from Album',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: AppColors.txt),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (source == null) return;
    await _pickAndUploadVehiclePhoto(vehicle, source);
  }

  Future<void> _pickAndUploadVehiclePhoto(Vehicle vehicle, ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1000,
      imageQuality: 80,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      final fileName = '${vehicle.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final supabase = Supabase.instance.client;

      await supabase.storage.from('vehicle-photos').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final photoUrl = supabase.storage.from('vehicle-photos').getPublicUrl(fileName);

      await supabase.from('vehicles').update({'photo_url': photoUrl}).eq('id', vehicle.id);

      if (!mounted) return;
      setState(() {
        _vehicles = [
          for (final v in _vehicles) v.id == vehicle.id ? v.copyWith(photoUrl: photoUrl) : v,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      _flash('Could not upload photo. Please try again.');
    }
  }

  void _flash(String message) {
    setState(() => _toastMessage = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _toastTimer?.cancel();
    _coverflowPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.ink,
      drawer: AppDrawer(
        profileName: _profileName,
        activeVehicle: _activeVehicle,
        onMyVehicles: _openMyVehicles,
        onMyBookings: _openMyBookingsFromDrawer,
        onRoadsideAssistance: _openRoadsideAssistance,
        onAiAdvisor: _openAiAdvisor,
        onFleetLogin: _openFleetLogin,
        onServicePartners: () => _openExternalUrl('https://reperi.in/service-partners.html'),
        onBePartner: () => _openExternalUrl('https://trustkon.com/vendorform.html'),
        onPrivacyPolicy: () => _openExternalUrl('https://reperi.in/privacy-policy.html'),
        onTermsAndConditions: () => _openExternalUrl('https://reperi.in/terms.html'),
        onContactUs: _callSupport,
        onLogout: _logout,
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                AppHeader(
                  onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onBell: () => _flash('No new notifications'),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 130),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LocationRow(
                          address: _serviceAddress ?? 'Add your service address',
                          onChange: _openAddressManagement,
                        ),
                        if (_vehiclesLoading)
                          const SizedBox(
                            height: 158,
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          )
                        else if (_vehicles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              'No vehicles added yet.',
                              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.mut),
                            ),
                          )
                        else
                          VehicleCarousel(
                            vehicles: _vehicles,
                            onTap: _openVehicleBookings,
                            onPhotoTap: _showVehiclePhotoSourceSheet,
                            onAddVehicle: _openAddVehicle,
                            onPageChanged: (page) => setState(() => _activeVehicleIndex = page),
                          ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: QuickActionRow(
                            onBookService: _bookService,
                            onBookWashing: _bookWashing,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _coverflowPosition,
                            builder: (context, position, coverflow) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  PackagesSideHeading(
                                    // Fully visible only at the first banner
                                    // (index 0), fading out as soon as the
                                    // coverflow moves away from it.
                                    opacity: (1 - position.abs()).clamp(0.0, 1.0),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: coverflow!),
                                ],
                              );
                            },
                            // Passed as `child` rather than built inline, so
                            // the coverflow itself (with all its own image
                            // decoding/painting) isn't rebuilt every time
                            // `position` changes — only the heading is.
                            child: BannerCoverflow(
                              imagePaths: kCoverflowBanners,
                              selectedIndex: _selectedBanner,
                              onSelect: (i) => setState(() => _selectedBanner = i),
                              onPositionChanged: (p) => _coverflowPosition.value = p,
                              onTapSelected: (i) =>
                                  _openCoverflowPackage(kCoverflowBanners[i]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ValueListenableBuilder<double>(
                          valueListenable: _coverflowPosition,
                          builder: (context, position, _) => DotIndicatorRow(
                            count: kCoverflowBanners.length,
                            activeIndex: position
                                .round()
                                .clamp(0, kCoverflowBanners.length - 1)
                                .toInt(),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                          child: Text(
                            'What does your car need today?',
                            style: GoogleFonts.manrope(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        ServiceBannerRow(
                          imagePaths: kServiceBanners,
                          onTap: (i) => _openServiceBanner(kServiceBanners[i]),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Keep your car showroom-new everyday :',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 1269x301 native size — a wide, short banner.
                          child: PromoBanner(
                            assetPath: kSubscriptionBanner,
                            aspectRatio: 1269 / 301,
                            onTap: _openSubscriptions,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Compliance and Safety checks :',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: TwoUpBannerRow(
                            // Native size is 853x1280 (portrait).
                            aspectRatio: 853 / 1280,
                            left: TwoUpBannerItem(
                              assetPath: kPollutionBanner,
                              onTap: () => _openPollutionScreen(),
                            ),
                            right: TwoUpBannerItem(
                              assetPath: kInspectionBanner,
                              onTap: () => _openInspectionScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Our Services',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        ServicesGrid(
                          expanded: _servicesOpen,
                          onServiceTap: (service) {
                            if (service == 'Periodic Service') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookServiceScreen(
                                    vehicle: {'id': vehicle.id},
                                  ),
                                ),
                              );
                            } else if (service == 'Deep Cleaning') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CarSpaScreen(
                                    vehicle: {'id': vehicle.id},
                                  ),
                                ),
                              );
                            } else if (service == 'AC Service') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AcPackageScreen(
                                    vehicleId: vehicle.id,
                                  ),
                                ),
                              );
                            } else if (service == 'Tyres & Wheels') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TyreCareScreen(
                                    vehicle: {'id': vehicle.id},
                                  ),
                                ),
                              );
                            } else if (service == 'Denting') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DentingTinkeringScreen(
                                    vehicle: {'id': vehicle.id},
                                  ),
                                ),
                              );
                            } else if (service == 'Painting') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaintCareScreen(
                                    vehicle: {'id': vehicle.id},
                                  ),
                                ),
                              );
                            } else if (service == 'Insurance Claim') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => InsuranceClaimScreen(
                                    vehicleId: vehicle.id,
                                    carModel: vehicle.model,
                                    carBrand: vehicle.brand,
                                    carNumber: vehicle.carNumber,
                                  ),
                                ),
                              );
                            } else if (service == 'Ceramic Coating') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DetailingPackagesScreen(),
                                ),
                              );
                            } else if (service == 'Roadside Help') {
                              final vehicle = _activeVehicle;

                              if (vehicle == null) {
                                _flash('Add a vehicle first');
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RoadsideAssistanceScreen(),
                                ),
                              );
                            } else {
                              _flash('Slot picker opens here');
                            }
                          },
                          onToggle: () =>
                              setState(() => _servicesOpen = !_servicesOpen),
                        ),
                        const SizedBox(height: 6),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Get your paint protected :',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 1280x426 native size.
                          child: PromoBanner(
                            assetPath: kPpfBanner,
                            aspectRatio: 1280 / 426,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DetailingPackagesScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'Stranded somewhere ?',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          // 1280x511 native size.
                          child: PromoBanner(
                            assetPath: kEmergencyBanner,
                            aspectRatio: 1280 / 511,
                            onTap: _openRoadsideAssistance,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Not `const` — its build() reads AppColors
                        // directly, so it must rebuild on a theme toggle.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text(
                            'More from Reperi :',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: AutoBannerStrip(
                            items: [
                              AutoBannerItem(
                                assetPath: kBatteryBanner,
                                onTap: () => _flash('Coming soon'),
                              ),
                              AutoBannerItem(
                                assetPath: kFleetBanner,
                                onTap: _openFleetManagement,
                              ),
                              AutoBannerItem(
                                assetPath: kPartnerBanner,
                                onTap: () => _openExternalUrl('https://trustkon.com/vendorform'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNavBar(
                // Home is always index 0 while this screen is visible —
                // navigating to another tab pushes a new screen (which
                // shows this same bar with its own currentIndex), rather
                // than swapping content in place here.
                currentIndex: 0,
                onSelect: (i) {
                  switch (i) {
                    case 1:
                      _openMyBookingsFromDrawer();
                      break;
                    case 3:
                      _openServices();
                      break;
                    case 4:
                      _openMyVehicles();
                      break;
                  }
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 44 + bottomInset,
              child: Center(
                child: AskAiButton(onTap: _openAiAdvisor),
              ),
            ),
            if (_toastMessage != null)
              Positioned(
                left: 18,
                right: 18,
                bottom: 104 + bottomInset,
                child: ToastBanner(message: _toastMessage!),
              ),
          ],
        ),
      ),
    );
  }
}
