import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offer_booking_sheet.dart';

/// Floating "offer" hub on the Home screen (app + website).
///
/// Switched on/off from Supabase WITHOUT an app update:
///   Table Editor → `offer_banner_control` → the single row's `status`
///     SHOW      → the round button appears on Home
///     DONTSHOW  → it's hidden (anything other than SHOW also hides it)
/// Checked every time Home opens and whenever the app comes back to the
/// foreground, so turning it off takes effect on the customer's next open.
///
/// The banner itself is `assets/images/offer_banner.jpeg` (swap the file to
/// change the offer). If that file is missing, the button never shows.
///
/// Looks: a gold-ringed rounded card that gently hops and wiggles every few
/// seconds to invite a tap. Tapped, it smoothly grows into the full banner
/// card while the Home screen behind blurs out; closing shrinks it back into
/// the button.
class OfferHubButton extends StatefulWidget {
  const OfferHubButton({super.key});

  static const String imagePath = 'assets/images/offer_banner.jpeg';

  @override
  State<OfferHubButton> createState() => _OfferHubButtonState();
}

class _OfferHubButtonState extends State<OfferHubButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // A small rounded "poster" of the offer banner (was a 64px circle).
  static const double _w = 84;
  static const double _h = 118;
  static const double _r = 20; // corner radius
  static const Color _gold = Color(0xFFD4A017);

  bool _enabled = false; // status == SHOW in Supabase
  double? _imageAspect; // width / height, once the banner image has loaded
  bool _open = false; // banner currently expanded

  late final AnimationController _attention = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  // Slowly turning gold ring, so the edge always glints.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5000),
  )..repeat();

  // Sparkles twinkling around the button.
  late final AnimationController _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadImage();
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attention.dispose();
    _glow.dispose();
    _spin.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final row = await Supabase.instance.client
          .from('offer_banner_control')
          .select('status')
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      final show =
          (row?['status'] ?? '').toString().trim().toUpperCase() == 'SHOW';
      if (mounted && show != _enabled) setState(() => _enabled = show);
    } catch (_) {
      // Offline / table missing: keep whatever we had (hidden by default).
    }
  }

  /// Loads the banner once to learn its shape (so the expanded card matches
  /// it exactly) and to have it decoded before the first tap.
  void _loadImage() {
    final stream =
        const AssetImage(OfferHubButton.imagePath).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (mounted && w > 0 && h > 0) setState(() => _imageAspect = w / h);
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener), // no file → no button
    );
    stream.addListener(listener);
  }

  Future<void> _openBanner() async {
    final aspect = _imageAspect;
    final box = context.findRenderObject() as RenderBox?;
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlayBox =
        navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (aspect == null || box == null || !box.hasSize) return;

    // The button's position in the same coordinate space the banner route
    // is drawn in (correct on the website's framed/scaled layouts too).
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final origin = topLeft & box.size;

    setState(() => _open = true);
    await navigator.push(_OfferBannerRoute(origin: origin, aspect: aspect));
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _enabled && _imageAspect != null;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: !visible
          ? const SizedBox(key: ValueKey('off'), width: _w, height: _h)
          : Opacity(
              key: const ValueKey('on'),
              // Hidden while expanded: the banner card IS the button then.
              opacity: _open ? 0 : 1,
              child: AnimatedBuilder(
                animation: Listenable.merge([_attention, _glow]),
                builder: (context, child) {
                  final v = reduceMotion ? 0.9 : _attention.value;
                  return Transform.translate(
                    offset: Offset(0, _hop(v)),
                    child: Transform.rotate(
                      angle: _wiggle(v),
                      child: Transform.scale(
                        scaleX: _squash(v),
                        scaleY: 2 - _squash(v),
                        alignment: Alignment.bottomCenter,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildBubble(reduceMotion),
              ),
            ),
    );
  }

  Widget _buildBubble(bool reduceMotion) {
    return Semantics(
      button: true,
      label: 'View current offer',
      child: GestureDetector(
        onTap: _openBanner,
        child: SizedBox(
          width: _w,
          height: _h + 10,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Gold "ping" ripple that spreads out each time it lands.
              if (!reduceMotion)
                AnimatedBuilder(
                  animation: _attention,
                  builder: (_, __) {
                    final p = _ripple(_attention.value);
                    if (p == null) return const SizedBox.shrink();
                    return Transform.scale(
                      scale: 1 + 0.75 * Curves.easeOutCubic.transform(p),
                      child: Container(
                        width: _w,
                        height: _h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_r),
                          border: Border.all(
                            color: _gold.withOpacity(0.7 * (1 - p)),
                            width: 2.5 * (1 - p) + 0.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Breathing gold glow.
              AnimatedBuilder(
                animation: _glow,
                builder: (_, __) => Container(
                  width: _w,
                  height: _h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_r),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withOpacity(0.25 + 0.25 * _glow.value),
                        blurRadius: 14 + 10 * _glow.value,
                        spreadRadius: 1 + 2 * _glow.value,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
              ),

              // Turning gold ring + the banner itself, cropped into the circle,
              // with a bright shine that sweeps across it.
              AnimatedBuilder(
                animation: _spin,
                builder: (_, child) => Container(
                  width: _w,
                  height: _h,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_r),
                    gradient: SweepGradient(
                      transform: GradientRotation(
                          reduceMotion ? 0 : _spin.value * 2 * math.pi),
                      colors: const [
                        Color(0xFFFFF4C2),
                        _gold,
                        Color(0xFF9C7208),
                        _gold,
                        Color(0xFFFFF4C2),
                      ],
                    ),
                  ),
                  child: child,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_r - 2.5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        OfferHubButton.imagePath,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
                      if (!reduceMotion)
                        AnimatedBuilder(
                          animation: _attention,
                          builder: (_, __) {
                            final p = _shine(_attention.value);
                            if (p == null) return const SizedBox.shrink();
                            // A diagonal band of light gliding left → right.
                            return Transform.translate(
                              offset: Offset(-_w + 2 * _w * p, 0),
                              child: Transform.rotate(
                                angle: 0.45,
                                child: Center(
                                  child: Container(
                                    width: 20,
                                    height: _h * 1.8,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0),
                                          Colors.white.withOpacity(0.85),
                                          Colors.white.withOpacity(0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),

              // Twinkling sparkles around the button.
              if (!reduceMotion) ..._sparkles(),

              // Small "OFFER" tag.
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE0B02A), Color(0xFFB8860B)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    'OFFER',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: const Color(0xFF15120A),
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

  /// Three little four-point stars that twinkle in turn around the button.
  List<Widget> _sparkles() {
    const spots = [
      // left, top, size, phase
      (-6.0, -6.0, 13.0, 0.0),
      (_w - 4, 4.0, 9.0, 0.35),
      (-10.0, _h * 0.55, 8.0, 0.68),
    ];
    return [
      for (final (left, top, size, phase) in spots)
        Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _twinkle,
              builder: (_, __) {
                final w = math.sin(((_twinkle.value + phase) % 1.0) * math.pi);
                final o = w * w; // sharp on, soft off
                return Opacity(
                  opacity: o,
                  child: Transform.rotate(
                    angle: o * 0.8,
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * o,
                      child: CustomPaint(
                        size: Size.square(size),
                        painter: _SparklePainter(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ];
  }

  // ── Attention animation (one 4.2s cycle, mostly resting) ──────────────
  // 0.00–0.08 hop up · 0.08–0.22 drop with a soft bounce · 0.22–0.40
  // wiggle that fades out · then rests until the next cycle.

  static double _hop(double v) {
    const height = 9.0;
    if (v < 0.08) return -height * Curves.easeOutCubic.transform(v / 0.08);
    if (v < 0.22) {
      return -height * (1 - Curves.bounceOut.transform((v - 0.08) / 0.14));
    }
    return 0;
  }

  static double _wiggle(double v) {
    if (v < 0.22 || v >= 0.40) return 0;
    final p = (v - 0.22) / 0.18;
    return math.sin(p * math.pi * 4) * 0.16 * (1 - p);
  }

  /// Ripple progress 0→1 starting as it lands, else null.
  static double? _ripple(double v) {
    if (v < 0.17 || v >= 0.55) return null;
    return (v - 0.17) / 0.38;
  }

  /// Shine sweep progress 0→1 after the wiggle, else null.
  static double? _shine(double v) {
    if (v < 0.42 || v >= 0.62) return null;
    return Curves.easeInOutCubic.transform((v - 0.42) / 0.20);
  }

  /// Tiny squash just as it lands, so the hop feels physical.
  static double _squash(double v) {
    if (v < 0.17 || v >= 0.24) return 1;
    final p = (v - 0.17) / 0.07;
    return 1 + 0.06 * math.sin(p * math.pi);
  }
}

/// Transparent route that grows the banner out of the button and blurs the
/// Home screen behind it. Tapping the banner opens a 3D carousel of offer
/// cards. Closing (X, the banner's close button, tapping outside the banner,
/// or Back) fades everything away back to the Home screen.
class _OfferBannerRoute extends PageRouteBuilder<void> {
  _OfferBannerRoute({required Rect origin, required double aspect})
      : super(
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 560),
          reverseTransitionDuration: const Duration(milliseconds: 440),
          pageBuilder: (context, animation, _) =>
              _OfferBannerView(animation: animation, origin: origin, aspect: aspect),
        );
}

/// One card in the offer carousel.
class _OfferCard {
  const _OfferCard(this.image, this.title, this.serviceKey, this.price);
  final String image;
  final String title;
  /// Row in the Supabase `services` table — the server charges ITS price.
  final String serviceKey;
  /// Shown only until the server's price loads.
  final int price;
}

/// The cards shown after tapping the banner. To change them, swap these
/// images in assets/images (same names), or edit this list.
const List<_OfferCard> _offerCards = [
  _OfferCard('assets/images/bucket_wash.jpeg', 'Bucket Wash', 'offer_bucket_wash', 1),
  _OfferCard('assets/images/shampoo_wash.jpeg', 'Shampoo Wash', 'offer_shampoo_wash', 199),
  _OfferCard('assets/images/full_cleaning.jpeg', 'Complete Wash', 'offer_complete_wash', 999),
];

class _OfferBannerView extends StatefulWidget {
  const _OfferBannerView({
    required this.animation,
    required this.origin,
    required this.aspect,
  });

  final Animation<double> animation;
  final Rect origin;
  final double aspect;

  @override
  State<_OfferBannerView> createState() => _OfferBannerViewState();
}

class _OfferBannerViewState extends State<_OfferBannerView>
    with SingleTickerProviderStateMixin {
  /// 0 = banner showing, 1 = 3D card carousel showing.
  late final AnimationController _stage = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  final PageController _pages = PageController(viewportFraction: 0.74);
  int _current = 0;

  late final CurvedAnimation _curved = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutQuart,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the card images now, so the carousel opens without a flicker.
    for (final card in _offerCards) {
      precacheImage(AssetImage(card.image), context, onError: (_, __) {});
    }
  }

  @override
  void dispose() {
    _stage.dispose();
    _pages.dispose();
    _curved.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _showCards() {
    if (_stage.status == AnimationStatus.dismissed) _stage.forward();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final padding = MediaQuery.of(context).padding;
        final usableHeight = screen.height - padding.vertical;

        // Banner card: as wide as the screen allows (max 460), shaped exactly
        // like the banner image, never taller than 78% of the screen.
        var width = math.min(screen.width - 32, 460.0);
        var height = width / widget.aspect;
        final maxHeight = usableHeight * 0.78;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * widget.aspect;
        }
        final target = Rect.fromCenter(
          center: Offset(screen.width / 2, padding.top + usableHeight / 2),
          width: width,
          height: height,
        );

        // Carousel cards: 9:16 like the 720x1280 images, narrow enough that
        // the neighbouring cards peek in at the sides.
        var cardWidth = math.min(screen.width * 0.74 - 24, 300.0);
        var cardHeight = cardWidth * 16 / 9;
        if (cardHeight > usableHeight * 0.72) {
          cardHeight = usableHeight * 0.72;
          cardWidth = cardHeight * 9 / 16;
        }

        return AnimatedBuilder(
          animation: Listenable.merge([_curved, _stage]),
          builder: (context, _) {
            final t = _curved.value; // route open/close
            final s = Curves.easeInOutCubic.transform(_stage.value); // banner → cards
            final rect = Rect.lerp(widget.origin, target, t)!;
            final radius = ui.lerpDouble(18, 26, t)!;
            final controlsOpacity =
                ((t - 0.65) / 0.35).clamp(0.0, 1.0) * (1 - s);

            // Every layer below has a KEY: layers appear/disappear during the
            // banner → cards switch, and without keys Flutter could reuse the
            // wrong slot for the carousel, attaching the PageController twice
            // ("ScrollController attached to multiple scroll views").
            return Stack(
              children: [
                // Blurred, dimmed Home screen. While the banner shows, tap
                // outside to close; in the carousel only the X closes, so a
                // stray tap while swiping doesn't throw people out.
                Positioned.fill(
                  key: const ValueKey('offer-backdrop'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _stage.value == 0 ? _close : null,
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 16 * t + 6 * s,
                        sigmaY: 16 * t + 6 * s,
                      ),
                      child: ColoredBox(
                        color: Colors.black.withOpacity(0.45 * t + 0.15 * s * t),
                      ),
                    ),
                  ),
                ),

                // The banner: grows from the button; tap it to see the cards.
                if (s < 1)
                  Positioned.fromRect(
                    key: const ValueKey('offer-banner'),
                    rect: rect,
                    child: Opacity(
                      opacity: 1 - s,
                      child: Transform.scale(
                        scale: 1 - 0.18 * s,
                        child: GestureDetector(
                          onTap: t > 0.95 ? _showCards : null,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(radius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.45 * t),
                                  blurRadius: 40 * t,
                                  offset: Offset(0, 18 * t),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(
                                    OfferHubButton.imagePath,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                  ),
                                  // Close (top-left), fades in as the card lands.
                                  Positioned(
                                    top: 14,
                                    left: 14,
                                    child: Opacity(
                                      opacity: controlsOpacity,
                                      child: IgnorePointer(
                                        ignoring: controlsOpacity < 0.5,
                                        child: _CloseButton(onTap: _close),
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
                  ),

                // The 3D card carousel.
                if (s > 0)
                  Positioned.fill(
                    key: const ValueKey('offer-cards'),
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: cardHeight + 40,
                            child: PageView.builder(
                              controller: _pages,
                              itemCount: _offerCards.length,
                              physics: const BouncingScrollPhysics(),
                              onPageChanged: (i) => setState(() => _current = i),
                              itemBuilder: (context, i) => _carouselCard(
                                i,
                                s,
                                cardWidth,
                                cardHeight,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Page dots.
                          Opacity(
                            opacity: _cardEntry(s, 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < _offerCards.length; i++)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: i == _current ? 22 : 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: i == _current
                                          ? const Color(0xFFD4A017)
                                          : Colors.white.withOpacity(0.45),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // X (top-right) — back to the Home screen.
                if (s > 0)
                  Positioned(
                    key: const ValueKey('offer-close'),
                    top: padding.top + 14,
                    right: 16,
                    child: Opacity(
                      opacity: (s * t).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: (1 - s) * -math.pi / 2,
                        child: _CloseButton(
                          onTap: _close,
                          icon: Icons.close_rounded,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// Apartment + payment popup for card [i]. After a successful booking,
  /// close the offer screens and return to Home.
  Future<void> _openBooking(int i) async {
    final card = _offerCards[i];
    final booked = await showOfferBookingSheet(
      context,
      image: card.image,
      title: card.title,
      serviceKey: card.serviceKey,
      fallbackPrice: card.price,
    );
    if (booked && mounted) _close();
  }

  /// Staggered entry for carousel item [i] (0..1) as the stage opens.
  static double _cardEntry(double s, int i) {
    final start = 0.25 + 0.12 * i;
    return ((s - start) / 0.45).clamp(0.0, 1.0);
  }

  Widget _carouselCard(int i, double s, double w, double h) {
    return AnimatedBuilder(
      animation: _pages,
      builder: (context, _) {
        // How far this card is from the centre (0 = in front).
        double page = _current.toDouble();
        if (_pages.positions.length == 1 && _pages.position.haveDimensions) {
          page = _pages.page ?? page;
        }
        final diff = (i - page).clamp(-1.5, 1.5);
        final away = diff.abs().clamp(0.0, 1.0);

        final entry = Curves.easeOutBack.transform(_cardEntry(s, i));

        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0014) // perspective
          // Side cards slide in towards the middle so part of the next
          // (and previous) card is always visible.
          ..translate(-diff * w * 0.10, (1 - entry) * 90) // 0.10 = small gap; lower = more gap
          ..rotateY(-diff * 0.55)
          ..scale(1 - 0.14 * away);

        return Center(
          child: Opacity(
            opacity: (_cardEntry(s, i)).clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: transform,
              child: GestureDetector(
                // Front card → booking popup. Side card → slide it to front.
                onTap: () => i == _current ? _openBooking(i) : _pages.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                ),
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45 - 0.2 * away),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          _offerCards[i].image,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          // Image not added yet: show a tidy placeholder.
                          errorBuilder: (_, __, ___) => DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF8FCBFB), Color(0xFFFFFFFF)],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _offerCards[i].title,
                                style: GoogleFonts.manrope(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0E2257),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Side cards sit a little in shadow.
                        IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withOpacity(0.35 * away),
                          ),
                        ),
                        // Thin glass edge.
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.35),
                              ),
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
        );
      },
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.onTap,
    this.icon = Icons.keyboard_arrow_down_rounded,
    this.size = 40,
  });

  final VoidCallback onTap;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close offer',
      child: GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.28),
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              child: Icon(icon, size: size * 0.66, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small glowing four-point star.
class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFE9A8).withOpacity(0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFF8E1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
