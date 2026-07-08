import 'dart:async';
import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';

class CarSpaScreen extends StatefulWidget {

  final Map<String, dynamic> vehicle;

  const CarSpaScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<CarSpaScreen> createState() =>
      _CarSpaScreenState();
}

class _CarSpaScreenState
    extends State<CarSpaScreen> {

  final PageController
      _beforeAfterController =
      PageController();

  int _currentPage = 0;

  Timer? _autoScrollTimer;

  int selectedPackage = -1;

  final List<String>
      _beforeAfterImages = [

    'assets/images/before_after_1.jpg',

    'assets/images/before_after_2.jpg',

    'assets/images/before_after_3.jpg',
  ];

  static const Color _bg =
      Color(0xFF0A0A0A);

  static const Color _card =
      Color(0xFF141414);

  static const Color _gold =
      Color(0xFFD4A84B);

  static const Color _white =
      Color(0xFFFFFFFF);

  static const Color _grey =
      Color(0xFF9E9E9E);

  static const Color _cardBorder =
      Color(0xFF2A2A2A);

  List<Map<String, dynamic>>
      packages = [

    {

      'title':
          'QUICK REFRESH',

      'subtitle':
          'Exterior Basic Care',

      'price':
          '₹399',

      'duration':
          '30 mins',

      'icon':
          Icons.water_drop_outlined,

      'features': [

        'Exterior Wash',

        'Vacuum Cleaning',

        'Tyre Polish',
      ],
    },

    {

      'title':
          'PREMIUM SPA',

      'subtitle':
          'Interior Deep Clean',

      'price':
          '₹999',

      'duration':
          '90 mins',

      'icon':
          Icons.chair_outlined,

      'features': [

        'Dashboard Detailing',

        'Steam Cleaning',

        'Odor Removal',

        'Interior Conditioning',
      ],
    },

    {

      'title':
          'SIGNATURE SPA+',

      'subtitle':
          'Complete Car Restoration',

      'price':
          '₹2499',

      'duration':
          '150 mins',

      'icon':
          Icons.diamond_outlined,

      'features': [

        'Foam Wash',

        'Paint Decontamination',

        'Wax Polish',

        'Interior Restoration',

        'Tyre Dressing',

        'Perfume Finish',
      ],
    },
  ];

  @override
  void initState() {

    super.initState();

    _startAutoScroll();
    _fetchPackageData();
  }

  Future<void> _fetchPackageData() async {
    try {
      final rows = await CatalogService.fetchByCategory('Car Spa');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      setState(() {
        if (byKey['car_spa_quick_refresh'] != null) {
          packages[0]['price'] = byKey['car_spa_quick_refresh']!['price'];
          packages[0]['duration'] = byKey['car_spa_quick_refresh']!['duration'];
          packages[0]['features'] = List<String>.from(byKey['car_spa_quick_refresh']!['services']);
        }
        if (byKey['car_spa_premium'] != null) {
          packages[1]['price'] = byKey['car_spa_premium']!['price'];
          packages[1]['duration'] = byKey['car_spa_premium']!['duration'];
          packages[1]['features'] = List<String>.from(byKey['car_spa_premium']!['services']);
        }
        if (byKey['car_spa_signature_plus'] != null) {
          packages[2]['price'] = byKey['car_spa_signature_plus']!['price'];
          packages[2]['duration'] = byKey['car_spa_signature_plus']!['duration'];
          packages[2]['features'] = List<String>.from(byKey['car_spa_signature_plus']!['services']);
        }
      });
    } catch (e) {
      // Keep the hardcoded fallback values above if the fetch fails.
    }
  }

  void _startAutoScroll() {

    _autoScrollTimer =
        Timer.periodic(

      const Duration(
          seconds: 3),

      (_) {

        final next =
            (_currentPage + 1) %
                _beforeAfterImages
                    .length;

        _beforeAfterController
            .animateToPage(

          next,

          duration:
              const Duration(
                  milliseconds:
                      500),

          curve:
              Curves.easeInOut,
        );
      },
    );
  }

  @override
  void dispose() {

    _autoScrollTimer
        ?.cancel();

    _beforeAfterController
        .dispose();

    super.dispose();
  }

  @override
  Widget build(
      BuildContext context) {

    return Scaffold(

      backgroundColor: _bg,

      body: SingleChildScrollView(
  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            _buildHero(),

            _buildBeforeAfter(),

            _buildPackages(),

            _buildWhyUs(),

            _buildLiveTracking(),

            _buildBottomCTA(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildHero() {

    return Stack(

      children: [

        SizedBox(

          width:
              double.infinity,

          height: 420,

          child: Image.asset(

            'assets/images/car_spa_hero.jpg',

            fit: BoxFit.cover,

            errorBuilder:
                (_, __, ___) =>
                    Container(

              color: const Color(
                  0xFF1A1A1A),

              child:
                  const Center(

                child: Icon(

                  Icons
                      .directions_car,

                  color: _gold,

                  size: 80,
                ),
              ),
            ),
          ),
        ),

        Container(

          width:
              double.infinity,

          height: 420,

          decoration:
              const BoxDecoration(

            gradient:
                LinearGradient(

              begin: Alignment
                  .centerRight,

              end: Alignment
                  .centerLeft,

              colors: [

                Colors
                    .transparent,

                Color(
                    0xCC000000),

                Color(
                    0xEE000000),
              ],
            ),
          ),
        ),

        SafeArea(

          child: Padding(

            padding:
                const EdgeInsets
                    .fromLTRB(

              24,
              48,
              24,
              32,
            ),

            child: Column(

              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              children: [

                const Text(

                  'PREMIUM',

                  style:
                      TextStyle(

                    color:
                        _white,

                    fontSize:
                        28,

                    fontWeight:
                        FontWeight
                            .w300,

                    letterSpacing:
                        6,
                  ),
                ),

                const Text(

                  'CAR SPA',

                  style:
                      TextStyle(

                    color:
                        _gold,

                    fontSize:
                        52,

                    fontWeight:
                        FontWeight
                            .w800,

                    letterSpacing:
                        2,

                    height: 1.0,
                  ),
                ),

                const SizedBox(
                    height: 10),

                const Text(

                  'Restore showroom shine.',

                  style: TextStyle(

                    color:
                        _white,

                    fontSize: 16,

                    fontWeight:
                        FontWeight
                            .w300,
                  ),
                ),

                const SizedBox(
                    height: 12),

                Row(

                  children:
                      const [

                    Text(

                      'INTERIOR',

                      style:
                          TextStyle(

                        color:
                            _grey,

                        fontSize:
                            12,

                        letterSpacing:
                            2,
                      ),
                    ),

                    Padding(

                      padding:
                          EdgeInsets.symmetric(
                              horizontal:
                                  8),

                      child: Text(

                        '•',

                        style:
                            TextStyle(

                          color:
                              _gold,

                          fontSize:
                              12,
                        ),
                      ),
                    ),

                    Text(

                      'EXTERIOR',

                      style:
                          TextStyle(

                        color:
                            _grey,

                        fontSize:
                            12,

                        letterSpacing:
                            2,
                      ),
                    ),

                    Padding(

                      padding:
                          EdgeInsets.symmetric(
                              horizontal:
                                  8),

                      child: Text(

                        '•',

                        style:
                            TextStyle(

                          color:
                              _gold,

                          fontSize:
                              12,
                        ),
                      ),
                    ),

                    Text(

                      'DETAILING',

                      style:
                          TextStyle(

                        color:
                            _grey,

                        fontSize:
                            12,

                        letterSpacing:
                            2,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                    height: 28),

                Container(

                  padding:
                      const EdgeInsets
                          .all(18),

                  decoration:
                      BoxDecoration(

                    color: Colors
                        .black
                        .withOpacity(
                            0.35),

                    borderRadius:
                        BorderRadius.circular(
                            18),

                    border:
                        Border.all(

                      color: _gold
                          .withOpacity(
                              0.3),
                    ),
                  ),

                  child:
                      const Column(

                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [

                      Text(

                        'PREMIUM SPA EXPERIENCE',

                        style:
                            TextStyle(

                          color:
                              _gold,

                          fontSize:
                              13,

                          fontWeight:
                              FontWeight
                                  .w800,

                          letterSpacing:
                              2,
                        ),
                      ),

                      SizedBox(
                          height:
                              12),

                      Text(

                        'Luxury detailing and restoration packages designed to bring back showroom-level shine and comfort.',

                        style:
                            TextStyle(

                          color:
                              _white,

                          fontSize:
                              15,

                          height:
                              1.6,
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
    );
  }

  Widget _buildBeforeAfter() {

    return Padding(

      padding:
          const EdgeInsets
              .fromLTRB(
                  0,
                  28,
                  0,
                  0),

      child: Column(

        crossAxisAlignment:
            CrossAxisAlignment
                .start,

        children: [

          const Padding(

            padding:
                EdgeInsets.symmetric(
                    horizontal:
                        20),

            child: Text(

              'BEFORE & AFTER',

              style: TextStyle(

                color:
                    _white,

                fontSize:
                    18,

                fontWeight:
                    FontWeight
                        .w800,
              ),
            ),
          ),

          const SizedBox(
              height: 14),

          SizedBox(

            height: 210,

            child:
                PageView.builder(

              controller:
                  _beforeAfterController,

              onPageChanged:
                  (i) {

                setState(() {

                  _currentPage =
                      i;
                });
              },

              itemCount:
                  _beforeAfterImages
                      .length,

              itemBuilder:
                  (context,
                      index) {

                return Padding(

                  padding:
                      const EdgeInsets
                          .symmetric(
                              horizontal:
                                  16),

                  child:
                      ClipRRect(

                    borderRadius:
                        BorderRadius.circular(
                            14),

                    child:
                        Image.asset(

                      _beforeAfterImages[
                          index],

                      fit: BoxFit
                          .cover,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackages() {

    return Padding(

      padding:
          const EdgeInsets
              .fromLTRB(
                  20,
                  32,
                  20,
                  0),

      child: Column(

        crossAxisAlignment:
            CrossAxisAlignment
                .start,

        children: [

          const Text(

            'OUR SPA PACKAGES',

            style: TextStyle(

              color:
                  _white,

              fontSize: 18,

              fontWeight:
                  FontWeight
                      .w800,
            ),
          ),

          const SizedBox(
              height: 16),

          ...List.generate(

            packages.length,

            (index) {

              final p =
                  packages[index];

              final selected =
                  selectedPackage ==
                      index;

              return GestureDetector(

                onTap: () {

                  setState(() {

                    selectedPackage =
                        index;
                  });
                },

                child: AnimatedContainer(

                  duration:
                      const Duration(
                          milliseconds:
                              300),

                  margin:
                      const EdgeInsets
                          .only(
                              bottom:
                                  16),

                  padding:
                      const EdgeInsets
                          .all(18),

                  decoration:
                      BoxDecoration(

                    color:
                        _card,

                    borderRadius:
                        BorderRadius.circular(
                            18),

                    border:
                        Border.all(

                      color: selected

                          ? _gold

                          : _cardBorder,

                      width:
                          selected
                              ? 2
                              : 1,
                    ),

                    boxShadow:
                        selected

                            ? [

                                BoxShadow(

                                  color: _gold
                                      .withOpacity(
                                          0.35),

                                  blurRadius:
                                      18,
                                ),
                              ]

                            : [],
                  ),

                  child:
                      Column(

                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [

                      Row(

                        children: [

                          Container(

                            padding:
                                const EdgeInsets
                                    .all(
                                        10),

                            decoration:
                                BoxDecoration(

                              color: _gold
                                  .withOpacity(
                                      0.12),

                              borderRadius:
                                  BorderRadius.circular(
                                      10),
                            ),

                            child:
                                Icon(

                              p['icon']
                                  as IconData,

                              color:
                                  _gold,
                            ),
                          ),

                          const SizedBox(
                              width:
                                  14),

                          Expanded(

                            child:
                                Column(

                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,

                              children: [

                                Text(

                                  p['title']
                                      as String,

                                  style:
                                      const TextStyle(

                                    color:
                                        _white,

                                    fontSize:
                                        18,

                                    fontWeight:
                                        FontWeight
                                            .w800,
                                  ),
                                ),

                                const SizedBox(
                                    height:
                                        4),

                                Text(

                                  p['subtitle']
                                      as String,

                                  style:
                                      const TextStyle(

                                    color:
                                        _grey,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Text(

                            p['price']
                                as String,

                            style:
                                const TextStyle(

                              color:
                                  _gold,

                              fontSize:
                                  24,

                              fontWeight:
                                  FontWeight
                                      .w800,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                          height: 18),

                      ...(p['features']
                              as List<
                                  String>)
                          .map(

                        (f) {

                          return Padding(

                            padding:
                                const EdgeInsets
                                    .only(
                                        bottom:
                                            8),

                            child:
                                Row(

                              children: [

                                const Icon(

                                  Icons
                                      .check_circle,

                                  color:
                                      _gold,

                                  size:
                                      18,
                                ),

                                const SizedBox(
                                    width:
                                        8),

                                Text(

                                  f,

                                  style:
                                      const TextStyle(

                                    color:
                                        _white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(
                          height: 18),

                      Container(

                        width: double
                            .infinity,

                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical:
                              12,
                        ),

                        decoration:
                            BoxDecoration(

                          color: selected

                              ? _gold

                              : Colors
                                  .transparent,

                          borderRadius:
                              BorderRadius.circular(
                                  10),

                          border:
                              Border.all(

                            color: selected

                                ? _gold

                                : _cardBorder,
                          ),
                        ),

                        child:
                            Center(

                          child: Text(

                            selected

                                ? 'SELECTED'

                                : 'SELECT',

                            style:
                                TextStyle(

                              color: selected

                                  ? Colors
                                      .black

                                  : _white,

                              fontWeight:
                                  FontWeight
                                      .w800,

                              letterSpacing:
                                  2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWhyUs() {

    return Container();
  }

  Widget _buildLiveTracking() {

    return Container();
  }

  Widget _buildBottomCTA() {

    return Padding(

      padding:
          const EdgeInsets
              .fromLTRB(
                  20,
                  24,
                  20,
                  0),

      child: GestureDetector(

        onTap: () {

          if (selectedPackage ==
              -1) {

            ScaffoldMessenger.of(
                    context)
                .showSnackBar(

              const SnackBar(

                content: Text(
                    'Please select a package'),
              ),
            );

            return;
          }

          final selected =
              packages[
                  selectedPackage];

          Navigator.push(

            context,

            MaterialPageRoute(

              builder: (_) =>
                  PaymentScreen(

                title:
                    selected[
                        'title'],

                price:
                    selected[
                        'price'],

                duration:
                    selected[
                        'duration'],

                vehicleId:
                    widget
                        .vehicle[
                            'id']
                        .toString(),
              ),
            ),
          );
        },

        child: Container(

          width:
              double.infinity,

          padding:
              const EdgeInsets
                  .symmetric(
            vertical: 18,
          ),

          decoration:
              BoxDecoration(

            color: _gold,

            borderRadius:
                BorderRadius.circular(
                    14),

            boxShadow: [

              BoxShadow(

                color: _gold
                    .withOpacity(
                        0.35),

                blurRadius:
                    16,

                offset:
                    const Offset(
                        0,
                        6),
              ),
            ],
          ),

          child: const Center(

            child: Text(

              'BOOK NOW',

              style: TextStyle(

                color:
                    Colors.black,

                fontSize:
                    16,

                fontWeight:
                    FontWeight
                        .w900,

                letterSpacing:
                    1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

