import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Home-screen card for ReperiResolve (fixed price for issues left after a
/// service). Drawn entirely in code — no image — so it stays crisp on every
/// screen and weighs nothing.
///
/// Left: three short lines of text. Right: a small car that loops through
/// three common problems, each with its own animation:
///   1. Water leak   — drops fall onto the window
///   2. Brake squeak — sound waves pulse from the front wheel
///   3. Rattle       — the car shakes with little zig-zags
class ReperiResolveCard extends StatefulWidget {
  const ReperiResolveCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<ReperiResolveCard> createState() => _ReperiResolveCardState();
}

class _ReperiResolveCardState extends State<ReperiResolveCard>
    with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF142A6E);
  static const _blue = Color(0xFF2F5BD8);
  static const _coral = Color(0xFFEF5B4C);

  /// One full loop = the three problems, 2.4 s each.
  static const _phaseSeconds = 2.4;
  static const _issues = <_Issue>[
    _Issue('Water leak', Icons.water_drop_rounded, Color(0xFF3FA2FF)),
    _Issue('Brake squeak', Icons.volume_up_rounded, _coral),
    _Issue('Rattle', Icons.vibration_rounded, Color(0xFFF0A020)),
  ];

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_phaseSeconds * _issues.length * 1000).round()),
  )..repeat();

  bool _pressed = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            height: 128,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x14142A6E)),
              boxShadow: const [
                BoxShadow(color: Color(0x1A142A6E), blurRadius: 18, offset: Offset(0, 8)),
              ],
            ),
            child: Stack(
              children: [
                // Soft blue glow behind the car.
                Positioned(
                  right: -40,
                  top: -30,
                  bottom: -30,
                  width: 210,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        _blue.withOpacity(0.10),
                        _blue.withOpacity(0.0),
                      ]),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: _text()),
                    SizedBox(width: 148, child: _art()),
                  ],
                ),
                // A light shine sweeps across once per loop.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) => CustomPaint(
                        painter: _ShinePainter(_c.value),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _text() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'After-service issue?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _coral,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ShaderMask(
              shaderCallback: (r) =>
                  const LinearGradient(colors: [_navy, _blue]).createShader(r),
              child: Text(
                'ReperiResolve',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Colors.white, // painted over by the gradient
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 9, 7),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Get a price',
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _art() {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final loop = _c.value * _issues.length;
        final phase = loop.floor() % _issues.length;
        final t = loop - loop.floor(); // 0..1 within the current problem
        final issue = _issues[phase];
        return Stack(
          children: [
            Positioned.fill(
              top: 22,
              child: CustomPaint(painter: _CarPainter(phase: phase, t: t, spin: _c.value)),
            ),
            // Label for the current problem.
            Positioned(
              top: 12,
              right: 10,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: _chip(issue, key: ValueKey(phase)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(_Issue issue, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(6, 4, 9, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [
          BoxShadow(color: Color(0x1F142A6E), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(issue.icon, size: 13, color: issue.color),
          const SizedBox(width: 4),
          Text(
            issue.label,
            style: GoogleFonts.manrope(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _Issue {
  const _Issue(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// The little car plus the effect for the current problem. Drawn in a fixed
/// 540 x 316 design space and scaled to fit.
class _CarPainter extends CustomPainter {
  _CarPainter({required this.phase, required this.t, required this.spin});

  final int phase; // 0 leak, 1 squeak, 2 rattle
  final double t; // progress within the phase, 0..1
  final double spin; // overall loop progress, for wheel rotation

  static const _navy = Color(0xFF142A6E);
  static const _blue = Color(0xFF2F5BD8);
  static const _glass = Color(0xFFDCE6FF);

  // Fade each effect in and out at the edges of its phase.
  double get _env {
    if (t < 0.12) return t / 0.12;
    if (t > 0.88) return (1 - t) / 0.12;
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const w = 540.0, h = 316.0;
    final s = math.min(size.width / w, size.height / h);
    canvas.save();
    canvas.translate((size.width - w * s) / 2, (size.height - h * s) / 2);
    canvas.scale(s);
    // Design space: x 30..570, y 96..412 (drops above, waves to the right).
    canvas.translate(-30, -96);

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(250, 356), width: 420, height: 18),
      Paint()..color = _navy.withOpacity(0.10),
    );

    // Rattle: shake the whole car.
    var dx = 0.0, dy = 0.0;
    if (phase == 2) {
      final k = _env;
      dx = math.sin(t * math.pi * 2 * 14) * 3.2 * k;
      dy = math.cos(t * math.pi * 2 * 11) * 2.0 * k;
    }
    canvas.save();
    canvas.translate(dx, dy);

    final body = Path()
      ..moveTo(40, 330)
      ..quadraticBezierTo(36, 290, 70, 280)
      ..lineTo(132, 268)
      ..quadraticBezierTo(160, 214, 214, 200)
      ..lineTo(330, 196)
      ..quadraticBezierTo(372, 198, 404, 236)
      ..lineTo(438, 270)
      ..quadraticBezierTo(484, 278, 488, 312)
      ..lineTo(490, 338)
      ..quadraticBezierTo(490, 352, 476, 352)
      ..lineTo(58, 352)
      ..quadraticBezierTo(42, 352, 40, 338)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_blue, _navy],
        ).createShader(const Rect.fromLTRB(40, 196, 490, 352)),
    );

    final glass = Paint()..color = _glass;
    canvas.drawPath(
      Path()
        ..moveTo(150, 268)
        ..quadraticBezierTo(172, 222, 214, 214)
        ..lineTo(264, 212)
        ..lineTo(264, 268)
        ..close(),
      glass,
    );
    canvas.drawPath(
      Path()
        ..moveTo(280, 212)
        ..lineTo(328, 212)
        ..quadraticBezierTo(360, 214, 386, 244)
        ..lineTo(404, 268)
        ..lineTo(280, 268)
        ..close(),
      glass,
    );

    // Door line, handles, lights.
    canvas.drawLine(const Offset(272, 214), const Offset(272, 346),
        Paint()
          ..color = const Color(0x800F2259)
          ..strokeWidth = 3);
    final handle = Paint()..color = _glass.withOpacity(0.8);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(292, 284, 30, 7), const Radius.circular(4)), handle);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(200, 284, 30, 7), const Radius.circular(4)), handle);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(470, 296, 16, 12), const Radius.circular(5)),
        Paint()..color = const Color(0xFFFFD36B));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(42, 300, 12, 12), const Radius.circular(4)),
        Paint()..color = const Color(0xFFEF5B4C));

    // Wheels with a turning spoke so the car feels alive.
    for (final cx in const [134.0, 396.0]) {
      final c = Offset(cx, 352);
      canvas.drawCircle(c, 44, Paint()..color = const Color(0xFF1A1A1A));
      canvas.drawCircle(c, 20, Paint()..color = const Color(0xFFC7CCD8));
      final a = spin * math.pi * 2 * 6;
      final spoke = Paint()
        ..color = const Color(0xFF5B6478)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final ang = a + i * math.pi * 2 / 3;
        canvas.drawLine(c, c + Offset(math.cos(ang), math.sin(ang)) * 16, spoke);
      }
      canvas.drawCircle(c, 5, Paint()..color = const Color(0xFF5B6478));
    }
    canvas.restore();

    switch (phase) {
      case 0:
        _leak(canvas);
      case 1:
        _squeak(canvas);
      default:
        _rattle(canvas);
    }
    canvas.restore();
  }

  void _drop(Canvas canvas, Offset at, double size, double opacity) {
    final p = Path()
      ..moveTo(at.dx, at.dy - size * 1.6)
      ..quadraticBezierTo(at.dx + size * 1.1, at.dy - size * 0.2, at.dx + size * 0.9, at.dy + size * 0.4)
      ..arcToPoint(Offset(at.dx - size * 0.9, at.dy + size * 0.4), radius: Radius.circular(size * 0.95))
      ..quadraticBezierTo(at.dx - size * 1.1, at.dy - size * 0.2, at.dx, at.dy - size * 1.6)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF3FA2FF).withOpacity(opacity));
  }

  void _leak(Canvas canvas) {
    // Three drops falling onto the windows, staggered.
    const xs = [222.0, 300.0, 350.0];
    for (var i = 0; i < xs.length; i++) {
      final local = ((t * 1.6) - i * 0.22) % 1.0;
      final y = 120 + local * 96; // falls to the roof line (~216)
      final fade = (local < 0.8 ? 1.0 : (1 - local) / 0.2) * _env;
      _drop(canvas, Offset(xs[i], y), 11, fade.clamp(0.0, 1.0).toDouble());
      // Small splash when it lands.
      if (local > 0.82) {
        final r = (local - 0.82) / 0.18;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(xs[i], 214), width: 18 + 30 * r, height: 6 + 6 * r),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF3FA2FF).withOpacity((1 - r) * 0.8 * _env),
        );
      }
    }
  }

  void _squeak(Canvas canvas) {
    // Arcs ripple out from the front wheel.
    const c = Offset(396, 352);
    for (var i = 0; i < 3; i++) {
      final local = ((t * 2.2) - i * 0.28) % 1.0;
      final r = 58 + local * 52;
      final op = (1 - local) * _env;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFEF5B4C).withOpacity(op.clamp(0.0, 1.0).toDouble());
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -0.55, 1.1, false, paint);
    }
  }

  void _rattle(Canvas canvas) {
    // Zig-zags flicker near the rear and the roof.
    final flick = (math.sin(t * math.pi * 2 * 6) * 0.5 + 0.5) * _env;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFF0A020).withOpacity(flick.clamp(0.0, 1.0).toDouble());
    Path zig(double x, double y) => Path()
      ..moveTo(x, y)
      ..lineTo(x + 12, y - 12)
      ..lineTo(x + 22, y)
      ..lineTo(x + 34, y - 12)
      ..lineTo(x + 44, y);
    canvas.drawPath(zig(40, 236), paint);
    canvas.drawPath(zig(250, 170), paint..color = paint.color.withOpacity((1 - flick) * _env));
  }

  @override
  bool shouldRepaint(_CarPainter old) => old.t != t || old.phase != phase || old.spin != spin;
}

/// A soft diagonal shine that sweeps across the card at the start of each
/// loop, then stays out of the way.
class _ShinePainter extends CustomPainter {
  _ShinePainter(this.v);
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    const sweep = 0.16; // fraction of the loop the sweep takes
    if (v > sweep) return;
    final p = v / sweep;
    final x = -size.width * 0.4 + p * size.width * 1.8;
    final rect = Rect.fromLTWH(x, 0, size.width * 0.35, size.height);
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.skew(-0.35, 0);
    canvas.translate(-rect.center.dx, -rect.center.dy);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white.withOpacity(0),
          Colors.white.withOpacity(0.55),
          Colors.white.withOpacity(0),
        ]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.v != v;
}
