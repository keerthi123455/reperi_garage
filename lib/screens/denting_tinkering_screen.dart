
import 'package:flutter/material.dart';
import 'payment_screen.dart';

class DentingTinkeringScreen extends StatefulWidget {

  final Map<String, dynamic> vehicle;

  const DentingTinkeringScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<DentingTinkeringScreen> createState() =>
      _DentingTinkeringScreenState();
}

class _DentingTinkeringScreenState
    extends State<DentingTinkeringScreen> {

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

  int selectedPackage = -1;

  final List<Map<String, dynamic>>
      packages = [

    {

      'title':
          'BASIC INSPECTION',

      'subtitle':
          'Damage Assessment & Estimate',

      'price':
          '₹99',

      'duration':
          '20 mins',

      'icon':
          Icons.search,

      'features': [

        'Dent inspection',

        'Paint damage check',

        'Panel alignment check',

        'Repair estimate',

        'Insurance guidance',
      ],

      'details':
          'Professional inspection and repair consultation for dents, scratches, and accident damage.',
    },

    {

      'title':
          'QUICK DENT FIX',

      'subtitle':
          'Minor Dent & Scratch Repair',

      'price':
          '₹1499',

      'duration':
          '2 hrs',

      'icon':
          Icons.build_circle_outlined,

      'features': [

        'Minor dent removal',

        'Scratch correction',

        'Panel finishing',

        'Basic touch-up',

        'FREE inspection',

        'FREE polish',
      ],

      'details':
          'Perfect for small dents and scratches caused by daily driving and parking incidents.',
    },

    {

      'title':
          'PANEL RESTORE',

      'subtitle':
          'Single Panel Restoration',

      'price':
          '₹3999',

      'duration':
          '5 hrs',

      'icon':
          Icons.car_repair_outlined,

      'features': [

        'Deep dent repair',

        'Paint blending',

        'Panel reshaping',

        'Machine polishing',

        'FREE inspection',

        'FREE polish',
      ],

      'details':
          'Advanced restoration package focused on restoring damaged doors, bumpers, and side panels.',
    },

    {

      'title':
          'BODY LINE CORRECTION',

      'subtitle':
          'Multi-Panel Alignment',

      'price':
          '₹4999',

      'duration':
          '6 hrs',

      'icon':
          Icons.auto_fix_high_outlined,

      'features': [

        'Multi-panel correction',

        'Bumper alignment',

        'Precision reshaping',

        'Machine finishing',

        'Paint refinement',

        'FREE inspection',

        'FREE polish',
      ],

      'details':
          'Premium body correction service for restoring factory body lines and alignment.',
    },

    {

      'title':
          'ACCIDENT RESTORATION',

      'subtitle':
          'Major Damage Recovery',

      'price':
          '₹7999',

      'duration':
          '1 day',

      'icon':
          Icons.car_crash_outlined,

      'features': [

        'Structural correction',

        'Deep restoration',

        'Paint correction',

        'Body alignment',

        'Insurance assistance',

        'FREE inspection',

        'FREE polish',
      ],

      'details':
          'Comprehensive accident repair package for heavily damaged vehicles requiring structural correction.',
    },

    {

      'title':
          'SIGNATURE RESTORATION+',

      'subtitle':
          'Luxury Finish Restoration',

      'price':
          '₹10999',

      'duration':
          '2 days',

      'icon':
          Icons.diamond_outlined,

      'features': [

        'Complete body rejuvenation',

        'Luxury paint finishing',

        'Advanced paint refinement',

        'Ceramic finishing',

        'Premium detailing',

        'Insurance support',

        'FREE inspection',

        'FREE polish',
      ],

      'details':
          'Ultimate showroom-level restoration package with luxury finishing and advanced detailing.',
    },
  ];

  @override
  Widget build(BuildContext context) {

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

            _buildPackages(),

            _buildWhyUs(),

            _buildLiveTracking(),

            _buildBottomCTA(),

            const SizedBox(height: 30),
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

          height: 420,
          width: double.infinity,

          child: Image.asset(

            'assets/images/tile_denting.jpg',

            fit: BoxFit.cover,
          ),
        ),

        Container(

          height: 420,

          decoration:
              BoxDecoration(

            gradient:
                LinearGradient(

              begin:
                  Alignment.bottomCenter,

              end:
                  Alignment.topCenter,

              colors: [

                Colors.black,

                Colors.black
                    .withOpacity(
                        0.25),
              ],
            ),
          ),
        ),

        SafeArea(

          child: Padding(

            padding:
                const EdgeInsets.all(
                    24),

            child: Column(

              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,

              children: [

                const SizedBox(
                    height: 40),

                const Text(

                  'DENTING &',

                  style: TextStyle(

                    color:
                        _white,

                    fontSize: 34,

                    fontWeight:
                        FontWeight.w300,

                    letterSpacing:
                        4,
                  ),
                ),

                const Text(

                  'TINKERING',

                  style: TextStyle(

                    color:
                        _gold,

                    fontSize: 54,

                    fontWeight:
                        FontWeight.w900,

                    height: 1,
                  ),
                ),

                const SizedBox(
                    height: 16),

                const Text(

                  'Precision body restoration and premium finish repair.',

                  style: TextStyle(

                    color:
                        _white,

                    fontSize: 16,

                    height: 1.6,
                  ),
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

                        'PREMIUM BODY STUDIO',

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

                        'Luxury-grade denting, tinkering, and accident restoration using precision tools and expert craftsmanship.',

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

  Widget _buildPackages() {

    return Padding(

      padding:
          const EdgeInsets.all(
              20),

      child: Column(

        crossAxisAlignment:
            CrossAxisAlignment
                .start,

        children: [

          const Text(

            'RESTORATION PACKAGES',

            style: TextStyle(

              color:
                  _white,

              fontSize: 22,

              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
              height: 18),

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

                child:
                    AnimatedContainer(

                  duration:
                      const Duration(
                          milliseconds:
                              300),

                  margin:
                      const EdgeInsets
                          .only(
                              bottom:
                                  18),

                  padding:
                      const EdgeInsets
                          .all(18),

                  decoration:
                      BoxDecoration(

                    color:
                        _card,

                    borderRadius:
                        BorderRadius.circular(
                            20),

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
                                      12),
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

                                  p['title'],

                                  style:
                                      const TextStyle(

                                    color:
                                        _white,

                                    fontSize:
                                        18,

                                    fontWeight:
                                        FontWeight
                                            .w900,
                                  ),
                                ),

                                const SizedBox(
                                    height:
                                        4),

                                Text(

                                  p['subtitle'],

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

                            p['price'],

                            style:
                                const TextStyle(

                              color:
                                  _gold,

                              fontSize:
                                  24,

                              fontWeight:
                                  FontWeight
                                      .w900,
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
                                            10),

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
                                        10),

                                Expanded(

                                  child:
                                      Text(

                                    f,

                                    style:
                                        const TextStyle(

                                      color:
                                          _white,
                                    ),
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

                        width:
                            double.infinity,

                        padding:
                            const EdgeInsets
                                .all(
                                    18),

                        decoration:
                            BoxDecoration(

                          color: Colors
                              .black
                              .withOpacity(
                                  0.2),

                          borderRadius:
                              BorderRadius.circular(
                                  14),

                          border:
                              Border.all(

                            color: _gold
                                .withOpacity(
                                    0.2),
                          ),
                        ),

                        child:
                            Column(

                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            const Text(

                              'WHAT WE DO',

                              style:
                                  TextStyle(

                                color:
                                    _gold,

                                fontWeight:
                                    FontWeight
                                        .w800,

                                letterSpacing:
                                    2,

                                fontSize:
                                    12,
                              ),
                            ),

                            const SizedBox(
                                height:
                                    12),

                            Text(

                              p['details'],

                              style:
                                  const TextStyle(

                                color:
                                    _white,

                                height:
                                    1.6,

                                fontSize:
                                    14,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(
                          height: 18),

                      Container(

                        width:
                            double.infinity,

                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical:
                              14,
                        ),

                        decoration:
                            BoxDecoration(

                          color: selected

                              ? _gold

                              : Colors
                                  .transparent,

                          borderRadius:
                              BorderRadius.circular(
                                  12),

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
                                      .w900,

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

    final items = [

      (

        Icons
            .construction_outlined,

        'Paint-safe\nTools',
      ),

      (

        Icons
            .verified_user_outlined,

        'Insurance\nSupport',
      ),

      (

        Icons
            .diamond_outlined,

        'OEM\nFinish',
      ),

      (

        Icons
            .engineering_outlined,

        'Expert\nTechnicians',
      ),
    ];

    return Padding(

      padding:
          const EdgeInsets.all(
              20),

      child: Column(

        crossAxisAlignment:
            CrossAxisAlignment
                .start,

        children: [

          const Text(

            'WHY CHOOSE US?',

            style: TextStyle(

              color:
                  _white,

              fontSize: 22,

              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
              height: 24),

          Row(

            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,

            children: items.map(

              (item) {

                return Expanded(

                  child: Column(

                    children: [

                      Container(

                        padding:
                            const EdgeInsets
                                .all(
                                    14),

                        decoration:
                            BoxDecoration(

                          color: _gold
                              .withOpacity(
                                  0.1),

                          shape: BoxShape
                              .circle,

                          border:
                              Border.all(

                            color: _gold
                                .withOpacity(
                                    0.3),
                          ),
                        ),

                        child: Icon(

                          item.$1,

                          color:
                              _gold,

                          size: 24,
                        ),
                      ),

                      const SizedBox(
                          height:
                              10),

                      Text(

                        item.$2,

                        textAlign:
                            TextAlign
                                .center,

                        style:
                            const TextStyle(

                          color:
                              _white,

                          fontSize:
                              11,

                          height:
                              1.4,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTracking() {

    return Container(

      margin:
          const EdgeInsets.all(
              20),

      padding:
          const EdgeInsets.all(
              20),

      decoration:
          BoxDecoration(

        color:
            const Color(
                0xFF161410),

        borderRadius:
            BorderRadius.circular(
                16),

        border: Border.all(

          color: _gold
              .withOpacity(
                  0.3),
        ),
      ),

      child: Column(

        children: [

          const Text(

            'LIVE TRACKING INCLUDED',

            style: TextStyle(

              color:
                  _gold,

              fontSize: 16,

              fontWeight:
                  FontWeight.w800,

              letterSpacing:
                  1.5,
            ),
          ),

          const SizedBox(
              height: 16),

          Row(

            children: [

              Expanded(

                child: Column(

                  children: [

                    _trackItem(

                      Icons
                          .camera_alt_outlined,

                      'Before/After Photos',
                    ),

                    const SizedBox(
                        height:
                            10),

                    _trackItem(

                      Icons
                          .list_alt_outlined,

                      'Repair Progress',
                    ),
                  ],
                ),
              ),

              const SizedBox(
                  width: 16),

              Expanded(

                child: Column(

                  children: [

                    _trackItem(

                      Icons
                          .notifications_outlined,

                      'Real-time Updates',
                    ),

                    const SizedBox(
                        height:
                            10),

                    _trackItem(

                      Icons
                          .history_outlined,

                      'Digital Repair History',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trackItem(
      IconData icon,
      String label) {

    return Row(

      children: [

        Icon(

          icon,

          color:
              _gold,

          size: 18,
        ),

        const SizedBox(
            width: 8),

        Expanded(

          child: Text(

            label,

            style:
                const TextStyle(

              color:
                  _white,

              fontSize:
                  12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomCTA() {

    return Padding(

      padding:
          const EdgeInsets
              .fromLTRB(
                  20,
                  0,
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

            color:
                _gold,

            borderRadius:
                BorderRadius.circular(
                    16),

            boxShadow: [

              BoxShadow(

                color: _gold
                    .withOpacity(
                        0.35),

                blurRadius:
                    18,
              ),
            ],
          ),

          child: const Row(

            mainAxisAlignment:
                MainAxisAlignment
                    .center,

            children: [

              Text(

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
                      2,
                ),
              ),

              SizedBox(
                  width: 10),

              Icon(

                Icons
                    .chevron_right,

                color:
                    Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

