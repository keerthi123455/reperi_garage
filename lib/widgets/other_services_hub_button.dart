import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Round yellow "Other Reperi Services" hub button (Home, bottom-left).
///
/// A yellow circle with the navy spanner that hops, wiggles, sends out a
/// ripple and gets a light sweep every few seconds, with little sparkles
/// around it. Tapped, it grows into the 16:9 banner
/// (`assets/images/other_reperi_services_banner_16x9.jpeg`) while the screen
/// behind blurs. Tapping the banner calls [onOpen] (opens the Other
/// Services screen). Tap outside, the close button, or Back shrinks it back.
class OtherServicesHubButton extends StatefulWidget {
  const OtherServicesHubButton({super.key, required this.onOpen});

  /// Called after the banner closes itself, when the banner was tapped.
  final VoidCallback onOpen;

  static const String imagePath = 'assets/images/other_reperi_services_banner_16x9.jpeg';
  static const double bannerAspect = 16 / 9;

  @override
  State<OtherServicesHubButton> createState() => _OtherServicesHubButtonState();
}

const Color _yellow = Color(0xFFFDF003);
const Color _navy = Color(0xFF022B57);

class _OtherServicesHubButtonState extends State<OtherServicesHubButton> with TickerProviderStateMixin {
  static const double _size = 62;

  bool _open = false;

  late final AnimationController _attention =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4600))..repeat();
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  late final AnimationController _twinkle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the banner now so it opens without a flash.
    precacheImage(const AssetImage(OtherServicesHubButton.imagePath), context, onError: (_, __) {});
  }

  @override
  void dispose() {
    _attention.dispose();
    _glow.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  Future<void> _openBanner() async {
    final box = context.findRenderObject() as RenderBox?;
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlayBox = navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    // The circle itself (the box is a bit taller for the bounce room).
    final origin = Rect.fromLTWH(topLeft.dx, topLeft.dy + box.size.height - _size, _size, _size);

    setState(() => _open = true);
    final go = await navigator.push<bool>(_BannerRoute(origin: origin));
    if (!mounted) return;
    setState(() => _open = false);
    if (go == true) widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Opacity(
      opacity: _open ? 0 : 1,
      child: Semantics(
        button: true,
        label: 'Other Reperi Services',
        child: GestureDetector(
          onTap: _openBanner,
          child: SizedBox(
            width: _size,
            height: _size + 12, // room for the hop
            child: AnimatedBuilder(
              animation: _attention,
              builder: (context, child) {
                final v = reduceMotion ? 0.9 : _attention.value;
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Transform.translate(
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
                  ),
                );
              },
              child: _bubble(reduceMotion),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(bool reduceMotion) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Ripple each time it lands.
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _attention,
              builder: (_, __) {
                final p = _ripple(_attention.value);
                if (p == null) return const SizedBox.shrink();
                return Transform.scale(
                  scale: 1 + 0.8 * Curves.easeOutCubic.transform(p),
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _yellow.withOpacity(0.85 * (1 - p)), width: 3 * (1 - p) + 0.5),
                    ),
                  ),
                );
              },
            ),
          // Breathing glow + the yellow disc with the spanner.
          AnimatedBuilder(
            animation: _glow,
            builder: (_, child) => Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _yellow,
                border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _yellow.withOpacity(0.35 + 0.3 * _glow.value),
                    blurRadius: 14 + 12 * _glow.value,
                    spreadRadius: 1 + 3 * _glow.value,
                  ),
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
                ],
              ),
              child: child,
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Center(child: _Spanner(size: 34)),
                  if (!reduceMotion)
                    AnimatedBuilder(
                      animation: _attention,
                      builder: (_, __) {
                        final p = _shine(_attention.value);
                        if (p == null) return const SizedBox.shrink();
                        return Transform.translate(
                          offset: Offset(-_size + 2 * _size * p, 0),
                          child: Transform.rotate(
                            angle: 0.5,
                            child: Center(
                              child: Container(
                                width: 16,
                                height: _size * 1.8,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    Colors.white.withOpacity(0),
                                    Colors.white.withOpacity(0.9),
                                    Colors.white.withOpacity(0),
                                  ]),
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
          if (!reduceMotion) ..._sparkles(),
        ],
      ),
    );
  }

  List<Widget> _sparkles() {
    const spots = [
      // left, top, size, phase
      (-8.0, -6.0, 13.0, 0.0),
      (_size - 2, 2.0, 9.0, 0.35),
      (_size - 6, _size - 10, 8.0, 0.68),
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
                final o = w * w;
                return Opacity(
                  opacity: o,
                  child: Transform.rotate(
                    angle: o * 0.8,
                    child: Transform.scale(
                      scale: 0.4 + 0.6 * o,
                      child: CustomPaint(size: Size.square(size), painter: _SparklePainter()),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ];
  }

  // One 4.6 s cycle: hop · bounce · wiggle · ripple · shine · rest.
  static double _hop(double v) {
    const h = 11.0;
    if (v < 0.08) return -h * Curves.easeOutCubic.transform(v / 0.08);
    if (v < 0.22) return -h * (1 - Curves.bounceOut.transform((v - 0.08) / 0.14));
    return 0;
  }

  static double _wiggle(double v) {
    if (v < 0.22 || v >= 0.40) return 0;
    final p = (v - 0.22) / 0.18;
    return math.sin(p * math.pi * 4) * 0.22 * (1 - p);
  }

  static double? _ripple(double v) => (v < 0.17 || v >= 0.55) ? null : (v - 0.17) / 0.38;

  static double? _shine(double v) =>
      (v < 0.42 || v >= 0.62) ? null : Curves.easeInOutCubic.transform((v - 0.42) / 0.20);

  static double _squash(double v) {
    if (v < 0.17 || v >= 0.24) return 1;
    return 1 + 0.07 * math.sin((v - 0.17) / 0.07 * math.pi);
  }
}

/// The navy spanner from the banner, drawn in code.
class _Spanner extends StatelessWidget {
  const _Spanner({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SpannerPainter());
}

class _SpannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Same shape as the banner's SVG (100×100 box, rotated 45°).
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);
    canvas.translate(50, 50);
    canvas.rotate(math.pi / 4);
    canvas.translate(-50, -50);
    final navy = Paint()..color = _navy;
    canvas.drawCircle(const Offset(50, 22), 17, navy);
    canvas.drawPath(
      Path()
        ..moveTo(43, 34)
        ..lineTo(57, 34)
        ..lineTo(56, 44)
        ..lineTo(44, 44)
        ..close(),
      navy,
    );
    canvas.drawRRect(RRect.fromLTRBR(44, 40, 56, 94, const Radius.circular(6)), navy);
    // Jaw cut-out.
    canvas.drawPath(
      Path()
        ..moveTo(43.5, 0)
        ..lineTo(56.5, 0)
        ..lineTo(56.5, 19)
        ..quadraticBezierTo(56.5, 25, 50, 25)
        ..quadraticBezierTo(43.5, 25, 43.5, 19)
        ..close(),
      Paint()..color = _yellow,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
        ..color = const Color(0xFFFFF59D).withOpacity(0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Grows the circle into the banner over a blurred backdrop.
/// Pops `true` when the banner is tapped.
class _BannerRoute extends PageRouteBuilder<bool> {
  _BannerRoute({required Rect origin})
      : super(
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 560),
          reverseTransitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (context, animation, _) => _BannerView(animation: animation, origin: origin),
        );
}

class _BannerView extends StatefulWidget {
  const _BannerView({required this.animation, required this.origin});

  final Animation<double> animation;
  final Rect origin;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView> {
  late final CurvedAnimation curved =
      CurvedAnimation(parent: widget.animation, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);

  Rect get origin => widget.origin;

  @override
  void dispose() {
    curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final screen = constraints.biggest;
      final pad = MediaQuery.of(context).padding;
      final width = math.min(screen.width - 28, 560.0);
      final height = width / OtherServicesHubButton.bannerAspect;
      final target = Rect.fromCenter(
        center: Offset(screen.width / 2, pad.top + (screen.height - pad.vertical) / 2),
        width: width,
        height: height,
      );

      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) {
          final t = curved.value;
          final rect = Rect.lerp(origin, target, t)!;
          // Circle → rounded card.
          final radius = ui.lerpDouble(origin.width / 2, 22, t)!;
          final contentOpacity = ((t - 0.35) / 0.4).clamp(0.0, 1.0);
          final controls = ((t - 0.7) / 0.3).clamp(0.0, 1.0);

          // Material: gives the texts a proper style (this route has none).
          return Material(
            type: MaterialType.transparency,
            child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(false),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
                    child: ColoredBox(color: Colors.black.withOpacity(0.45 * t)),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: GestureDetector(
                  onTap: t > 0.95 ? () => Navigator.of(context).pop(true) : null,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _yellow,
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
                          // While still small it's just the yellow disc + spanner.
                          Opacity(
                            opacity: 1 - contentOpacity,
                            child: const Center(child: _Spanner(size: 34)),
                          ),
                          Opacity(
                            opacity: contentOpacity,
                            child: Image.asset(
                              OtherServicesHubButton.imagePath,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text('Other Reperi Services',
                                    style: TextStyle(color: _navy, fontSize: 24, fontWeight: FontWeight.w900)),
                              ),
                            ),
                          ),
                          // Close (top-right).
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Opacity(
                              opacity: controls,
                              child: IgnorePointer(
                                ignoring: controls < 0.5,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).maybePop(false),
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _navy.withOpacity(0.12),
                                    ),
                                    child: const Icon(Icons.close_rounded, color: _navy, size: 20),
                                  ),
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
              // Hint under the banner.
              Positioned(
                left: 0,
                right: 0,
                top: target.bottom + 18,
                child: Opacity(
                  opacity: controls,
                  child: const Center(
                    child: Text('Tap the banner to see all services',
                        style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
          );
        },
      );
    });
  }
}
