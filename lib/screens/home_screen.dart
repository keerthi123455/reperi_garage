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
import '../services/ai_chat_session.dart';
import '../services/push_notification_service.dart';
import '../services/vehicle_change_bus.dart';
import '../services/vehicle_update_tracker.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../utils/premium_page_route.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_header.dart';
import '../widgets/ask_ai_button.dart';
import '../widgets/auto_banner_strip.dart';
import '../widgets/banner_coverflow.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/dot_indicator_row.dart';
import '../widgets/location_row.dart';
import '../widgets/notification_permission_dialog.dart';
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
import 'spares_screen.dart';
import 'two_wheeler_servicing_screen.dart';
import 'two_wheeler_washing_screen.dart';
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

  bool get _isActiveVehicleTwoWheeler => _activeVehicle?.isTwoWheeler ?? false;

  // Settled slide + continuous drag/settle position for the two-wheeler
  // coverflow (servicing/washing) — mirrors _selectedBanner/_coverflowPosition
  // above exactly, including driving its own "OUR PACKAGES" side heading.
  int _selectedTwoWheelerBanner = 0;
  late final ValueNotifier<double> _twoWheelerCoverflowPosition;

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
    _twoWheelerCoverflowPosition = ValueNotifier(_selectedTwoWheelerBanner.toDouble());
    _servicesOpen = widget.servicesExpandedByDefault;
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
    // Fired whenever a vehicle's details are edited from anywhere else in
    // the app (My Garage, the vehicle dashboard) — re-pulls the fleet so
    // this screen's carousel reflects the change immediately, without
    // needing to leave and come back.
    vehicleChangeBus.addListener(_loadVehicles);
    _loadVehicles();
    _loadProfile();
    _loadServiceAddress();
    _maybeShowNotificationPrimer();
  }

  /// Shows the notification "soft ask" on Home, not at cold launch, so
  /// the user has context (booking updates, not marketing) before either
  /// this or the native OS prompt shows up. See
  /// push_notification_service_mobile.dart's init() for the other half
  /// of this — it no longer requests the permission itself.
  ///
  /// Gated on whether the OS has ACTUALLY granted permission yet — not a
  /// one-time "have we shown it" flag. Gating on "shown" meant tapping
  /// "Not Now" even once (or the dialog just not registering a tap in
  /// time) permanently stopped OneSignal from ever being asked again for
  /// the life of the install, silently killing every push notification
  /// from then on with no way to retry short of reinstalling. Checking
  /// real permission status means it keeps politely re-asking each time
  /// Home loads until the user actually grants it — and stops
  /// immediately once they do, since hasPermission() then returns true.
  Future<void> _maybeShowNotificationPrimer() async {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (PushNotificationService.hasPermission()) return;
      showNotificationPermissionPrimer(context);
    });
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
      premiumPageRoute((_) => const AddressManagementScreen()),
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
          hasUpdate: await VehicleUpdateTracker.hasUpdate(id),
          vehicleType: (row['vehicle_type'] as String?) ?? 'four_wheeler',
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

  // _bookService/_bookWashing/_openCoverflowPackage/_openServiceBanner used
  // to block with a "Add a vehicle first" snackbar whenever there was no
  // active vehicle. That's exactly the browsing these package screens are
  // meant to allow without a vehicle yet (they only need a real one at the
  // final "Book Now" step, which now prompts for one via PaymentScreen) —
  // so they navigate regardless, falling back to an empty vehicle id/map
  // when there isn't one yet.

  void _bookService() {
    final vehicle = _activeVehicle;
    Navigator.push(
      context,
      premiumPageRoute((_) => ServicingPackageScreen(vehicleId: vehicle?.id ?? '')),
    ).then((_) {
      if (vehicle != null) _refreshVehicleBookingStatus(vehicle.id);
    });
  }

  void _bookWashing() {
    final vehicle = _activeVehicle;
    Navigator.push(
      context,
      premiumPageRoute((_) => WashingPackageScreen(vehicleId: vehicle?.id ?? '')),
    ).then((_) {
      if (vehicle != null) _refreshVehicleBookingStatus(vehicle.id);
    });
  }

  /// Maps a coverflow slide's image filename to the package screen it
  /// opens. Tapping a slide that isn't already centered just brings it to
  /// center (see `BannerCoverflow.onSelect`) — this only fires for a
  /// second, deliberate tap on the slide that's already selected.
  void _openCoverflowPackage(String assetPath) {
    final vehicle = _activeVehicle;
    final vehicleId = vehicle?.id ?? '';

    final WidgetBuilder? builder = switch (assetPath) {
      'assets/images/service.jpg' => (_) => ServicingPackageScreen(vehicleId: vehicleId),
      'assets/images/washing.jpg' => (_) => WashingPackageScreen(vehicleId: vehicleId),
      'assets/images/wheelmanagement.jpg' =>
        (_) => WheelManagementPackageScreen(vehicleId: vehicleId),
      'assets/images/paintcare.jpg' => (_) => PaintCarePackageScreen(vehicleId: vehicleId),
      'assets/images/ac.jpg' => (_) => AcPackageScreen(vehicleId: vehicleId),
      _ => null,
    };
    if (builder == null) return;

    Navigator.push(context, premiumPageRoute(builder)).then((_) {
      if (vehicle != null) _refreshVehicleBookingStatus(vehicle.id);
    });
  }

  /// Same idea as [_openCoverflowPackage], for the two-slide two-wheeler
  /// coverflow — both slides now get their own bike-specific pricing/
  /// checklist screens instead of reusing the four-wheeler package screens.
  void _openTwoWheelerCoverflowPackage(String assetPath) {
    final vehicle = _activeVehicle;
    final vehicleId = vehicle?.id ?? '';

    final WidgetBuilder? builder = switch (assetPath) {
      'assets/images/servicing_twowheeler.jpeg' =>
        (_) => TwoWheelerServicingScreen(vehicleId: vehicleId),
      'assets/images/washing_twowheeler.jpeg' =>
        (_) => TwoWheelerWashingScreen(vehicleId: vehicleId),
      _ => null,
    };
    if (builder == null) return;

    Navigator.push(context, premiumPageRoute(builder)).then((_) {
      if (vehicle != null) _refreshVehicleBookingStatus(vehicle.id);
    });
  }

  /// Maps a "2D" service banner's image filename to the screen it opens.
  void _openServiceBanner(String assetPath) {
    // Neither of these is tied to a specific vehicle.
    if (assetPath == 'assets/images/detailing.jpeg') {
      Navigator.push(
        context,
        premiumPageRoute((_) => const DetailingPackagesScreen()),
      );
      return;
    }
    if (assetPath == 'assets/images/spares.jpeg') {
      Navigator.push(
        context,
        premiumPageRoute((_) => const SparesScreen()),
      );
      return;
    }

    final vehicle = _activeVehicle;
    final vehicleMap = {'id': vehicle?.id ?? ''};

    final WidgetBuilder? builder = switch (assetPath) {
      'assets/images/tyres.jpeg' => (_) => TyreCareScreen(vehicle: vehicleMap),
      'assets/images/servicing.jpeg' => (_) => BookServiceScreen(vehicle: vehicleMap),
      'assets/images/painting.jpeg' => (_) => PaintCareScreen(vehicle: vehicleMap),
      'assets/images/dent.jpeg' => (_) => DentingTinkeringScreen(vehicle: vehicleMap),
      'assets/images/carspa.jpeg' => (_) => CarSpaScreen(vehicle: vehicleMap),
      'assets/images/insurance.jpeg' => (_) => InsuranceClaimScreen(
          vehicleId: vehicle?.id ?? '',
          carModel: vehicle?.model ?? '',
          carBrand: vehicle?.brand ?? '',
          carNumber: vehicle?.carNumber ?? '',
        ),
      _ => null,
    };
    if (builder == null) return;

    Navigator.push(context, premiumPageRoute(builder)).then((_) {
      if (vehicle != null) _refreshVehicleBookingStatus(vehicle.id);
    });
  }

  void _openVehicleBookings(Vehicle vehicle) {
    Navigator.push(
      context,
      premiumPageRoute(
        (_) => VehicleBookingsScreen(
          vehicleId: vehicle.id,
          carModel: vehicle.model,
          carBrand: vehicle.brand,
          carNumber: vehicle.carNumber,
        ),
      ),
      // That screen marks every update source seen as soon as it loads —
      // reload so this vehicle's notification bell clears instead of
      // staying lit until some unrelated refresh happens to notice.
    ).then((_) => _loadVehicles());
  }

  void _openMyVehicles() {
    Navigator.push(context, premiumPageRoute((_) => const ProfileScreen()))
        .then((_) => _loadVehicles());
  }

  /// Bound to the "+" tile at the end of the vehicle carousel — same
  /// destination as [_openMyVehicles], but lands straight in the
  /// add-vehicle sheet instead of just the profile screen.
  void _openAddVehicle() {
    Navigator.push(
      context,
      premiumPageRoute((_) => const ProfileScreen(autoOpenAddVehicle: true)),
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
    Navigator.push(context, premiumPageRoute((_) => const RoadsideAssistanceScreen()));
  }

  void _openSubscriptions() {
    // Browsing subscription plans doesn't need a vehicle — only actually
    // subscribing does, which SubscriptionsScreen's own booking step
    // gates via PaymentScreen.
    Navigator.push(
      context,
      premiumPageRoute((_) => SubscriptionsScreen(vehicleId: _activeVehicle?.id ?? '')),
    );
  }

  void _openAiAdvisor() {
    // The advisor gives advice and shows package recommendations from
    // plain chat, independent of any vehicle — it only needs one at the
    // point someone taps a recommended package to book it, which
    // AiAdvisorSheet's own "add a vehicle" prompt already covers.
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
      premiumPageRoute(
        (_) => ServicesScreen(activeVehicle: _activeVehicleMap),
      ),
    );
  }

  /// Bound to the header's search icon — lands directly on the Services
  /// screen with the search field already focused, instead of just
  /// showing the catalog like [_openServices].
  void _openServicesSearch() {
    Navigator.push(
      context,
      premiumPageRoute(
        (_) => ServicesScreen(
          activeVehicle: _activeVehicleMap,
          autoFocusSearch: true,
        ),
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
        premiumPageRoute(
          (_) => FleetDashboardScreen(
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
    // Same "browse the offer, gate only the actual booking" pattern as
    // the rest of these — PollutionScreen only touches vehicleId at its
    // own PaymentScreen construction.
    //
    // Trialing premiumPageRoute here (fade + rise + scale, both directions)
    // in place of the flat default MaterialPageRoute slide — see
    // lib/utils/premium_page_route.dart.
    Navigator.push(
      context,
      premiumPageRoute((_) => PollutionScreen(vehicleId: _activeVehicle?.id ?? '')),
    );
  }

  void _openInspectionScreen() {
    Navigator.push(
      context,
      premiumPageRoute((_) => InspectionScreen(vehicleId: _activeVehicle?.id ?? '')),
    );
  }

  void _openFleetManagement() {
    Navigator.push(
      context,
      premiumPageRoute((_) => const FleetManagementScreen()),
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
    AiChatSession.clear();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showBatteryEnquirySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BatteryEnquirySheet(),
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
    vehicleChangeBus.removeListener(_loadVehicles);
    _toastTimer?.cancel();
    _coverflowPosition.dispose();
    _twoWheelerCoverflowPosition.dispose();
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
                  onSearch: _openServicesSearch,
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
                        else
                          // VehicleCarousel already renders a "+ Add
                          // Vehicle" tile after the last vehicle card, and
                          // handles an empty vehicle list on its own
                          // (itemCount = vehicles.length + 1, so with zero
                          // vehicles it's just that one tile) — showing a
                          // plain "No vehicles added yet." text instead,
                          // as this used to, meant a new user never even
                          // saw the button to add their first one.
                          VehicleCarousel(
                            vehicles: _vehicles,
                            onTap: _openVehicleBookings,
                            onPhotoTap: _showVehiclePhotoSourceSheet,
                            onAddVehicle: _openAddVehicle,
                            onPageChanged: (page) => setState(() => _activeVehicleIndex = page),
                          ),
                        const SizedBox(height: 6),
                        // Book Service/Book Washing don't apply to a
                        // two-wheeler — its own servicing/washing packages
                        // are booked straight from the coverflow below.
                        if (!_isActiveVehicleTwoWheeler)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: QuickActionRow(
                              onBookService: _bookService,
                              onBookWashing: _bookWashing,
                            ),
                          ),
                        if (_isActiveVehicleTwoWheeler) ...[
                          const SizedBox(height: 22),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: ValueListenableBuilder<double>(
                              valueListenable: _twoWheelerCoverflowPosition,
                              builder: (context, position, coverflow) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    PackagesSideHeading(
                                      opacity: (1 - position.abs()).clamp(0.0, 1.0),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: coverflow!),
                                  ],
                                );
                              },
                              child: BannerCoverflow(
                                imagePaths: kTwoWheelerCoverflowBanners,
                                selectedIndex: _selectedTwoWheelerBanner,
                                onSelect: (i) =>
                                    setState(() => _selectedTwoWheelerBanner = i),
                                onPositionChanged: (p) =>
                                    _twoWheelerCoverflowPosition.value = p,
                                onTapSelected: (i) => _openTwoWheelerCoverflowPackage(
                                    kTwoWheelerCoverflowBanners[i]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ValueListenableBuilder<double>(
                            valueListenable: _twoWheelerCoverflowPosition,
                            builder: (context, position, _) => DotIndicatorRow(
                              count: kTwoWheelerCoverflowBanners.length,
                              activeIndex: position
                                  .round()
                                  .clamp(0, kTwoWheelerCoverflowBanners.length - 1)
                                  .toInt(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ] else ...[
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
                          // Every one of these leads to a browse-tiers
                          // screen that only needs a real vehicle at its
                          // own "Book Now" (which now prompts for one via
                          // PaymentScreen if it's missing) — so tapping a
                          // service tile always opens it, vehicle or not,
                          // falling back to an empty id/map when there
                          // isn't one yet. Detailing and Roadside Help
                          // never needed a vehicle in the first place.
                          onServiceTap: (service) {
                            final vehicle = _activeVehicle;
                            final vehicleMap = {'id': vehicle?.id ?? ''};

                            if (service == 'Periodic Service') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => BookServiceScreen(vehicle: vehicleMap),
                                ),
                              );
                            } else if (service == 'Deep Cleaning') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => CarSpaScreen(vehicle: vehicleMap),
                                ),
                              );
                            } else if (service == 'AC Service') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => AcPackageScreen(vehicleId: vehicle?.id ?? ''),
                                ),
                              );
                            } else if (service == 'Tyres & Wheels') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => TyreCareScreen(vehicle: vehicleMap),
                                ),
                              );
                            } else if (service == 'Denting') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => DentingTinkeringScreen(vehicle: vehicleMap),
                                ),
                              );
                            } else if (service == 'Painting') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => PaintCareScreen(vehicle: vehicleMap),
                                ),
                              );
                            } else if (service == 'Insurance Claim') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => InsuranceClaimScreen(
                                    vehicleId: vehicle?.id ?? '',
                                    carModel: vehicle?.model ?? '',
                                    carBrand: vehicle?.brand ?? '',
                                    carNumber: vehicle?.carNumber ?? '',
                                  ),
                                ),
                              );
                            } else if (service == 'Ceramic Coating') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => const DetailingPackagesScreen(),
                                ),
                              );
                            } else if (service == 'Roadside Help') {
                              Navigator.push(
                                context,
                                premiumPageRoute(
                                  (_) => const RoadsideAssistanceScreen(),
                                ),
                              );
                            } else if (service == 'Pre-buy Inspection') {
                              _openInspectionScreen();
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
                                premiumPageRoute(
                                  (_) => const DetailingPackagesScreen(),
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
                        ],
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
                                onTap: _showBatteryEnquirySheet,
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

/// The "Battery Management" enquiry popup — reached from the "More from
/// Reperi" banner strip. Just two fields since this is a lead-capture form
/// (a human follows up), not a full booking — the actual work order/quote
/// happens outside the app once the garage reaches out.
class _BatteryEnquirySheet extends StatefulWidget {
  const _BatteryEnquirySheet();

  @override
  State<_BatteryEnquirySheet> createState() => _BatteryEnquirySheetState();
}

class _BatteryEnquirySheetState extends State<_BatteryEnquirySheet> {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _requirementController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _companyController.dispose();
    _requirementController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      await Supabase.instance.client.from('battery_enquiries').insert({
        'user_id': userId,
        'company': _companyController.text.trim(),
        'requirement': _requirementController.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enquiry submitted — our team will reach out shortly.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit: $e')),
      );
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppColors.mut, fontSize: 14),
      hintStyle: TextStyle(color: AppColors.mut.withOpacity(0.7), fontSize: 14),
      filled: true,
      fillColor: AppColors.ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD4A017), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: AppColors.line,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A017).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.battery_charging_full_rounded,
                            color: Color(0xFFD4A017), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Battery Management Enquiry',
                          style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tell us a bit about your requirement and our team will reach out.',
                    style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _companyController,
                    style: TextStyle(color: AppColors.txt, fontSize: 16),
                    decoration: _fieldDecoration('Company'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your company name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _requirementController,
                    style: TextStyle(color: AppColors.txt, fontSize: 16),
                    decoration: _fieldDecoration(
                      'Requirement',
                      hint: 'e.g. EV fleet battery servicing, 20 units',
                    ),
                    maxLines: 3,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your requirement' : null,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A017),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text(
                              'SUBMIT ENQUIRY',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
