import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hello_world_app/screens/ai_advisor_sheet.dart';
import 'package:hello_world_app/screens/fleet_dashboard_screen.dart';
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
import '../constants/app_colors.dart';
import 'profile_screen.dart';
import 'service_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? profileData;
  Map<String, dynamic>? activeVehicle;

  bool hasActiveService = false;
  bool hasNewUpdate = false;
  bool loading = true;
  int _navIndex = 0;

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

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showScrollHint = true);
    });
  }

  void _onScroll() {
    if (_showScrollHint) {
      setState(() => _showScrollHint = false);
    }
    _startIdleTimer();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _orbController.dispose();
    _tipTimer?.cancel();
    _idleTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
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

      Map<String, dynamic>? vehicle;
      bool serviceExists = false;
      bool updateExists = false;

      if (profile != null && profile['active_vehicle_id'] != null) {
        final vResponse = await supabase
            .from('vehicles')
            .select()
            .eq('id', profile['active_vehicle_id'])
            .maybeSingle();

        vehicle = vResponse;

        final bookingResponse = await supabase
            .from('bookings')
            .select()
            .eq('vehicle_id', vehicle!['id']);

        serviceExists = bookingResponse.isNotEmpty;

        if (bookingResponse.isNotEmpty) {
          final bookingId = bookingResponse[0]['id'];
          final updates = await supabase
              .from('booking_updates')
              .select()
              .eq('booking_id', bookingId);
          updateExists = updates.isNotEmpty;
        }
      }

      if (!mounted) return;

      setState(() {
        profileData = profile;
        activeVehicle = vehicle;
        hasActiveService = serviceExists;
        hasNewUpdate = updateExists;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = profileData != null;
    final hasVehicle = activeVehicle != null;

    final sliderItems = [
      {
        'image': 'assets/images/21pointinspection.JPG',
        'title': '21 STEP\nINSPECTION',
        'price': '₹599',
        'duration': '45 mins',
        'services': ['Engine Check', 'Brake Inspection', 'Battery Health'],
        'benefits': ['Prevent breakdowns', 'Vehicle health report'],
      },
      {
        'image': 'assets/images/quickcare.JPG',
        'title': 'QUICK CARE',
        'price': '₹399',
        'duration': '30 mins',
        'services': ['Exterior Wash', 'Interior Vacuum'],
        'benefits': ['Cleaner interiors', 'Quick refresh'],
      },
      {
        'image': 'assets/images/WheelzCare.JPG',
        'title': 'WHEELZCARE',
        'price': '₹599',
        'duration': '45 mins',
        'services': ['Wheel Alignment', 'Wheel Balancing'],
        'benefits': ['Smoother driving', 'Longer tyre life'],
      },
      {
        'image': 'assets/images/car360.JPG',
        'title': 'CAR360 PACK',
        'price': '₹1599',
        'duration': '3 hrs',
        'services': ['Detailing', 'Paint Protection'],
        'benefits': ['Showroom finish', 'Premium shine'],
      },
    ];

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
          // No dedicated screen yet — keeping previous behavior (no navigation),
          // but now guarded so it won't silently do nothing without explanation.
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
        },
      ),
      _ActionTile(
        image: 'assets/images/tile_insurance.jpg',
        icon: Icons.shield_rounded,
        title: 'Insurance\nClaims',
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
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      drawer: GarageDrawer(
        profileData: profileData,
        activeVehicle: activeVehicle,
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

          // ── Racing lines + grid background ──
          Positioned.fill(
            child: CustomPaint(painter: GarageBackgroundPainter()),
          ),

          // ── Main content ──
          loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4A017)),
                )
              : SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),

                            // ── TOP BAR ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Builder(
                                  builder: (ctx) => GestureDetector(
                                    onTap: () =>
                                        Scaffold.of(ctx).openDrawer(),
                                    child: _darkIcon(Icons.menu_rounded),
                                  ),
                                ),
                                Image.asset(
                                  'assets/images/login.png',
                                  height: 110,
                                  fit: BoxFit.contain,
                                ),
                                GestureDetector(
                                  onTap: () async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    final isFleetLoggedIn =
                                        prefs.getBool('fleet_logged_in') ??
                                            false;
                                    if (isFleetLoggedIn) {
                                      final fleetId =
                                          prefs.getString('fleet_user_id');
                                      final fleetUser =
                                          await Supabase.instance.client
                                              .from('fleet_users')
                                              .select()
                                              .eq('id', fleetId!)
                                              .single();
                                      if (!context.mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FleetDashboardScreen(
                                              fleetUser: fleetUser),
                                        ),
                                      );
                                    } else {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) =>
                                            const FleetLoginSheet(),
                                      );
                                    }
                                  },
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A1A),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: const Color(0xFFD4A017)),
                                    ),
                                    child: const Icon(
                                      Icons.local_shipping_rounded,
                                      color: Color(0xFFD4A017),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 34),

                            // ── GREETING ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Good day 👋',
                                      style: TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 16),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      hasProfile
                                          ? profileData!['name'].toString()
                                          : 'Complete Profile',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 34,
                                        letterSpacing: -0.8,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'What does your car need today?',
                                      style: TextStyle(
                                          color: Color(0xFF555555),
                                          fontSize: 14),
                                    ),
                                  ],
                                ),
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD4A017),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      hasProfile
                                          ? profileData!['name'][0]
                                              .toUpperCase()
                                          : 'G',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 30),

                            // ── VEHICLE CARD ──
                            hasVehicle
                                ? _vehicleCard(activeVehicle!)
                                : _noProfileCard(),

                            const SizedBox(height: 20),

                            // ── CAR TIP CARD ──
                            _TipCard(
                              tip: _tips[_tipIndex],
                              tipIndex: _tipIndex,
                            ),

                            const SizedBox(height: 34),

                            _goldSeparator(),
                            _sectionTitle('Our Packages'),
                            const SizedBox(height: 20),

                            // ── PACKAGES CAROUSEL ──
                            CarouselSlider(
                              options: CarouselOptions(
                                height: 230,
                                autoPlay: true,
                                enlargeCenterPage: true,
                                viewportFraction: 0.9,
                              ),
                              items: sliderItems.map((item) {
                                return Builder(
                                  builder: (context) {
                                    return GestureDetector(
                                      onTap: () {
                                        if (activeVehicle == null) {
                                          _showNoProfileDialog(context);
                                          return;
                                        }
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ServiceDetailsScreen(
                                              title: item['title'] as String,
                                              image: item['image'] as String,
                                              price: item['price'] as String,
                                              duration:
                                                  item['duration'] as String,
                                              vehicleId: activeVehicle!['id'],
                                              services: List<String>.from(
                                                  item['services'] as List),
                                              benefits: List<String>.from(
                                                  item['benefits'] as List),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(28),
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
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.asset(
                                                  item['image'] as String,
                                                  fit: BoxFit.cover),
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.bottomLeft,
                                                    end: Alignment.topRight,
                                                    colors: [
                                                      Colors.black
                                                          .withOpacity(0.88),
                                                      Colors.black
                                                          .withOpacity(0.18),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.all(24),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      item['title'] as String,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 30,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        height: 1,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      item['price'] as String,
                                                      style: const TextStyle(
                                                        color:
                                                            Color(0xFFF5C842),
                                                        fontSize: 34,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.timer,
                                                            color: Colors.white70,
                                                            size: 18),
                                                        const SizedBox(
                                                            width: 6),
                                                        Text(
                                                          item['duration']
                                                              as String,
                                                          style: const TextStyle(
                                                              color: Colors
                                                                  .white70),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 34),

                            _goldSeparator(),
                            _sectionTitle('Our Services'),
                            const SizedBox(height: 20),

                            // ── ROADSIDE ASSISTANCE BANNER ──
                            GestureDetector(
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

                            const SizedBox(height: 16),

                            // ── ACTION GRID ──
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: quickActions.length,
                              itemBuilder: (context, index) {
                                return _ActionCard(
                                  tile: quickActions[index],
                                  onTap: () {
                                    if (quickActions[index].onTap != null) {
                                      quickActions[index].onTap!(context);
                                    }
                                  },
                                );
                              },
                            ),

                            const SizedBox(height: 34),

                            _goldSeparator(),
                            _sectionTitle('Other Offerings'),
                            const SizedBox(height: 20),

                            // ── OTHER OFFERINGS CAROUSEL ──
                            CarouselSlider(
                              options: CarouselOptions(
                                height: 220,
                                autoPlay: true,
                                enlargeCenterPage: true,
                                viewportFraction: 0.9,
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
                                          horizontal: 4),
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
                                                  begin:
                                                      Alignment.bottomCenter,
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
                                                style:
                                                    ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFF6C3FD4),
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
                                                        BorderRadius.circular(
                                                            14),
                                                  ),
                                                ),
                                                onPressed: () {
                                                  if (item['type'] == 'fleet') {
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
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                          content: Text(
                                                              'Partner Garage Program coming soon')),
                                                    );
                                                  }
                                                },
                                                child: const Text(
                                                  'LEARN MORE',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
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

                            const SizedBox(height: 120),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.15)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'scroll to view services',
                            style: TextStyle(
                              color: Colors.white,
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
        ],
      ),

      // ── BOTTOM NAV ──
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 95,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
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
              GestureDetector(
                onTap: () {
                  if (activeVehicle == null) {
                    _showNoProfileDialog(context);
                    return;
                  }
                  Navigator.push(
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
                },
                child: _navItem(Icons.calendar_month, 'Bookings', 1),
              ),
              GestureDetector(
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
                          colors: [Color(0xFFF8D66D), Color(0xFFD4A017)],
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
              GestureDetector(
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
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                  fetchProfile();
                },
                child: _navItem(Icons.person, 'Profile', 3),
              ),
            ],
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
          colors: [Colors.transparent, Color(0x26D4A017), Colors.transparent],
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
                borderRadius: BorderRadius.circular(30),
                gradient: SweepGradient(
                  center: Alignment.center,
                  startAngle: 0,
                  endAngle: 2 * pi,
                  transform: GradientRotation(
                      _shimmerController.value * 2 * pi),
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
          child: GestureDetector(
            onTap: () {
              Navigator.push(
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
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF161616), Color(0xFF0C0C0C)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACTIVE VEHICLE',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 10,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v['car_brand'] ?? '',
                              style: const TextStyle(
                                color: Color(0xFF666666),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              v['car_model'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.directions_car_rounded,
                        size: 64,
                        color: const Color(0xFFD4A017).withOpacity(0.15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(height: 1, color: const Color(0xFF222222)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF0033A0), width: 3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0033A0),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              v['car_number'] ?? '',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFD4A017).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_forward_ios_rounded,
                            color: Color(0xFFD4A017), size: 14),
                      ),
                    ],
                  ),
                  if (hasActiveService) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                const Color(0xFFD4A017).withOpacity(0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.build_circle_rounded,
                              color: Color(0xFFD4A017), size: 16),
                          SizedBox(width: 10),
                          Text(
                            'SERVICE IN PROGRESS',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                          Spacer(),
                          _PulseDot(),
                        ],
                      ),
                    ),
                  ],
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
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.red.withOpacity(0.5), blurRadius: 10)
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.white, size: 7),
                  SizedBox(width: 5),
                  Text(
                    'NEW UPDATE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _noProfileCard() {
    return GestureDetector(
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
            color: Colors.white, size: 16),
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
    return GestureDetector(
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

  const GarageDrawer({
    super.key,
    required this.profileData,
    required this.activeVehicle,
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
                  Container(
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
                  ),
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
            _tile(context, Icons.calendar_month, 'My Bookings', () {
              if (activeVehicle == null) {
                Navigator.pop(context);
                return;
              }
              Navigator.push(
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
            _tile(context, Icons.shield, 'Insurance Claims', () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Insurance screen coming soon')),
              );
            }),
            _tile(context, Icons.card_giftcard, 'Offers & Referrals', () {}),
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

// ── Background painter ────────────────────────────────────────
class GarageBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4A017).withOpacity(0.08)
      ..strokeWidth = 1;

    for (double i = -size.height; i < size.width; i += 24) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }

    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.010)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 120) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guidePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}