import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/roadside_assistance_screen.dart';

/// Round yellow hub button on Home (the spanner that hops and shines).
///
/// Tapped, it opens a speed-dial: the screen blurs, the spanner turns into
/// a ✕ and three circles spring out around it —
///   • SOS (red)            → [onSos] (Roadside Assistance)
///   • Call (green)         → calls the Reperi line
///   • Other services (blue with the yellow spanner) → grows into the 16:9
///     banner (`assets/images/other_reperi_services_banner_16x9.jpeg`);
///     tapping the banner calls [onOpen] (the Other Services screen).
/// Tap ✕, outside, or Back to close.
class OtherServicesHubButton extends StatefulWidget {
  const OtherServicesHubButton({
    super.key,
    required this.onOpen,
    this.onSos,
    this.phone = '9353094672',
  });

  /// Called after the banner closes itself, when the banner was tapped.
  final VoidCallback onOpen;

  /// SOS circle — open Roadside Assistance.
  final VoidCallback? onSos;

  /// Number the Call circle dials.
  final String phone;

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

  /// Tap on the hub: open the speed-dial, then do what was picked.
  Future<void> _openMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    final navigator = Navigator.of(context, rootNavigator: true);
    final overlayBox = navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    // The circle itself (the box is a bit taller for the bounce room).
    final origin = Rect.fromLTWH(topLeft.dx, topLeft.dy + box.size.height - _size, _size, _size);

    HapticFeedback.lightImpact();
    setState(() => _open = true);
    final pick = await navigator.push<_HubPick>(_HubMenuRoute(origin: origin, hubSize: _size));
    if (!mounted) return;

    switch (pick?.action) {
      case _HubAction.services:
        // The banner grows out of the blue circle that was tapped.
        final go = await navigator.push<bool>(_BannerRoute(origin: pick!.from));
        if (!mounted) return;
        setState(() => _open = false);
        if (go == true) widget.onOpen();
        return;
      case _HubAction.sos:
        setState(() => _open = false);
        if (widget.onSos != null) {
          widget.onSos!();
        } else {
          // Works even if the screen didn't pass onSos.
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoadsideAssistanceScreen()));
        }
        return;
      case _HubAction.call:
        setState(() => _open = false);
        try {
          await launchUrl(Uri(scheme: 'tel', path: widget.phone));
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Call us on ${widget.phone}')));
          }
        }
        return;
      case null:
        setState(() => _open = false);
    }
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
          onTap: _openMenu,
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

/// The spanner from the banner, drawn in code (navy on yellow by default).
class _Spanner extends StatelessWidget {
  const _Spanner({required this.size, this.color = _navy, this.background = _yellow});
  final double size;
  final Color color;

  /// Colour behind the spanner — used for the jaw cut-out.
  final Color background;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SpannerPainter(color, background));
}

class _SpannerPainter extends CustomPainter {
  const _SpannerPainter(this.color, this.background);
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    // Same shape as the banner's SVG (100×100 box, rotated 45°).
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);
    canvas.translate(50, 50);
    canvas.rotate(math.pi / 4);
    canvas.translate(-50, -50);
    final navy = Paint()..color = color;
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
      Paint()..color = background,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpannerPainter old) => old.color != color || old.background != background;
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


// ═══════════════════════════════════════════════════════════════════════
//  Speed-dial (opened by tapping the hub)
// ═══════════════════════════════════════════════════════════════════════

enum _HubAction { sos, call, services }

class _HubPick {
  const _HubPick(this.action, this.from);
  final _HubAction action;

  /// Where the tapped circle was (the banner grows out of it).
  final Rect from;
}

const Color _sosRed = Color(0xFFE5262B);
const Color _callGreen = Color(0xFF1FAA59);
const Color _servicesBlue = Color(0xFF1D5FD6);

class _HubMenuRoute extends PageRouteBuilder<_HubPick> {
  _HubMenuRoute({required Rect origin, required double hubSize})
      : super(
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 520),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, _) =>
              _HubMenuView(animation: animation, origin: origin, hubSize: hubSize),
        );
}

class _HubMenuItem {
  const _HubMenuItem(this.action, this.label, this.angleDeg);
  final _HubAction action;
  final String label;

  /// Direction from the hub (0° = right, 90° = down, 180° = left, 270° = up).
  final double angleDeg;
}

/// Fanned out to the left / up of the hub (it sits at the right edge).
const List<_HubMenuItem> _kHubItems = [
  _HubMenuItem(_HubAction.sos, 'SOS', 270),
  _HubMenuItem(_HubAction.call, 'Call us', 225),
  _HubMenuItem(_HubAction.services, "Not sure what's wrong\nwith your vehicle?", 180),
];

class _HubMenuView extends StatefulWidget {
  const _HubMenuView({required this.animation, required this.origin, required this.hubSize});
  final Animation<double> animation;
  final Rect origin;
  final double hubSize;

  @override
  State<_HubMenuView> createState() => _HubMenuViewState();
}

class _HubMenuViewState extends State<_HubMenuView> with SingleTickerProviderStateMixin {
  static const double _item = 58; // circle size
  static const double _radius = 130; // distance from the hub centre (room for labels)

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _pick(_HubAction a, Rect rect) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_HubPick(a, rect));
  }

  /// Item i's progress (0 → 1), staggered so they spring out one by one.
  double _itemT(double t, int i) {
    final start = 0.08 * i;
    final x = ((t - start) / (1 - start)).clamp(0.0, 1.0);
    return x;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final center = widget.origin.center;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, _pulse]),
      builder: (context, _) {
        final raw = widget.animation.value;
        final forward = widget.animation.status != AnimationStatus.reverse;
        final t = reduceMotion ? (raw > 0 ? 1.0 : 0.0) : raw;

        final children = <Widget>[
          // Dim + blur; tap anywhere to close.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
                child: ColoredBox(color: Colors.black.withOpacity(0.5 * t)),
              ),
            ),
          ),
        ];

        for (var i = 0; i < _kHubItems.length; i++) {
          final it = _kHubItems[i];
          final p = _itemT(t, i);
          final curved = forward ? Curves.easeOutBack.transform(p) : Curves.easeInCubic.transform(p);
          final a = it.angleDeg * math.pi / 180;
          var target = center + Offset(math.cos(a), math.sin(a)) * _radius;
          // Keep every circle (and its label) fully on screen.
          target = Offset(
            target.dx.clamp(pad.left + _item / 2 + 8, screen.width - pad.right - _item / 2 - 8).toDouble(),
            target.dy.clamp(pad.top + _item / 2 + 8, screen.height - pad.bottom - _item / 2 - 28).toDouble(),
          );
          final pos = Offset.lerp(center, target, curved)!;
          final rect = Rect.fromCenter(center: pos, width: _item, height: _item);
          final opacity = p.clamp(0.0, 1.0);
          final scale = 0.4 + 0.6 * curved.clamp(0.0, 1.2);

          // Wide enough for a two-line label, centred under the circle.
          const labelW = 150.0;
          children.add(Positioned(
            left: rect.center.dx - labelW / 2,
            top: rect.top,
            width: labelW,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Pressable(
                      onTap: t > 0.9 ? () => _pick(it.action, rect) : null,
                      child: _circleFor(it.action),
                    ),
                    const SizedBox(height: 6),
                    // Label — shrinks to fit, never overflows.
                    Container(
                      constraints: const BoxConstraints(maxWidth: labelW - 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          it.label,
                          maxLines: 2,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
        }

        // The hub itself, turning from spanner into ✕.
        final hubTurn = Curves.easeOutCubic.transform(t);
        children.add(Positioned.fromRect(
          rect: widget.origin,
          child: GestureDetector(
            onTap: _close,
            child: Transform.rotate(
              angle: hubTurn * math.pi / 2,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _yellow,
                  border: Border.all(color: Colors.white.withOpacity(0.7), width: 2),
                  boxShadow: [
                    BoxShadow(color: _yellow.withOpacity(0.45), blurRadius: 22, spreadRadius: 2),
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(opacity: (1 - hubTurn * 1.6).clamp(0.0, 1.0), child: const _Spanner(size: 34)),
                    Opacity(
                      opacity: ((hubTurn - 0.35) / 0.65).clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: -math.pi / 4,
                        child: const Icon(Icons.close_rounded, color: _navy, size: 32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));

        return Material(type: MaterialType.transparency, child: Stack(children: children));
      },
    );
  }

  Widget _circleFor(_HubAction a) {
    switch (a) {
      case _HubAction.sos:
        final p = _pulse.value;
        return Container(
          width: _item,
          height: _item,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.3, -0.4),
              colors: [Color(0xFFFF6B6B), _sosRed, Color(0xFFB3141A)],
              stops: [0, 0.6, 1],
            ),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(color: _sosRed.withOpacity(0.18 + 0.18 * p), spreadRadius: 3 + 5 * p),
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
            ],
          ),
          alignment: Alignment.center,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('SOS',
                  maxLines: 1,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ),
        );
      case _HubAction.call:
        return _plainCircle(
          color: _callGreen,
          child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 26),
        );
      case _HubAction.services:
        return _plainCircle(
          color: _servicesBlue,
          child: const _Spanner(size: 32, color: _yellow, background: _servicesBlue),
        );
    }
  }

  Widget _plainCircle({required Color color, required Widget child}) {
    return Container(
      width: _item,
      height: _item,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.45), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Shrinks a little while pressed — premium tap feel.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.88 : 1,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}
