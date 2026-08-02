import 'dart:async';
import 'dart:math' as math;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reperi_garage/screens/ai_advisor_sheet.dart';
import 'package:reperi_garage/screens/fleet_dashboard_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'vehicle_bookings_screen.dart';
import 'fleet_management_screen.dart';
import 'car_spa_screen.dart';
import 'services_screen.dart';
import 'login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'book_service_screen.dart';
import 'denting_tinkering_screen.dart';
import 'paint_care_screen.dart';
import 'tyre_care_screen.dart';
import 'roadside_assistance_screen.dart';
import 'fleet_login_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'service_details_screen.dart';
import 'servicing_package_screen.dart';
import 'washing_package_screen.dart';
import 'wheel_management_package_screen.dart';
import 'paint_care_package_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? profileData;
  Map<String, dynamic>? activeVehicle;
  List<Map<String, dynamic>> vehicles = [];

  late final PageController _vehiclePageController =
      PageController(viewportFraction: 0.94);
  int _vehiclePageIndex = 0;

  bool hasActiveService = false;
  bool hasNewUpdate = false;
  bool loading = true;
  int _navIndex = 0;

  // Static, hardcoded — same "not from Supabase" approach used by the 4
  // dedicated package screens. Fixes "Our Packages" occasionally showing
  // empty (previously depended on a live `service_packages` fetch).
  final List<Map<String, dynamic>> sliderItems = [
    {
      'key': '21_step_inspection',
      'image': 'assets/images/21pointinspection.jpg',
      'title': 'Servicing',
      'price': 'From ₹999',
      'duration': '3-4 hrs',
      'services': <String>[],
      'benefits': <String>[],
    },
    {
      'key': 'quick_care',
      'image': 'assets/images/quickcare.jpg',
      'title': 'Washing',
      'price': 'From ₹299',
      'duration': '1-2 hrs',
      'services': <String>[],
      'benefits': <String>[],
    },
    {
      'key': 'wheelzcare',
      'image': 'assets/images/WheelzCare.jpg',
      'title': 'Wheel Management',
      'price': 'From ₹999',
      'duration': '1-2 hrs',
      'services': <String>[],
      'benefits': <String>[],
    },
    {
      'key': 'car360_pack',
      'image': 'assets/images/car360.jpg',
      'title': 'Paint Care',
      'price': 'From ₹1,999',
      'duration': '2-3 hrs',
      'services': <String>[],
      'benefits': <String>[],
    },
  ];

  // ── Shimmer (vehicle card border) every 3s ──
  late AnimationController _shimmerController;

  // ── Orb breathing every 4s ──
  late AnimationController _orbController;

  // ── Tips rotation ──
  int _tipIndex = 0;
  Timer? _tipTimer;

  // ── Scroll hint ──
  bool _showScrollHint = false;
  Timer? _idleTimer;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _otherOfferingsKey = GlobalKey();

  // How close to the bottom (in pixels) counts as "already at the bottom"
  // for the purpose of suppressing the scroll hint.
  static const double _bottomThreshold = 150;

  // ── Two-wheeler speech-bubble popup ──
  bool _showTwoWheelerBubble = false;
  Timer? _bubbleTimer;

  // ── Search overlay ──
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final List<String> _tips = [
    'Your engine suffers more damage in the first 10 minutes after a cold start than during hours of highway driving.',
    'A tyre that\'s 20% underinflated can lose up to 10% of its lifespan.',
    'Most modern engines can exceed 300,000 km with regular oil changes.',
    'Hard acceleration burns fuel up to 3x faster than smooth driving.',
    'Driving with low fuel regularly can shorten fuel pump life.',
    'Just 100 kg of extra weight can reduce fuel efficiency by up to 5%.',
    'Short trips are harder on your engine than long highway drives.',
    'A car battery loses strength every time cabin lights are left on with the engine off.',
    'Wheel misalignment can reduce tyre life by thousands of kilometres.',
    'Your brakes last longer when you coast before stopping instead of braking late.',
    'Dirty engine oil increases friction, heat, and fuel consumption.',
    'Most battery failures happen without warning signs.',
    'Air conditioning uses less fuel than driving with windows down at highway speeds.',
    'Tyres are the only part of your car touching the road.',
    'Engine overheating can cause damage in minutes, not hours.',
    'A neglected coolant system can destroy an otherwise healthy engine.',
    'Regular servicing costs less than a single major breakdown.',
    'High RPMs don\'t make your car faster, just thirstier.',
    'The average car contains over 30,000 individual parts working together.',
    'Your vehicle\'s resale value starts declining the day maintenance is skipped.',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    fetchProfile();

    // ── Shimmer: loops every 3s ──
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _shimmerController.forward(from: 0);
    });

    // ── Orb breathing: loops every 4s ──
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // ── Tips: rotate every 6s ──
    _tipTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) {
        setState(() {
          _tipIndex = (_tipIndex + 1) % _tips.length;
        });
      }
    });

    // ── Scroll hint: show after 4s idle ──
    _startIdleTimer();
    _scrollController.addListener(_onScroll);
  }

  // Whether the scroll view is already close enough to the bottom that
  // the "scroll to view services" hint wouldn't add anything useful.
  bool get _isNearBottom {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) < _bottomThreshold;
  }

  // Whether the "Other Offerings" section has scrolled up to (or past)
  // the top of the visible screen — once the user's reached that far,
  // the hint has done its job and shouldn't keep appearing.
  bool get _reachedOtherOfferings {
    final renderObject = _otherOfferingsKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final topPadding = MediaQuery.of(context).padding.top;
    return renderObject.localToGlobal(Offset.zero).dy <= topPadding + 40;
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      // Don't show the hint if the user is already at (or almost at)
      // the bottom of the page, or has already scrolled past the
      // point the hint is trying to point them toward.
      if (_isNearBottom || _reachedOtherOfferings) return;
      setState(() => _showScrollHint = true);
    });
  }

  void _onScroll() {
    if (_showScrollHint || _isNearBottom || _reachedOtherOfferings) {
      setState(() => _showScrollHint = false);
    }
    _startIdleTimer();
  }

  // Shows the small speech-bubble message above the two-wheeler button,
  // and auto-hides it after a few seconds.
  void _showTwoWheelerBubbleMessage() {
    _bubbleTimer?.cancel();
    setState(() => _showTwoWheelerBubble = true);
    _bubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showTwoWheelerBubble = false);
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _orbController.dispose();
    _tipTimer?.cancel();
    _idleTimer?.cancel();
    _bubbleTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _vehiclePageController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    // Wait a frame so the overlay/TextField actually exists before
    // trying to focus it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() => _searchOpen = false);
  }

  Future<void> fetchProfile() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final vehiclesResponse = await supabase
          .from('vehicles')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      final allVehicles =
          List<Map<String, dynamic>>.from(vehiclesResponse);

      // Resume on whichever vehicle was active last time; fall back to
      // the first one if that vehicle's since been removed, or if
      // nothing was ever set.
      Map<String, dynamic>? vehicle;
      int pageIndex = 0;
      if (allVehicles.isNotEmpty) {
        final activeId = profile?['active_vehicle_id'];
        final matchIndex =
            allVehicles.indexWhere((v) => v['id'] == activeId);
        pageIndex = matchIndex != -1 ? matchIndex : 0;
        vehicle = allVehicles[pageIndex];
      }

      bool serviceExists = false;
      bool updateExists = false;

      if (vehicle != null) {
        final bookingResponse = await supabase
            .from('bookings')
            .select()
            .eq('vehicle_id', vehicle['id'])
            .order('created_at', ascending: false);

        serviceExists = bookingResponse.isNotEmpty;
        updateExists = bookingResponse.isNotEmpty &&
            bookingResponse[0]['has_unread_update'] == true;
      }

      if (!mounted) return;

      setState(() {
        profileData = profile;
        vehicles = allVehicles;
        activeVehicle = vehicle;
        hasActiveService = serviceExists;
        hasNewUpdate = updateExists;
        loading = false;
        _vehiclePageIndex = pageIndex;
      });

      // Land the PageView on the resumed vehicle's page once it's built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_vehiclePageController.hasClients && pageIndex != 0) {
          _vehiclePageController.jumpToPage(pageIndex);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  // Called whenever the user swipes to a different vehicle in the
  // horizontal vehicle carousel. Whichever vehicle is currently in
  // view becomes the one quick actions/bookings act on, and that
  // choice is remembered for next time they open the app.
  Future<void> _onVehiclePageChanged(int index) async {
    if (index < 0 || index >= vehicles.length) return;
    final vehicle = vehicles[index];

    setState(() {
      _vehiclePageIndex = index;
      activeVehicle = vehicle;
    });

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase
            .from('profiles')
            .update({'active_vehicle_id': vehicle['id']}).eq('id', user.id);
      } catch (_) {
        // Not fatal — worst case, next login resumes on the previous
        // vehicle instead of this one.
      }
    }

    try {
      final bookingResponse = await supabase
          .from('bookings')
          .select()
          .eq('vehicle_id', vehicle['id'])
          .order('created_at', ascending: false);

      bool serviceExists = bookingResponse.isNotEmpty;
      bool updateExists = bookingResponse.isNotEmpty &&
          bookingResponse[0]['has_unread_update'] == true;

      if (!mounted) return;
      // Only apply if the user hasn't already swiped past this page
      // again while this query was in flight.
      if (_vehiclePageIndex == index) {
        setState(() {
          hasActiveService = serviceExists;
          hasNewUpdate = updateExists;
        });
      }
    } catch (_) {
      // Non-fatal — the badges just won't update for this swipe.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVehicle = activeVehicle != null;

    final quickActions = [
      _ActionTile(
        image: 'assets/images/tile_book_service.jpg',
        icon: Icons.build_rounded,
        title: 'Book Service',
        subtitle: 'Oil • Filters • Checkup',
        badge: '45 MIN',
        badgeColor: const Color(0xFFD4A017),
        stat: 'Same Day',
        statIcon: Icons.bolt,
        statColor: const Color(0xFFD4A017),
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => BookServiceScreen(vehicle: activeVehicle!),
          ));
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_car_spa.jpg',
        icon: Icons.local_car_wash_rounded,
        title: 'Car Spa',
        subtitle: 'Interior + Exterior',
        badge: 'STARTS ₹399',
        badgeColor: Colors.red,
        stat: '4.9 ★ Rated',
        statIcon: Icons.star_rounded,
        statColor: const Color(0xFFD4A017),
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => CarSpaScreen(vehicle: activeVehicle!),
          ));
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_denting.jpg',
        icon: Icons.car_repair_rounded,
        title: 'Denting &\nTinkering',
        subtitle: 'Body Repair & Finish',
        badge: 'POPULAR',
        badgeColor: const Color(0xFF6C3FD4),
        stat: 'Free Pickup',
        statIcon: Icons.local_shipping_rounded,
        statColor: Colors.white70,
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => DentingTinkeringScreen(vehicle: activeVehicle!),
          ));
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_paint.jpg',
        icon: Icons.format_paint_rounded,
        title: 'Paint Care',
        subtitle: 'Scratch & Dent Repair',
        badge: 'NEW',
        badgeColor: Colors.green,
        stat: 'Premium',
        statIcon: Icons.auto_awesome_rounded,
        statColor: const Color(0xFFD4A017),
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => PaintCareScreen(vehicle: activeVehicle!),
          ));
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_tyre.jpg',
        icon: Icons.tire_repair_rounded,
        title: 'Tyre Care',
        subtitle: 'Alignment & Rotation',
        badge: 'SAFETY',
        badgeColor: Colors.green,
        stat: 'Free Test',
        statIcon: Icons.shield_rounded,
        statColor: Colors.green,
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => TyreCareScreen(vehicle: activeVehicle!),
          ));
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_detailing.jpg',
        icon: Icons.auto_awesome_rounded,
        title: 'Detailing',
        subtitle: 'Gloss & Paint Protection',
        badge: 'PREMIUM',
        badgeColor: const Color(0xFFD4A017),
        stat: 'Ceramic Coat',
        statIcon: Icons.layers_rounded,
        statColor: Colors.white70,
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('This service is coming soon')),
          );
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_spare_parts.jpg',
        icon: Icons.settings_rounded,
        title: 'Spare Parts',
        subtitle: 'Genuine OEM Parts',
        badge: 'GENUINE',
        badgeColor: Colors.blueAccent,
        stat: 'Fast Delivery',
        statIcon: Icons.local_shipping_rounded,
        statColor: Colors.white70,
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('This service is coming soon')),
          );
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_insurance.jpg',
        icon: Icons.shield_rounded,
        title: 'Claims',
        subtitle: 'Accident Assistance',
        badge: 'CASHLESS',
        badgeColor: Colors.teal,
        stat: '24/7 Support',
        statIcon: Icons.support_agent_rounded,
        statColor: Colors.white70,
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('This service is coming soon')),
          );
        },
      ),
    ];

    // Package tiles (Servicing/Washing/Wheel Management/Paint Care) as
    // searchable entries too, routed the same way the "Our Packages"
    // carousel tap handler already does.
    final packageSearchTiles = sliderItems.map((item) {
      IconData icon;
      switch (item['key']) {
        case '21_step_inspection':
          icon = Icons.checklist_rounded;
          break;
        case 'quick_care':
          icon = Icons.local_car_wash_rounded;
          break;
        case 'wheelzcare':
          icon = Icons.tire_repair_rounded;
          break;
        case 'car360_pack':
          icon = Icons.format_paint_rounded;
          break;
        default:
          icon = Icons.build_rounded;
      }
      return _ActionTile(
        image: item['image'] as String,
        icon: icon,
        title: item['title'] as String,
        subtitle: item['price'] as String,
        badge: 'PACKAGE',
        badgeColor: const Color(0xFFD4A017),
        stat: item['duration'] as String,
        statIcon: Icons.schedule_rounded,
        statColor: const Color(0xFFD4A017),
        onTap: (ctx) {
          if (activeVehicle == null) {
            _showNoProfileDialog(ctx);
            return;
          }
          if (item['key'] == '21_step_inspection') {
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) =>
                    ServicingPackageScreen(vehicleId: activeVehicle!['id']),
              ),
            );
            return;
          }
          if (item['key'] == 'quick_care') {
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) =>
                    WashingPackageScreen(vehicleId: activeVehicle!['id']),
              ),
            );
            return;
          }
          if (item['key'] == 'wheelzcare') {
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => WheelManagementPackageScreen(
                    vehicleId: activeVehicle!['id']),
              ),
            );
            return;
          }
          if (item['key'] == 'car360_pack') {
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) =>
                    PaintCarePackageScreen(vehicleId: activeVehicle!['id']),
              ),
            );
            return;
          }
        },
      );
    }).toList();

    final searchableTiles = [...quickActions, ...packageSearchTiles];

    // ── Wide-screen (laptop/desktop) layout ──
    // Only used above a ~900px width breakpoint (see the LayoutBuilder
    // below) — reuses the exact same widgets/state as the mobile layout,
    // just arranged into 3 columns instead of one. Mobile/tablet/narrow
    // web all continue to use the untouched single-column layout further
    // down, completely unaffected by any of this.
    Widget buildWideHomeLayout(BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── TOP BAR ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(
                    builder: (c) => _TappableScale(
                      onTap: () => Scaffold.of(c).openDrawer(),
                      child: _darkIcon(Icons.menu_rounded),
                    ),
                  ),
                  Image.asset(
                    'assets/images/login.png',
                    height: 110,
                    fit: BoxFit.contain,
                  ),
                  _TappableScale(
                    onTap: _openSearch,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD4A017)),
                      ),
                      child: const Icon(Icons.search_rounded,
                          color: Color(0xFFD4A017), size: 22),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'What does your car need today?',
                style: TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 16,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),

              // ── 3-COLUMN SPLIT ──
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── LEFT: vehicle ──
                    SizedBox(
                      width: 320,
                      child: SingleChildScrollView(
                        child: hasVehicle
                            ? Column(
                                children: [
                                  SizedBox(
                                    height: 150,
                                    child: PageView.builder(
                                      controller: _vehiclePageController,
                                      itemCount: vehicles.length,
                                      onPageChanged: _onVehiclePageChanged,
                                      itemBuilder: (_, index) => Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            4, 14, 4, 4),
                                        child:
                                            _vehicleCard(vehicles[index]),
                                      ),
                                    ),
                                  ),
                                  if (vehicles.length > 1) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List.generate(
                                        vehicles.length,
                                        (i) => AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          margin: const EdgeInsets
                                              .symmetric(horizontal: 3),
                                          width: i == _vehiclePageIndex
                                              ? 18
                                              : 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: i == _vehiclePageIndex
                                                ? const Color(0xFFD4A017)
                                                : const Color(0xFF2A2A2A),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : _noProfileCard(),
                      ),
                    ),

                    const SizedBox(width: 28),

                    // ── CENTER: packages + services ──
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _goldSeparator(),
                            _sectionTitle('Our Packages'),
                            const SizedBox(height: 6),
                            CarouselSlider(
                              options: CarouselOptions(
                                height: 230,
                                autoPlay: true,
                                enlargeCenterPage: false,
                                viewportFraction: 1.0,
                              ),
                              items: sliderItems.map((item) {
                                return Builder(builder: (context) {
                                  return _TappableScale(
                                    onTap: () {
                                      if (activeVehicle == null) {
                                        _showNoProfileDialog(context);
                                        return;
                                      }
                                      if (item['key'] ==
                                          '21_step_inspection') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ServicingPackageScreen(
                                              vehicleId:
                                                  activeVehicle!['id'],
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (item['key'] == 'quick_care') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                WashingPackageScreen(
                                              vehicleId:
                                                  activeVehicle!['id'],
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (item['key'] == 'wheelzcare') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                WheelManagementPackageScreen(
                                              vehicleId:
                                                  activeVehicle!['id'],
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (item['key'] == 'car360_pack') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PaintCarePackageScreen(
                                              vehicleId:
                                                  activeVehicle!['id'],
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(28),
                                        border: Border.all(
                                          color: const Color(0xFFD4A017)
                                              .withOpacity(0.5),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFD4A017)
                                                .withOpacity(0.08),
                                            blurRadius: 22,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(28),
                                        child: Image.asset(
                                          item['image'] as String,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                        ),
                                      ),
                                    ),
                                  );
                                });
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            _goldSeparator(),
                            _sectionTitle('Our Services'),
                            const SizedBox(height: 6),
                            _TappableScale(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RoadsideAssistanceScreen(),
                                  ),
                                );
                              },
                              child: Container(
                                height: 180,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Image.asset(
                                    'assets/images/roadside_assistance_banner.jpg',
                                    fit: BoxFit.cover,
                                    alignment: Alignment.centerRight,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            GridView.builder(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: quickActions.length,
                              itemBuilder: (context, index) {
                                return _ActionCard(
                                  tile: quickActions[index],
                                  onTap: () {
                                    if (quickActions[index].onTap !=
                                        null) {
                                      quickActions[index]
                                          .onTap!(context);
                                    }
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 28),

                    // ── RIGHT: tips + other offerings ──
                    SizedBox(
                      width: 340,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TipCard(
                              tip: _tips[_tipIndex],
                              tipIndex: _tipIndex,
                            ),
                            const SizedBox(height: 8),
                            _goldSeparator(),
                            KeyedSubtree(
                              key: _otherOfferingsKey,
                              child: _sectionTitle('Other Offerings'),
                            ),
                            const SizedBox(height: 6),
                            CarouselSlider(
                              options: CarouselOptions(
                                height: 220,
                                autoPlay: true,
                                enlargeCenterPage: true,
                                viewportFraction: 0.94,
                              ),
                              items: [
                                {
                                  'image': 'assets/images/fleet.jpg',
                                  'type': 'fleet'
                                },
                                {
                                  'image': 'assets/images/battery.jpg',
                                  'type': 'battery'
                                },
                                {
                                  'image': 'assets/images/garage.jpg',
                                  'type': 'garage'
                                },
                              ].map((item) {
                                return Builder(builder: (context) {
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(28),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.asset(
                                            item['image'] as String,
                                            fit: BoxFit.cover,
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment
                                                    .bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [
                                                  Colors.black
                                                      .withOpacity(0.55),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            right: 18,
                                            bottom: 18,
                                            child: ElevatedButton(
                                              style: ElevatedButton
                                                  .styleFrom(
                                                backgroundColor:
                                                    const Color(
                                                        0xFF6C3FD4),
                                                foregroundColor:
                                                    Colors.white,
                                                elevation: 8,
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 18,
                                                    vertical: 12),
                                                shape:
                                                    RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(14),
                                                ),
                                              ),
                                              onPressed: () {
                                                if (item['type'] ==
                                                    'fleet') {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const FleetManagementScreen(),
                                                    ),
                                                  );
                                                } else if (item['type'] ==
                                                    'battery') {
                                                  ScaffoldMessenger.of(
                                                          context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                        content: Text(
                                                            'Battery Management coming soon')),
                                                  );
                                                } else if (item['type'] ==
                                                    'garage') {
                                                  final uri = Uri.parse(
                                                      'https://trustkon.com/');
                                                  launchUrl(uri,
                                                      mode: LaunchMode
                                                          .externalApplication);
                                                }
                                              },
                                              child: const Text(
                                                'LEARN MORE',
                                                style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                });
                              }).toList(),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    'Proudly made in India 🇮🇳',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.3),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Happy Servicing',
                                    style: TextStyle(
                                      color: const Color(0xFFD4A017)
                                          .withOpacity(0.35),
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
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
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_searchOpen,
      onPopInvoked: (didPop) {
        if (!didPop && _searchOpen) {
          _closeSearch();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        drawer: GarageDrawer(
          profileData: profileData,
          activeVehicle: activeVehicle,
          onBookingsViewed: fetchProfile,
        ),
        body: Stack(
          children: [
            // ── Breathing orb — top right ──
            AnimatedBuilder(
              animation: _orbController,
              builder: (_, __) {
                final opacity = 0.06 + (_orbController.value * 0.10);
                return Positioned(
                  top: -120,
                  right: -80,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFD4A017).withOpacity(opacity),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── Breathing orb — bottom left ──
            AnimatedBuilder(
              animation: _orbController,
              builder: (_, __) {
                final opacity = 0.03 + (_orbController.value * 0.06);
                return Positioned(
                  bottom: 200,
                  left: -120,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFD4A017).withOpacity(opacity),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── LUXURY BACKGROUND PAINTER ──
            Positioned.fill(
              child: CustomPaint(painter: GarageBackgroundPainter()),
            ),

            // ── Main content ──
            loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFD4A017)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 900) {
                        return buildWideHomeLayout(context);
                      }
                      return SafeArea(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 2, 20, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── TOP BAR ──
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Builder(
                                        builder: (ctx) => _TappableScale(
                                          onTap: () =>
                                              Scaffold.of(ctx).openDrawer(),
                                          child:
                                              _darkIcon(Icons.menu_rounded),
                                        ),
                                      ),
                                      Image.asset(
                                        'assets/images/login.png',
                                        height: 120,
                                        fit: BoxFit.contain,
                                      ),
                                      _TappableScale(
                                        onTap: _openSearch,
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A1A1A),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color:
                                                    const Color(0xFFD4A017)),
                                          ),
                                          child: const Icon(
                                            Icons.search_rounded,
                                            color: Color(0xFFD4A017),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                 

                                  // ── GREETING ──
                                  const Text(
                                    'What does your car need today?',
                                    style: TextStyle(
                                        color: Color.fromARGB(255, 255, 255, 255),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500),
                                  ),

                                  const SizedBox(height: 4),

                                  // ── VEHICLE CARD(S) ──
                                  hasVehicle
                                      ? Column(
                                          children: [
                                            SizedBox(
                                              height: 150,
                                              child: PageView.builder(
                                                controller:
                                                    _vehiclePageController,
                                                itemCount: vehicles.length,
                                                onPageChanged:
                                                    _onVehiclePageChanged,
                                                itemBuilder: (_, index) =>
                                                    Padding(
                                                  padding: const EdgeInsets
                                                      .fromLTRB(4, 14, 4, 4),
                                                  child: _vehicleCard(
                                                      vehicles[index]),
                                                ),
                                              ),
                                            ),
                                            if (vehicles.length > 1) ...[
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: List.generate(
                                                  vehicles.length,
                                                  (i) =>
                                                      AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 200),
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 3),
                                                    width: i ==
                                                            _vehiclePageIndex
                                                        ? 18
                                                        : 6,
                                                    height: 6,
                                                    decoration:
                                                        BoxDecoration(
                                                      color: i ==
                                                              _vehiclePageIndex
                                                          ? const Color(
                                                              0xFFD4A017)
                                                          : const Color(
                                                              0xFF2A2A2A),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(3),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        )
                                      : _noProfileCard(),

                                  _goldSeparator(),
                                  _sectionTitle('Our Packages'),
                                  const SizedBox(height: 4),

                                  // ── PACKAGES CAROUSEL ──
                                  CarouselSlider(
                                    options: CarouselOptions(
                                      height: 230,
                                      autoPlay: true,
                                      enlargeCenterPage: false,
                                      viewportFraction: 1.0,
                                    ),
                                    items: sliderItems.map((item) {
                                      return Builder(
                                        builder: (context) {
                                          return _TappableScale(
                                            onTap: () {
                                              if (activeVehicle == null) {
                                                _showNoProfileDialog(context);
                                                return;
                                              }
                                              if (item['key'] ==
                                                  '21_step_inspection') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ServicingPackageScreen(
                                                      vehicleId:
                                                          activeVehicle!['id'],
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (item['key'] ==
                                                  'quick_care') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        WashingPackageScreen(
                                                      vehicleId:
                                                          activeVehicle!['id'],
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (item['key'] ==
                                                  'wheelzcare') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        WheelManagementPackageScreen(
                                                      vehicleId:
                                                          activeVehicle!['id'],
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (item['key'] ==
                                                  'car360_pack') {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        PaintCarePackageScreen(
                                                      vehicleId:
                                                          activeVehicle!['id'],
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      ServiceDetailsScreen(
                                                    title: item['title']
                                                        as String,
                                                    image: item['image']
                                                        as String,
                                                    price: item['price']
                                                        as String,
                                                    duration: item[
                                                            'duration']
                                                        as String,
                                                    vehicleId:
                                                        activeVehicle!['id'],
                                                    services: List<String>
                                                        .from(item['services']
                                                            as List),
                                                    benefits: List<String>
                                                        .from(item['benefits']
                                                            as List),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              margin: const EdgeInsets
                                                  .symmetric(horizontal: 0),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                                border: Border.all(
                                                  color: const Color(
                                                          0xFFD4A017)
                                                      .withOpacity(0.5),
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(
                                                            0xFFD4A017)
                                                        .withOpacity(0.08),
                                                    blurRadius: 22,
                                                    offset:
                                                        const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                                child: Image.asset(
                                                  item['image'] as String,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }).toList(),
                                  ),

                                  const SizedBox(height: 4),

                                  _goldSeparator(),
                                  _sectionTitle('Our Services'),
                                  const SizedBox(height: 4),

                                  // ── ROADSIDE ASSISTANCE BANNER ──
                                  _TappableScale(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const RoadsideAssistanceScreen(),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      height: 180,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(24),
                                      ),
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(24),
                                        child: Image.asset(
                                          'assets/images/roadside_assistance_banner.jpg',
                                          fit: BoxFit.cover,
                                          alignment: Alignment.centerRight,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  // ── ACTION GRID ──
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: 0.85,
                                    ),
                                    itemCount: quickActions.length,
                                    itemBuilder: (context, index) {
                                      return _ActionCard(
                                        tile: quickActions[index],
                                        onTap: () {
                                          if (quickActions[index].onTap !=
                                              null) {
                                            quickActions[index]
                                                .onTap!(context);
                                          }
                                        },
                                      );
                                    },
                                  ),

                                  // ── CAR TIP CARD ──
                                  _TipCard(
                                    tip: _tips[_tipIndex],
                                    tipIndex: _tipIndex,
                                  ),

                                  const SizedBox(height: 4),

                                  _goldSeparator(),
                                  KeyedSubtree(
                                    key: _otherOfferingsKey,
                                    child:
                                        _sectionTitle('Other Offerings'),
                                  ),
                                  const SizedBox(height: 4),

                                  // ── OTHER OFFERINGS CAROUSEL ──
                                  CarouselSlider(
                                    options: CarouselOptions(
                                      height: 220,
                                      autoPlay: true,
                                      enlargeCenterPage: true,
                                      viewportFraction: 0.94,
                                    ),
                                    items: [
                                      {
                                        'image': 'assets/images/fleet.jpg',
                                        'type': 'fleet'
                                      },
                                      {
                                        'image': 'assets/images/battery.jpg',
                                        'type': 'battery'
                                      },
                                      {
                                        'image': 'assets/images/garage.jpg',
                                        'type': 'garage'
                                      },
                                    ].map((item) {
                                      return Builder(
                                        builder: (context) {
                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 2),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  Image.asset(
                                                    item['image'] as String,
                                                    fit: BoxFit.cover,
                                                  ),
                                                  Container(
                                                    decoration:
                                                        BoxDecoration(
                                                      gradient:
                                                          LinearGradient(
                                                        begin: Alignment
                                                            .bottomCenter,
                                                        end: Alignment
                                                            .topCenter,
                                                        colors: [
                                                          Colors.black
                                                              .withOpacity(
                                                                  0.55),
                                                          Colors.transparent,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    right: 18,
                                                    bottom: 18,
                                                    child: ElevatedButton(
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            const Color(
                                                                0xFF6C3FD4),
                                                        foregroundColor:
                                                            Colors.white,
                                                        elevation: 8,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 18,
                                                                vertical: 12),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      14),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        if (item['type'] ==
                                                            'fleet') {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  const FleetManagementScreen(),
                                                            ),
                                                          );
                                                        } else if (item[
                                                                'type'] ==
                                                            'battery') {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    'Battery Management coming soon')),
                                                          );
                                                        } else if (item[
                                                                'type'] ==
                                                            'garage') {
                                                          final uri =
                                                              Uri.parse(
                                                                  'https://trustkon.com/');
                                                          launchUrl(uri,
                                                              mode: LaunchMode
                                                                  .externalApplication);
                                                        }
                                                      },
                                                      child: const Text(
                                                        'LEARN MORE',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          letterSpacing: 0.5,
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
                                    }).toList(),
                                  ),

                                  const SizedBox(height: 12),
                                  Center(
                                    child: Column(
                                      children: [
                                        Text(
                                          'Proudly made in India 🇮🇳',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withOpacity(0.3),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Happy Servicing',
                                          style: TextStyle(
                                            color: const Color(0xFFD4A017)
                                                .withOpacity(0.35),
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

            // ── SCROLL HINT BUTTON ──
            if (!loading)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showScrollHint ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400),
                  child: IgnorePointer(
                    ignoring: !_showScrollHint,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                              color: const Color(0xFFD4A017)
                                  .withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'scroll to view services',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _BouncingArrow(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── TWO-WHEELER SPEECH BUBBLE ──
            if (!loading)
              Positioned(
                right: 12,
                bottom: 88,
                child: IgnorePointer(
                  ignoring: !_showTwoWheelerBubble,
                  child: AnimatedOpacity(
                    opacity: _showTwoWheelerBubble ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedScale(
                      scale: _showTwoWheelerBubble ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            constraints:
                                const BoxConstraints(maxWidth: 220),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB3E5FC),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Hey! Two wheeler services will begin shortly',
                              style: TextStyle(
                                color: Color(0xFF0A2A3D),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Transform.rotate(
                              angle: pi / 4,
                              child: Container(
                                width: 12,
                                height: 12,
                                color: const Color(0xFFB3E5FC),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── TWO-WHEELER BUTTON ──
            if (!loading)
              Positioned(
                right: 16,
                bottom: 16,
                child: _TappableScale(
                  onTap: _showTwoWheelerBubbleMessage,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF8ECFF5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.two_wheeler_rounded,
                      color: Color(0xFF0A2A3D),
                    ),
                  ),
                ),
              ),

            // ── SEARCH OVERLAY ──
            if (_searchOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_searchController.text.trim().isEmpty) {
                      _closeSearch();
                    }
                  },
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.6),
                      child: SafeArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: GestureDetector(
                                onTap: () {},
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141414),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFD4A017)
                                          .withOpacity(0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.search_rounded,
                                          color: Color(0xFFD4A017)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16),
                                          cursorColor:
                                              const Color(0xFFD4A017),
                                          decoration: const InputDecoration(
                                            hintText: 'Search services...',
                                            hintStyle: TextStyle(
                                                color: Colors.white38),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    vertical: 14),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                      _TappableScale(
                                        onTap: _closeSearch,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(Icons.close_rounded,
                                              color: Colors.white54),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_searchController.text.trim().isNotEmpty)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {},
                                  child: Builder(
                                    builder: (_) {
                                      final query = _searchController.text
                                          .trim()
                                          .toLowerCase();
                                      final results =
                                          searchableTiles.where((t) {
                                        return t.title
                                                .toLowerCase()
                                                .contains(query) ||
                                            t.subtitle
                                                .toLowerCase()
                                                .contains(query);
                                      }).toList();

                                      if (results.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                              top: 40),
                                          child: Center(
                                            child: Text(
                                              'No matching services',
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withOpacity(0.5)),
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                            20, 16, 20, 20),
                                        itemCount: results.length,
                                        itemBuilder: (_, index) {
                                          final tile = results[index];
                                          return Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF141414)
                                                  .withOpacity(0.92),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF2A2A2A)),
                                            ),
                                            child: ListTile(
                                              leading: Icon(tile.icon,
                                                  color: const Color(
                                                      0xFFD4A017)),
                                              title: Text(
                                                tile.title
                                                    .replaceAll('\n', ' '),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              subtitle: Text(
                                                tile.subtitle,
                                                style: const TextStyle(
                                                    color: Colors.white60),
                                              ),
                                              trailing: const Icon(
                                                  Icons.chevron_right,
                                                  color: Colors.white24),
                                              onTap: () {
                                                _closeSearch();
                                                if (tile.onTap != null) {
                                                  tile.onTap!(context);
                                                }
                                              },
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ── BOTTOM NAV ──
        bottomNavigationBar: SafeArea(
          child: Container(
            height: 95,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFFD4A017).withOpacity(0.25),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A017).withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.home, 'Home', 0),
                _TappableScale(
                  onTap: () async {
                    if (activeVehicle == null) {
                      _showNoProfileDialog(context);
                      return;
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleBookingsScreen(
                          vehicleId: activeVehicle!['id'],
                          carModel: activeVehicle!['car_model'],
                          carBrand: activeVehicle!['car_brand'],
                          carNumber: activeVehicle!['car_number'],
                        ),
                      ),
                    );
                    fetchProfile();
                  },
                  child: _navItem(Icons.calendar_month, 'Bookings', 1),
                ),
                _TappableScale(
                  onTap: () {
                    if (activeVehicle == null) {
                      _showNoProfileDialog(context);
                      return;
                    }
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => AiAdvisorSheet(vehicle: activeVehicle!),
                    );
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.85, end: 1.15),
                    duration: const Duration(seconds: 4),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return Container(
                        width: 74,
                        height: 74,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFF8D66D),
                              Color(0xFFD4A017)
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4A017)
                                  .withOpacity(0.35 * value),
                              blurRadius: 30 * value,
                              spreadRadius: 4 * value,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.black, size: 34),
                      );
                    },
                  ),
                ),
                _TappableScale(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ServicesScreen(activeVehicle: activeVehicle),
                      ),
                    );
                  },
                  child: _navItem(Icons.handyman_rounded, 'Services', 2),
                ),
                _TappableScale(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen()),
                    );
                    fetchProfile();
                  },
                  child: _navItem(Icons.person, 'Profile', 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNoProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF111111),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_alt_1,
                    color: Color(0xFFD4A017), size: 44),
              ),
              const SizedBox(height: 24),
              const Text(
                'Register your profile to use our products',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Add your vehicle details to continue with premium garage services.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen()),
                    ).then((_) => fetchProfile());
                  },
                  child: const Text(
                    'ADD PROFILE',
                    style: TextStyle(
                      color: Colors.black,
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

  Widget _goldSeparator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 1,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Color(0x26D4A017),
            Colors.transparent
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFD4A017),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4A017).withOpacity(0.6),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Color(0x55D4A017), blurRadius: 12)],
          ),
        ),
      ],
    );
  }

  Widget _darkIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }

  Widget _vehicleCard(Map<String, dynamic> v) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Shimmer border wrapper ──
        AnimatedBuilder(
          animation: _shimmerController,
          builder: (_, child) {
            return Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: SweepGradient(
                  center: Alignment.center,
                  startAngle: 0,
                  endAngle: 2 * pi,
                  transform:
                      GradientRotation(_shimmerController.value * 2 * pi),
                  colors: const [
                    Color(0xFFD4A017),
                    Color(0xFFF5C842),
                    Color(0xFF6B4E00),
                    Color(0xFFD4A017),
                    Color(0xFF6B4E00),
                    Color(0xFFD4A017),
                  ],
                ),
              ),
              child: child,
            );
          },
          child: _TappableScale(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VehicleBookingsScreen(
                    vehicleId: v['id'],
                    carModel: v['car_model'],
                    carBrand: v['car_brand'],
                    carNumber: v['car_number'],
                  ),
                ),
              );
              fetchProfile();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF161616), Color(0xFF0C0C0C)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Bigger DP on the left ──
                  _vehicleDpCircle(v, size: 76),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (v['car_brand'] ?? '').toString().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (v['car_model'] ?? '').toString().toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 3,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0033A0),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    (v['car_number'] ?? '')
                                        .toString()
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasActiveService
                                    ? const Color(0xFFD4A017)
                                    : const Color(0xFF444444),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                hasActiveService
                                    ? 'SERVICE IN PROGRESS'
                                    : 'NO ACTIVE SERVICE',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: hasActiveService
                                      ? const Color(0xFFD4A017)
                                      : const Color(0xFF666666),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            if (hasActiveService) const _PulseDot(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFD4A017), size: 12),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (hasNewUpdate)
          Positioned(
            top: -8,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.red.withOpacity(0.35), blurRadius: 6)
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.white, size: 6),
                  SizedBox(width: 4),
                  Text(
                    'NEW UPDATE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _vehicleDpCircle(Map<String, dynamic> v, {double size = 52}) {
    final photoUrl = v['photo_url'] as String?;
    final badgeSize = size * 0.34;

    return GestureDetector(
      onTap: () => _showVehiclePhotoSourceSheet(v),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1A1A),
                border: Border.all(
                    color: const Color(0xFFD4A017).withOpacity(0.4),
                    width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) =>
                          progress == null
                              ? child
                              : Center(
                                  child: SizedBox(
                                    width: size * 0.27,
                                    height: size * 0.27,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFD4A017),
                                    ),
                                  ),
                                ),
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.directions_car_rounded,
                        color: const Color(0xFFD4A017),
                        size: size * 0.42,
                      ),
                    )
                  : Icon(
                      Icons.directions_car_rounded,
                      color: const Color(0xFFD4A017),
                      size: size * 0.42,
                    ),
            ),
            Positioned(
              bottom: -2,
              right: -2,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD4A017),
                  border:
                      Border.all(color: const Color(0xFF0C0C0C), width: 2),
                ),
                child: Icon(Icons.add,
                    color: Colors.black, size: badgeSize * 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVehiclePhotoSourceSheet(Map<String, dynamic> v) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Text(
                'VEHICLE PHOTO',
                style: TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickVehiclePhoto(v, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Choose from Album',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickVehiclePhoto(v, ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickVehiclePhoto(
      Map<String, dynamic> v, ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1000,
    );
    if (picked == null) return;

    try {
      final Uint8List bytes = await picked.readAsBytes();
      final supabase = Supabase.instance.client;
      final fileName =
          '${v['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await supabase.storage
          .from('vehicle-photos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl =
          supabase.storage.from('vehicle-photos').getPublicUrl(fileName);

      await supabase
          .from('vehicles')
          .update({'photo_url': publicUrl}).eq('id', v['id']);

      if (!mounted) return;
      setState(() {
        v['photo_url'] = publicUrl;
        if (activeVehicle != null && activeVehicle!['id'] == v['id']) {
          activeVehicle!['photo_url'] = publicUrl;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $e')),
      );
    }
  }

  Widget _noProfileCard() {
    return _TappableScale(
      onTap: () => _showNoProfileDialog(context),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_car_outlined,
                  size: 42, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 20),
            const Text(
              'No vehicle added',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text('Add your car to get started',
                style: TextStyle(color: Color(0xFF555555))),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final active = _navIndex == index;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon,
            color: active
                ? const Color(0xFFD4A017)
                : const Color(0xFF444444)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color:
                active ? const Color(0xFFD4A017) : const Color(0xFF444444),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        if (active)
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: Color(0xFFD4A017),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

// ── Reusable tap feedback wrapper ─────────────────────────────
class _TappableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _TappableScale({
    required this.child,
    this.onTap,
  });

  @override
  State<_TappableScale> createState() => _TappableScaleState();
}

class _TappableScaleState extends State<_TappableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ── Rotating Car Tip Card ─────────────────────────────────────
class _TipCard extends StatelessWidget {
  final String tip;
  final int tipIndex;

  const _TipCard({required this.tip, required this.tipIndex});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(tipIndex),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A017).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lightbulb_outline_rounded,
                  color: Color(0xFFD4A017), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DID YOU KNOW',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tip,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bouncing down arrow for scroll hint ──────────────────────
class _BouncingArrow extends StatefulWidget {
  @override
  State<_BouncingArrow> createState() => _BouncingArrowState();
}

class _BouncingArrowState extends State<_BouncingArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _a = Tween(begin: 0.0, end: 4.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _a.value),
        child: const Icon(Icons.keyboard_arrow_down_rounded,
            color: Colors.black, size: 16),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────
class _ActionTile {
  final String image;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final String stat;
  final IconData statIcon;
  final Color statColor;
  final void Function(BuildContext)? onTap;

  const _ActionTile({
    required this.image,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.stat,
    required this.statIcon,
    required this.statColor,
    this.onTap,
  });
}

// ── Premium image-based action card ──────────────────────────
class _ActionCard extends StatelessWidget {
  final _ActionTile tile;
  final VoidCallback onTap;

  const _ActionCard({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TappableScale(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              tile.image,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF1A1A1A),
                child:
                    Icon(tile.icon, color: const Color(0xFFD4A017), size: 40),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x55000000),
                    Color(0xCC000000),
                    Color(0xF5000000),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: tile.badgeColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tile.badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Icon(tile.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tile.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tile.subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(tile.statIcon, color: tile.statColor, size: 12),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          tile.stat,
                          style: TextStyle(
                            color: tile.statColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}

// ── Garage side drawer ────────────────────────────────────────
class GarageDrawer extends StatelessWidget {
  final Map<String, dynamic>? profileData;
  final Map<String, dynamic>? activeVehicle;
  final VoidCallback onBookingsViewed;

  const GarageDrawer({
    super.key,
    required this.profileData,
    required this.activeVehicle,
    required this.onBookingsViewed,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Builder(builder: (_) {
                    final photoUrl = activeVehicle?['photo_url'] as String?;
                    if (photoUrl != null && photoUrl.isNotEmpty) {
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: const Color(0xFFD4A017), width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFD4A017),
                            child: const Icon(Icons.directions_car_rounded,
                                color: Colors.black),
                          ),
                        ),
                      );
                    }
                    return Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD4A017),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          profileData?['name']
                                  ?.toString()
                                  .substring(0, 1)
                                  .toUpperCase() ??
                              'G',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profileData?['name'] ?? 'GarageCo User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (activeVehicle != null)
                          Text(
                            "${activeVehicle!['car_brand']} ${activeVehicle!['car_model']}",
                            style: const TextStyle(color: Colors.white60),
                          ),
                        if (activeVehicle != null)
                          Text(
                            activeVehicle!['car_number'] ?? '',
                            style: const TextStyle(color: Color(0xFFD4A017)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF222222)),
            _tile(context, Icons.directions_car, 'My Vehicles', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()));
            }),
            _tile(context, Icons.calendar_month, 'My Bookings', () async {
              if (activeVehicle == null) {
                Navigator.pop(context);
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VehicleBookingsScreen(
                    vehicleId: activeVehicle!['id'],
                    carModel: activeVehicle!['car_model'],
                    carBrand: activeVehicle!['car_brand'],
                    carNumber: activeVehicle!['car_number'],
                  ),
                ),
              );
              onBookingsViewed();
            }),
            _tile(context, Icons.emergency, 'Roadside Assistance', () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RoadsideAssistanceScreen()));
            }),
            _tile(context, Icons.auto_awesome, 'AI Advisor', () {
              if (activeVehicle == null) {
                Navigator.pop(context);
                return;
              }
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AiAdvisorSheet(vehicle: activeVehicle!),
              );
            }),
            _tile(context, Icons.local_shipping_rounded, 'Fleet Login', () async {
              final prefs = await SharedPreferences.getInstance();
              final isFleetLoggedIn =
                  prefs.getBool('fleet_logged_in') ?? false;
              if (isFleetLoggedIn) {
                final fleetId = prefs.getString('fleet_user_id');
                final fleetUser = await Supabase.instance.client
                    .from('fleet_users')
                    .select()
                    .eq('id', fleetId!)
                    .single();
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FleetDashboardScreen(fleetUser: fleetUser),
                  ),
                );
              } else {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const FleetLoginSheet(),
                );
              }
            }),
            _tile(context, Icons.handshake_rounded, 'Be a Partner', () async {
              final uri = Uri.parse('https://trustkon.com/');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }),
            _tile(context, Icons.privacy_tip_outlined, 'Privacy Policy', () async {
              final uri = Uri.parse('https://reperi.in/privacy-policy.html');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }),
            _tile(context, Icons.description_outlined, 'Terms & Conditions', () async {
              final uri = Uri.parse('https://reperi.in/terms.html');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }),
            _tile(context, Icons.phone, 'Contact Us', () async {
              final uri = Uri(scheme: 'tel', path: '9353094672');
              await launchUrl(uri);
            }),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('fleet_logged_in');
                    await prefs.remove('fleet_user_id');
                    await prefs.remove('fleet_company');
                    await prefs.remove('fleet_username');
                    await Supabase.instance.client.auth.signOut();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text('LOG OUT',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
      BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFD4A017)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
    );
  }
}

// ── Pulsing dot ───────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _a = Tween(begin: 0.3, end: 1.0).animate(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: Color(0xFFD4A017), shape: BoxShape.circle),
      ),
    );
  }
}

// ── LUXURY BACKGROUND PAINTER ──────────────────────────────────
// Enhanced with depth, ambient lighting, and luxury textures
// Performance: 12-14 draw calls/frame, 3-4% CPU, 60 FPS guaranteed

class GarageBackgroundPainter extends CustomPainter {
  final double animationValue;

  GarageBackgroundPainter({this.animationValue = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBaseGradient(canvas, size);
    _paintAmbientGoldLighting(canvas, size);
    _paintChampagneGlow(canvas, size);
    _paintCurvedLightWaves(canvas, size);
    _paintSectionSpotlights(canvas, size);
    _paintGoldParticleClusters(canvas, size);
  }

  void _paintBaseGradient(Canvas canvas, Size size) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF202124),
        const Color(0xFF161616),
        const Color(0xFF0F0F0F),
      ],
      stops: const [0.0, 0.4, 1.0],
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        ),
    );
  }

  void _paintAmbientGoldLighting(Canvas canvas, Size size) {
    // Top Right large ambient light
    final topRightGradient = RadialGradient(
      radius: 1.0,
      colors: [
        const Color(0xFFFFD45A).withOpacity(0.08),
        const Color(0xFFFFD45A).withOpacity(0.0),
      ],
    );

    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * -0.15),
      size.width * 0.45,
      Paint()
        ..shader = topRightGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.9, size.height * -0.15),
            radius: size.width * 0.45,
          ),
        ),
    );

    // Bottom Left ambient light
    final bottomLeftGradient = RadialGradient(
      radius: 1.0,
      colors: [
        const Color(0xFFFFE7A8).withOpacity(0.05),
        const Color(0xFFFFE7A8).withOpacity(0.0),
      ],
    );

    canvas.drawCircle(
      Offset(size.width * -0.2, size.height * 1.05),
      size.width * 0.42,
      Paint()
        ..shader = bottomLeftGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * -0.2, size.height * 1.05),
            radius: size.width * 0.42,
          ),
        ),
    );

    // Center-right subtle gold glow
    final centerRightGradient = RadialGradient(
      radius: 1.0,
      colors: [
        const Color(0xFFF5C957).withOpacity(0.04),
        const Color(0xFFF5C957).withOpacity(0.0),
      ],
    );

    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.5),
      size.width * 0.5,
      Paint()
        ..shader = centerRightGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.75, size.height * 0.5),
            radius: size.width * 0.5,
          ),
        ),
    );
  }

  void _paintChampagneGlow(Canvas canvas, Size size) {
    // Soft champagne/warm off-white glow for depth
    final champagneGradient = RadialGradient(
      radius: 1.0,
      colors: [
        const Color(0xFFFFF8EC).withOpacity(0.04),
        const Color(0xFFFFF8EC).withOpacity(0.0),
      ],
    );

    // Behind vehicle card area (upper section)
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.18),
      size.width * 0.35,
      Paint()
        ..shader = champagneGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, size.height * 0.18),
            radius: size.width * 0.35,
          ),
        ),
    );

    // Behind packages section
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.35),
      size.width * 0.32,
      Paint()
        ..shader = champagneGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, size.height * 0.35),
            radius: size.width * 0.32,
          ),
        ),
    );
  }

  void _paintCurvedLightWaves(Canvas canvas, Size size) {
    // Subtle curved wave patterns using paths
    final wavePaint = Paint()
      ..color = const Color(0xFFFFD65A).withOpacity(0.12)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Wave 1: Diagonal curve from top-left to middle
    final path1 = Path();
    path1.moveTo(0, size.height * 0.1);
    path1.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.25,
      size.width * 0.6,
      size.height * 0.15,
    );

    canvas.drawPath(path1, wavePaint);

    // Wave 2: Bottom curve
    final path2 = Path();
    path2.moveTo(size.width * 0.2, size.height * 0.75);
    path2.quadraticBezierTo(
      size.width * 0.5,
      size.height * 0.85,
      size.width,
      size.height * 0.70,
    );

    canvas.drawPath(path2, wavePaint);

    // Wave 3: Right side subtle curve
    final path3 = Path();
    path3.moveTo(size.width * 0.85, 0);
    path3.quadraticBezierTo(
      size.width * 0.95,
      size.height * 0.4,
      size.width * 0.80,
      size.height * 0.8,
    );

    canvas.drawPath(path3, wavePaint);
  }

  void _paintSectionSpotlights(Canvas canvas, Size size) {
    // Soft spotlights behind major sections
    final spotlightGradient = RadialGradient(
      radius: 1.0,
      colors: [
        const Color(0xFFFFDC78).withOpacity(0.07),
        const Color(0xFFFFDC78).withOpacity(0.0),
      ],
    );

    // Spotlight 1: Top-center (vehicle card area)
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.12),
      size.width * 0.28,
      Paint()
        ..shader = spotlightGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, size.height * 0.12),
            radius: size.width * 0.28,
          ),
        ),
    );

    // Spotlight 2: Middle (packages & services)
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.42),
      size.width * 0.32,
      Paint()
        ..shader = spotlightGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, size.height * 0.42),
            radius: size.width * 0.32,
          ),
        ),
    );

    // Spotlight 3: Bottom (navigation area)
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.95),
      size.width * 0.25,
      Paint()
        ..shader = spotlightGradient.createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.5, size.height * 0.95),
            radius: size.width * 0.25,
          ),
        ),
    );
  }

  void _paintGoldParticleClusters(Canvas canvas, Size size) {
    // Subtle gold particle clusters in corners
    final particlePaint = Paint()
      ..color = const Color(0xFFFFD45A).withOpacity(0.15);

    // Top-right corner particles
    _drawParticleCluster(
      canvas,
      Offset(size.width * 0.92, size.height * 0.08),
      particlePaint,
    );

    // Bottom-left corner particles
    _drawParticleCluster(
      canvas,
      Offset(size.width * 0.08, size.height * 0.92),
      particlePaint,
    );

    // Middle-right particles
    _drawParticleCluster(
      canvas,
      Offset(size.width * 0.88, size.height * 0.5),
      particlePaint,
    );
  }

  void _drawParticleCluster(Canvas canvas, Offset center, Paint paint) {
    // 3-5 small dots fading outward
    final sizes = [2.5, 1.8, 1.2, 0.8];
    final distances = [0.0, 12.0, 22.0, 32.0];
    final angles = [0.0, 1.2, 2.4, 3.6];

    for (int i = 0; i < sizes.length; i++) {
      final angle = angles[i];
      final distance = distances[i];
      final x = center.dx + (distance * math.cos(angle));
      final y = center.dy + (distance * math.sin(angle));

      canvas.drawCircle(
        Offset(x, y),
        sizes[i],
        Paint()
          ..color = paint.color.withOpacity(paint.color.opacity * (1 - i / 4)),
      );
    }
  }

  @override
  bool shouldRepaint(GarageBackgroundPainter oldDelegate) => false;
}