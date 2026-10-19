import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
/// Looks: a gold-ringed circle that gently hops and wiggles every few
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
  static const double _size = 58;
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
          ? const SizedBox(key: ValueKey('off'), width: _size, height: _size)
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
                child: _buildBubble(),
              ),
            ),
    );
  }

  Widget _buildBubble() {
    return Semantics(
      button: true,
      label: 'View current offer',
      child: GestureDetector(
        onTap: _openBanner,
        child: SizedBox(
          width: _size,
          height: _size + 10,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Breathing gold glow.
              AnimatedBuilder(
                animation: _glow,
                builder: (_, __) => Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
              // Gold ring + the banner itself, cropped into the circle.
              Container(
                width: _size,
                height: _size,
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Color(0xFFFFE08A),
                      _gold,
                      Color(0xFFB8860B),
                      _gold,
                      Color(0xFFFFE08A),
                    ],
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    OfferHubButton.imagePath,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
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

  /// Tiny squash just as it lands, so the hop feels physical.
  static double _squash(double v) {
    if (v < 0.17 || v >= 0.24) return 1;
    final p = (v - 0.17) / 0.07;
    return 1 + 0.06 * math.sin(p * math.pi);
  }
}

/// Transparent route that grows the banner out of the button and blurs the
/// Home screen behind it. Closing (X button, tapping outside, or Back)
/// plays it in reverse, shrinking the card back into the button.
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

class _OfferBannerView extends StatelessWidget {
  const _OfferBannerView({
    required this.animation,
    required this.origin,
    required this.aspect,
  });

  final Animation<double> animation;
  final Rect origin;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final padding = MediaQuery.of(context).padding;

        // Final card: as wide as the screen allows (max 460), shaped exactly
        // like the banner image, never taller than 78% of the screen.
        var width = math.min(screen.width - 32, 460.0);
        var height = width / aspect;
        final maxHeight = (screen.height - padding.vertical) * 0.78;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * aspect;
        }
        final target = Rect.fromCenter(
          center: Offset(screen.width / 2,
              padding.top + (screen.height - padding.vertical) / 2),
          width: width,
          height: height,
        );

        return AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            final t = curved.value;
            final rect = Rect.lerp(origin, target, t)!;
            final radius = ui.lerpDouble(origin.shortestSide / 2, 26, t)!;
            final controlsOpacity = ((t - 0.65) / 0.35).clamp(0.0, 1.0);

            return Stack(
              children: [
                // Blurred, dimmed Home screen. Tap anywhere outside to close.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 16 * t,
                        sigmaY: 16 * t,
                      ),
                      child: ColoredBox(
                        color: Colors.black.withOpacity(0.45 * t),
                      ),
                    ),
                  ),
                ),

                // The card, growing from the button.
                Positioned.fromRect(
                  rect: rect,
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
                          // Round glass close button, top-left (like the
                          // reference design), fades in as the card lands.
                          Positioned(
                            top: 14,
                            left: 14,
                            child: Opacity(
                              opacity: controlsOpacity,
                              child: IgnorePointer(
                                ignoring: controlsOpacity < 0.5,
                                child: _CloseButton(
                                  onTap: () => Navigator.of(context).maybePop(),
                                ),
                              ),
                            ),
                          ),
                        ],
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
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.28),
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
