import 'package:flutter/material.dart';
import 'payment_screen.dart';
import '../services/catalog_service.dart';

class PaintCareScreen extends StatefulWidget {

  final Map<String, dynamic> vehicle;

  const PaintCareScreen({
    super.key,
    required this.vehicle,
  });

  @override
  State<PaintCareScreen> createState() =>
      _PaintCareScreenState();
}

class _PaintCareScreenState
    extends State<PaintCareScreen> {

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

List<Map<String, dynamic>>
      packages = [

    {

      'title':
          'QUICK POLISH',

      'subtitle':
          'Basic Shine Enhancement',

      'price':
          '₹599',

      'duration':
          '45 mins',

      'icon':
          Icons.auto_awesome_outlined,

      'features': [

        'Exterior wash',

        'Quick buffing',

        'Tyre shine',

        'Water spot removal',

        'Gloss enhancement',
      ],

      'details':
          'Perfect for restoring daily shine and improving overall exterior appearance quickly.',
    },

    {

      'title':
          'SCRATCH CONTROL',

      'subtitle':
          'Scratch & Swirl Correction',

      'price':
          '₹1499',

      'duration':
          '2 hrs',

      'icon':
          Icons.cleaning_services_outlined,

      'features': [

        'Scratch removal',

        'Swirl correction',

        'Paint enhancement',

        'Machine buffing',

        'Gloss restoration',
      ],

      'details':
          'Designed to remove minor scratches, swirl marks and restore paint smoothness.',
    },

    {

      'title':
          'RUST CONTROL',

      'subtitle':
          'Anti-Rust Protection',

      'price':
          '₹2999',

      'duration':
          '3 hrs',

      'icon':
          Icons.shield_outlined,

      'features': [

        'Underbody coating',

        'Rust treatment',

        'Corrosion prevention',

        'Protective sealant',

        'Metal protection layer',
      ],

      'details':
          'Advanced anti-rust treatment protecting your vehicle body from corrosion and damage.',
    },

    {

      'title':
          'PREMIUM PAINT RESTORE',

      'subtitle':
          'Paint Correction & Restoration',

      'price':
          '₹4999',

      'duration':
          '5 hrs',

      'icon':
          Icons.format_paint_outlined,

      'features': [

        'Paint correction',

        'Multi-stage polishing',

        'Deep gloss enhancement',

        'Oxidation removal',

        'Premium machine finish',
      ],

      'details':
          'Restores dull paint, oxidation and faded surfaces back to premium glossy finish.',
    },

    {

      'title':
          'VINYL & WRAP STUDIO',

      'subtitle':
          'Exterior Customization',

      'price':
          '₹7999',

      'duration':
          '1 day',

      'icon':
          Icons.layers_outlined,

      'features': [

        'Vinyl wrap installation',

        'Gloss/matte finish',

        'Roof wrap',

        'Mirror accents',

        'Color customization',

        'Paint-safe removal',
      ],

      'details':
          'Premium wrapping solutions for luxury styling, customization and exterior transformation.',
    },

    {

      'title':
          'SHOWROOM SHINE+',

      'subtitle':
          'Luxury Exterior Restoration',

      'price':
          '₹10999',

      'duration':
          '2 days',

      'icon':
          Icons.diamond_outlined,

      'features': [

        'Ceramic coating',

        'Deep detailing',

        'Paint refinement',

        'Hydrophobic protection',

        'Luxury polishing',

        'Exterior rejuvenation',

        'PPF enhancement',
      ],

      'details':
          'Ultimate luxury package delivering showroom-level shine, protection and exterior perfection.',
},
  ];

  @override
  void initState() {
    super.initState();
    _fetchPackageData();
  }

  Future<void> _fetchPackageData() async {
    try {
      final rows = await CatalogService.fetchByCategory('Paint Care');
      if (!mounted) return;

      final byKey = {for (final row in rows) row['key'] as String: row};

      const keyOrder = [
        'paint_quick_polish',
        'paint_scratch_control',
        'paint_rust_control',
        'paint_premium_restore',
        'paint_vinyl_wrap_studio',
        'paint_showroom_shine_plus',
      ];

      setState(() {
        for (var i = 0; i < keyOrder.length && i < packages.length; i++) {
          final row = byKey[keyOrder[i]];
          if (row != null) {
            packages[i]['price'] = row['price'];
            packages[i]['duration'] = row['duration'];
            packages[i]['details'] = row['details'] ?? packages[i]['details'];
            packages[i]['features'] = List<String>.from(row['services']);
          }
        }
      });
    } catch (e) {
      // Keep the hardcoded fallback values above if the fetch fails.
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: _bg,

      body:
          SingleChildScrollView(

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment
                  .start,

          children: [

            _buildHero(),

            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

            _buildPackages(),

            _buildWhyUs(),

            _buildTracking(),

            _buildBottomCTA(),

            const SizedBox(
                height: 30),
                  ],
                ),
              ),
            ),
          ],
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

            'assets/images/tile_detailing.jpg',

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

                  'PAINT',

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

                  'CARE',

                  style: TextStyle(

                    color:
                        _gold,

                    fontSize: 58,

                    fontWeight:
                        FontWeight.w900,

                    height: 1,
                  ),
                ),

                const SizedBox(
                    height: 16),

                const Text(

                  'Luxury exterior restoration, protection and finish enhancement.',

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

                        'PREMIUM EXTERIOR STUDIO',

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

                        'Advanced polishing, ceramic coating, wraps, PPF and luxury paint restoration using premium-grade products.',

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

            'EXTERIOR PACKAGES',

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
            .verified_outlined,

        'Paint-safe\nProducts',
      ),

      (

        Icons
            .shield_outlined,

        'Imported\nCoatings',
      ),

      (

        Icons
            .diamond_outlined,

        'OEM\nFinish',
      ),

      (

        Icons
            .engineering_outlined,

        'Certified\nDetailers',
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

  Widget _buildTracking() {

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

                      'Process Updates',
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

                      'Exterior Inspection',
                    ),

                    const SizedBox(
                        height:
                            10),

                    _trackItem(

                      Icons
                          .history_outlined,

                      'Digital Service History',
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

