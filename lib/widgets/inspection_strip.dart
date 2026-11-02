import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/catalog_service.dart';

/// Home screen strip: yellow card, navy text —
///   "Car inspection at your location within [2 hours]      ₹199 ›"
/// with a little looping story drawn below the text (9 s):
///   1. a blue car breaks down (smoke, hazards blinking)
///   2. a man in a suit walks up, spots it and makes a call
///   3. a Reperi mechanic rides in on a scooter
///   4. he fixes it on the spot (spanner + sparks), the smoke stops
///   5. green tick, the car bounces, the man waves — "2 hours" lights up
///
/// All drawn in code (no image / video assets). With the phone's "reduce
/// motion" setting on, it shows one still frame of the fixed car.
///
/// No fixed heights: the text wraps on small phones / big fonts and the
/// strip grows; the scene keeps its aspect ratio and scales with the width,
/// so nothing ever overflows.
class InspectionStrip extends StatefulWidget {
  const InspectionStrip({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Doorstep Car Inspection in the Supabase `services` table.
  static const String serviceKey = 'os_inspection';

  @override
  State<InspectionStrip> createState() => _InspectionStripState();
}

class _InspectionStripState extends State<InspectionStrip> with SingleTickerProviderStateMixin {
  static const Color _yellow = Color(0xFFFDF003);
  static const Color _navy = Color(0xFF022B57);

  /// One full story. Frame shown when "reduce motion" is on: the fixed car.
  static const Duration _loop = Duration(milliseconds: 9000);
  static const double _stillFrame = 0.80;

  late final AnimationController _c = AnimationController(vsync: this, duration: _loop);
  bool _pressed = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _t => _still ? _stillFrame : _c.value;

  @override
  Widget build(BuildContext context) {
    final price = CatalogService.byKey(InspectionStrip.serviceKey)?.price ?? 199;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Semantics(
        button: true,
        label: 'Car inspection at your location within 2 hours, $price rupees. Book.',
        excludeSemantics: true,
        child: Material(
          color: _yellow,
          borderRadius: BorderRadius.circular(22),
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(22),
            splashColor: _navy.withOpacity(0.08),
            highlightColor: _navy.withOpacity(0.05),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(color: _navy.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 8)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _c,
                            builder: (context, _) => _text(_chipGlow(_t)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '₹$price',
                          maxLines: 1,
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: _navy,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: _navy, size: 26),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: RepaintBoundary(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(
                            color: Colors.white.withOpacity(0.42),
                            child: AspectRatio(
                              aspectRatio: _StoryPainter.viewW / _StoryPainter.viewH,
                              child: AnimatedBuilder(
                                animation: _c,
                                builder: (context, _) => Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(painter: _StoryPainter(_t)),
                                    Positioned(
                                      left: 8,
                                      top: 7,
                                      right: 8,
                                      child: Align(alignment: Alignment.topLeft, child: _captions(_t)),
                                    ),
                                  ],
                                ),
                              ),
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
      ),
    );
  }

  /// "2 hours" lights up (navy box, yellow text) once the car is fixed.
  static double _chipGlow(double t) => _kf(t, const [[0, 0], [81, 0], [82, 1], [96, 1], [97, 0]]);

  Widget _text(double k) {
    final base = GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35, color: _navy);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _navy.withOpacity(k),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '2 hours',
        maxLines: 1,
        style: base.copyWith(
          fontWeight: FontWeight.w900,
          color: Color.lerp(_navy, _yellow, k),
          height: 1.3,
        ),
      ),
    );
    // One run of text, so it wraps onto more lines when the phone is narrow
    // or the font is big — never overflows.
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Car inspection at your location '),
          TextSpan(text: 'within ', style: base.copyWith(fontWeight: FontWeight.w600)),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip),
        ],
      ),
    );
  }

  // ── Captions (top-left pill, one per stage) ─────────────────────────────
  static const List<String> _capText = [
    'Car broke down',
    'Calling Reperi…',
    'Expert on the way',
    'Fixing it on the spot',
    'Fixed ✓ Back on the road',
  ];
  static const List<List<List<double>>> _capKeys = [
    [[0, 0], [1, 0], [3, 1], [22, 1], [25, 0]],
    [[0, 0], [24, 0], [27, 1], [42, 1], [45, 0]],
    [[0, 0], [44, 0], [47, 1], [58, 1], [61, 0]],
    [[0, 0], [60, 0], [62, 1], [74, 1], [77, 0]],
    [[0, 0], [76, 0], [79, 1], [95, 1], [98, 0]],
  ];

  Widget _captions(double t) {
    final pills = <Widget>[];
    for (var i = 0; i < _capText.length; i++) {
      final o = _kf(t, _capKeys[i]);
      if (o <= 0.01) continue;
      pills.add(Opacity(
        opacity: o.clamp(0.0, 1.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(20)),
          child: Text(
            _capText[i],
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w800, color: _yellow, height: 1.25),
          ),
        ),
      ));
    }
    if (pills.isEmpty) return const SizedBox.shrink();
    // Shrinks (never overflows) on narrow strips / big fonts.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: Stack(children: pills),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Keyframes: [[percent, value], …] → value at t (0..1), like CSS @keyframes.
// ═════════════════════════════════════════════════════════════════════════

double _kf(double t, List<List<double>> k, [Curve curve = Curves.linear]) {
  final p = t * 100;
  if (p <= k.first[0]) return k.first[1];
  for (var i = 1; i < k.length; i++) {
    if (p <= k[i][0]) {
      final a = k[i - 1], b = k[i];
      final span = b[0] - a[0];
      final f = span <= 0 ? 1.0 : ((p - a[0]) / span).clamp(0.0, 1.0);
      return a[1] + (b[1] - a[1]) * curve.transform(f);
    }
  }
  return k.last[1];
}

// ═════════════════════════════════════════════════════════════════════════
//  The scene — drawn on a 340 × 124 grid, scaled to the strip's width.
// ═════════════════════════════════════════════════════════════════════════

class _StoryPainter extends CustomPainter {
  _StoryPainter(this.t);

  /// 0..1 through the 9-second story.
  final double t;

  static const double viewW = 340, viewH = 124;
  static const double _loopMs = 9000;

  static const Color _navy = Color(0xFF022B57);
  static const Color _yellow = Color(0xFFFDF003);
  static const Color _carBlue = Color(0xFF2E7CF6);
  static const Color _carDark = Color(0xFF1F5FCC);
  static const Color _glass = Color(0xFFBFE3FF);
  static const Color _tyre = Color(0xFF1B2430);
  static const Color _hub = Color(0xFFB9C3CF);
  static const Color _suit = Color(0xFF0F2A4A);
  static const Color _suitArm = Color(0xFF132F52);
  static const Color _skin = Color(0xFFC98B5E);
  static const Color _skin2 = Color(0xFF8D5A3B);
  static const Color _hair = Color(0xFF1E1A17);
  static const Color _orange = Color(0xFFF07A1F);
  static const Color _orangeDark = Color(0xFFB85A12);
  static const Color _red = Color(0xFFD7263D);
  static const Color _scooter = Color(0xFFE5484D);
  static const Color _steel = Color(0xFF5C6B7A);
  static const Color _green = Color(0xFF1FAA59);

  double get _ms => t * _loopMs;

  Paint _fill(Color c, [double opacity = 1]) => Paint()
    ..color = c.withOpacity(opacity.clamp(0.0, 1.0))
    ..isAntiAlias = true;

  void _rect(Canvas c, double x, double y, double w, double h, double r, Color color) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)), _fill(color));
  }

  void _rotate(Canvas c, double cx, double cy, double degrees) {
    c.translate(cx, cy);
    c.rotate(degrees * math.pi / 180);
    c.translate(-cx, -cy);
  }

  void _scaleAt(Canvas c, double cx, double cy, double s) {
    c.translate(cx, cy);
    c.scale(s);
    c.translate(-cx, -cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / viewW, size.height / viewH);

    _road(canvas);

    // Everything except the road fades out at the end and back in at the start.
    final all = _kf(t, const [[0, 0], [3, 1], [95, 1], [99, 0], [100, 0]]);
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, viewW, viewH),
      Paint()..color = Colors.black.withOpacity(all.clamp(0.0, 1.0)),
    );
    _car(canvas);
    _tick(canvas);
    _man(canvas);
    _scooterRide(canvas);
    _mechanic(canvas);
    _spannerAndSparks(canvas);
    canvas.restore();

    canvas.restore();
  }

  // ── Road ────────────────────────────────────────────────────────────────
  void _road(Canvas c) {
    c.drawRect(const Rect.fromLTWH(0, 112, viewW, 12), _fill(_navy, 0.9));
    for (var x = 10.0; x < viewW; x += 50) {
      _rect(c, x, 117, 22, 2.5, 1, _yellow.withOpacity(0.85));
    }
  }

  // ── Blue car ────────────────────────────────────────────────────────────
  void _car(Canvas c) {
    final bounce = _kf(t, const [[0, 0], [78, 0], [80, -5], [82, 0], [84, -3], [86, 0], [100, 0]], Curves.easeInOut);
    c.save();
    c.translate(0, bounce);

    c.drawOval(Rect.fromCenter(center: const Offset(70, 112), width: 112, height: 6), _fill(Colors.black, 0.15));

    final cabin = Path()
      ..moveTo(38, 80)
      ..lineTo(50, 62)
      ..quadraticBezierTo(53, 59, 58, 59)
      ..lineTo(86, 59)
      ..quadraticBezierTo(91, 59, 94, 63)
      ..lineTo(106, 80)
      ..close();
    c.drawPath(cabin, _fill(_carDark));
    final w1 = Path()
      ..moveTo(44, 79)
      ..lineTo(53, 65)
      ..quadraticBezierTo(55, 63, 58, 63)
      ..lineTo(70, 63)
      ..lineTo(70, 79)
      ..close();
    final w2 = Path()
      ..moveTo(74, 63)
      ..lineTo(86, 63)
      ..quadraticBezierTo(89, 63, 91, 66)
      ..lineTo(100, 79)
      ..lineTo(74, 79)
      ..close();
    c.drawPath(w1, _fill(_glass));
    c.drawPath(w2, _fill(_glass));

    _rect(c, 20, 78, 104, 27, 9, _carBlue);
    c.drawRect(const Rect.fromLTWH(20, 92, 104, 4), _fill(_carDark));
    _rect(c, 64, 84, 10, 2.5, 1, const Color(0xFF1A4FB0));

    // Headlight (+ a flash when it's fixed)
    c.drawCircle(const Offset(119, 86), 3.6, _fill(const Color(0xFFFFF6B0)));
    final beam = _kf(t, const [[0, 0], [79, 0], [80, 0.8], [82, 0], [84, 0.8], [86, 0]]);
    if (beam > 0) c.drawCircle(const Offset(119, 86), 9, _fill(const Color(0xFFFFF6B0), beam));

    // Hazard lights blink until the car is fixed
    if (t < 0.75) {
      final on = (_ms % 700) < 350;
      final hz = on ? const Color(0xFFFF9F1C) : const Color(0xFF5A3A10);
      _rect(c, 20, 83, 5, 6, 2, hz);
      _rect(c, 114, 94, 6, 4, 2, hz);
    }

    // Bonnet, raised a touch
    final bonnet = Path()
      ..moveTo(104, 79)
      ..lineTo(124, 73)
      ..lineTo(124, 77)
      ..lineTo(106, 80)
      ..close();
    c.drawPath(bonnet, _fill(_carDark));

    for (final x in const [42.0, 98.0]) {
      c.drawCircle(Offset(x, 104), 10, _fill(_tyre));
      c.drawCircle(Offset(x, 104), 4.5, _fill(_hub));
      c.drawRect(Rect.fromLTWH(x - 1, 96, 2, 16), _fill(_tyre));
    }

    // Smoke from the bonnet until it's fixed
    if (t < 0.73) {
      const origin = Offset(112, 78);
      const puffs = [
        [112.0, 0.0],
        [116.0, 530.0],
        [110.0, 1060.0],
      ];
      for (final puff in puffs) {
        if (_ms < puff[1]) continue;
        final p = ((_ms - puff[1]) % 1600) / 1600;
        final e = Curves.easeOut.transform(p);
        final s = 0.4 + 1.1 * e;
        final op = p < 0.15 ? 0.75 * (p / 0.15) : 0.75 * (1 - (p - 0.15) / 0.85);
        final x = origin.dx + (puff[0] - origin.dx) * s + 8 * e;
        final y = origin.dy + (74 - origin.dy) * s - 34 * e;
        c.drawCircle(Offset(x, y), 7 * s, _fill(const Color(0xFF7A8794), op));
      }
    }
    c.restore();
  }

  // ── Green tick over the fixed car ───────────────────────────────────────
  void _tick(Canvas c) {
    final o = _kf(t, const [[0, 0], [76, 0], [79, 1], [88, 1], [90, 0]]);
    if (o <= 0) return;
    final s = _kf(t, const [[0, 0.2], [76, 0.2], [79, 1.18], [81, 1], [100, 1]]);
    c.save();
    _scaleAt(c, 70, 40, s);
    c.drawCircle(const Offset(70, 40), 13, _fill(_green, o));
    final check = Path()
      ..moveTo(63, 40)
      ..lineTo(68, 45)
      ..lineTo(77, 35);
    c.drawPath(
      check,
      Paint()
        ..color = Colors.white.withOpacity(o)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    c.restore();
  }

  // ── Man in a suit ───────────────────────────────────────────────────────
  void _man(Canvas c) {
    final o = _kf(t, const [[0, 0], [4, 1], [96, 1], [99, 0], [100, 0]]);
    if (o <= 0) return;
    final x = _kf(t, const [[0, 170], [22, 0], [100, 0]]);
    c.saveLayer(const Rect.fromLTWH(0, 0, viewW, viewH), Paint()..color = Colors.black.withOpacity(o));
    c.translate(x, 0);

    // Legs swing while walking in
    final p = t * 100;
    double swing = 0;
    if (p > 2 && p < 22) {
      final env = (p < 4 ? (p - 2) / 2 : p > 20 ? (22 - p) / 2 : 1.0).clamp(0.0, 1.0);
      swing = 18 * env * math.cos(2 * math.pi * (p - 4) / 4);
    }
    for (final leg in [
      [222.0, 220.0, swing],
      [226.0, 224.0, -swing],
    ]) {
      c.save();
      _rotate(c, 226, 96, leg[2]);
      _rect(c, leg[0], 94, 5, 18, 2, const Color(0xFF0A1C33));
      _rect(c, leg[1], 109, 9, 3.5, 1.5, const Color(0xFF111111));
      c.restore();
    }

    _rect(c, 216, 64, 22, 33, 6, _suit);
    c.drawPath(
      Path()
        ..moveTo(223, 64)
        ..lineTo(227, 72)
        ..lineTo(231, 64)
        ..close(),
      _fill(Colors.white),
    );
    c.drawPath(
      Path()
        ..moveTo(226, 67)
        ..lineTo(228, 67)
        ..lineTo(229, 80)
        ..lineTo(227, 83)
        ..lineTo(225, 80)
        ..close(),
      _fill(_red),
    );
    // Front arm (stays down)
    _rect(c, 216, 66, 5, 22, 2.5, _suitArm);
    c.drawCircle(const Offset(218.5, 88), 2.6, _fill(_skin));

    // Head, looking left at the car
    c.drawCircle(const Offset(228, 54), 9, _fill(_skin));
    c.drawPath(
      Path()
        ..moveTo(219, 52)
        ..quadraticBezierTo(220, 43, 228, 43)
        ..quadraticBezierTo(237, 43, 237, 52)
        ..quadraticBezierTo(233, 47, 228, 48)
        ..quadraticBezierTo(222, 48, 219, 52)
        ..close(),
      _fill(_hair),
    );
    c.drawCircle(const Offset(224, 54), 1.1, _fill(_hair));
    c.drawCircle(const Offset(235.5, 55), 1.8, _fill(const Color(0xFFB07548)));

    // Phone arm: elbow out, phone to the ear; waves at the end
    final arm = _kf(
      t,
      const [[0, 0], [23, 0], [27, -133], [43, -133], [47, 0], [84, 0], [87, -150], [89, -125], [91, -150], [93, -125], [95, 0], [100, 0]],
      Curves.easeInOut,
    );
    final fore = _kf(t, const [[0, 0], [23, 0], [27, -97], [43, -97], [47, 0], [100, 0]], Curves.easeInOut);
    c.save();
    _rotate(c, 235.5, 68, arm);
    _rect(c, 233, 66, 5, 14, 2.5, _suitArm);
    _rotate(c, 235.5, 79, fore);
    _rect(c, 233, 77, 5, 11, 2.5, _suitArm);
    c.drawCircle(const Offset(235.5, 88), 2.8, _fill(_skin));
    _rect(c, 233, 85, 5, 9, 1.3, const Color(0xFF111111));
    c.restore();

    // Call waves
    final wave = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final w1 = _kf(t, const [[0, 0], [28, 0], [30, 1], [33, 0], [35, 1], [38, 0], [40, 1], [43, 0]]);
    final w2 = _kf(t, const [[0, 0], [29, 0], [31, 1], [34, 0], [36, 1], [39, 0], [41, 1], [43, 0]]);
    if (w1 > 0) {
      c.drawPath(
        Path()
          ..moveTo(246, 40)
          ..quadraticBezierTo(251, 46, 246, 52),
        wave..color = _navy.withOpacity(w1),
      );
    }
    if (w2 > 0) {
      c.drawPath(
        Path()
          ..moveTo(251, 36)
          ..quadraticBezierTo(258, 46, 251, 56),
        wave..color = _navy.withOpacity(w2),
      );
    }

    // "!" — he notices the car
    final ao = _kf(t, const [[0, 0], [20, 0], [22, 1], [26, 0]]);
    if (ao > 0) {
      final alertScale = _kf(t, const [[0, 0.3], [20, 0.3], [22, 1.15], [24, 1], [100, 1]]);
      c.save();
      _scaleAt(c, 228, 34, alertScale);
      c.drawCircle(const Offset(228, 32), 7, _fill(_red, ao));
      _rect(c, 227, 27, 2, 6, 1, Colors.white.withOpacity(ao));
      c.drawCircle(const Offset(228, 35.5), 1.1, _fill(Colors.white, ao));
      c.restore();
    }

    c.restore();
  }

  // ── Scooter ─────────────────────────────────────────────────────────────
  void _scooterRide(Canvas c) {
    final o = _kf(t, const [[0, 1], [96, 1], [99, 0], [100, 0]]);
    if (o <= 0) return;
    final x = _kf(t, const [[0, 260], [44, 260], [56, 0], [100, 0]], Curves.easeOutCubic);
    if (x >= 200) return; // still off-screen
    c.saveLayer(const Rect.fromLTWH(0, 0, viewW, viewH), Paint()..color = Colors.black.withOpacity(o));
    c.translate(x, 0);
    c.drawOval(Rect.fromCenter(center: const Offset(182, 112), width: 44, height: 5), _fill(Colors.black, 0.15));
    for (final wx in const [166.0, 198.0]) {
      c.drawCircle(Offset(wx, 105), 7, _fill(_tyre));
      c.drawCircle(Offset(wx, 105), 3, _fill(_hub));
    }
    c.drawPath(
      Path()
        ..moveTo(160, 100)
        ..quadraticBezierTo(162, 90, 176, 90)
        ..lineTo(190, 90)
        ..lineTo(194, 100)
        ..close(),
      _fill(_scooter),
    );
    c.save();
    _rotate(c, 188, 89, 12);
    _rect(c, 186, 78, 4, 22, 2, _scooter);
    c.restore();
    _rect(c, 186, 76, 12, 3, 1.5, _tyre);
    _rect(c, 168, 86, 16, 4, 2, _tyre);
    // Toolbox on the back
    _rect(c, 156, 82, 12, 9, 2, _navy);
    _rect(c, 160, 80, 4, 3, 1, _navy);
    c.restore();
  }

  // ── Mechanic ────────────────────────────────────────────────────────────
  void _mechanic(Canvas c) {
    final o = _kf(t, const [[0, 1], [96, 1], [99, 0], [100, 0]]);
    if (o <= 0) return;
    final x = _kf(t, const [[0, 260], [44, 260], [56, 0], [58, -6], [62, -56], [100, -56]], Curves.easeOutCubic);
    final y = _kf(t, const [[0, -10], [44, -10], [56, -10], [58, -16], [62, 0], [100, 0]], Curves.easeOutCubic);
    if (x >= 200) return;
    c.saveLayer(const Rect.fromLTWH(0, 0, viewW, viewH), Paint()..color = Colors.black.withOpacity(o));
    c.translate(x, y);
    _rect(c, 174, 95, 5, 17, 2, _orangeDark);
    _rect(c, 179, 95, 5, 17, 2, _orangeDark);
    _rect(c, 172, 109, 8, 3.5, 1.5, const Color(0xFF111111));
    _rect(c, 178, 109, 8, 3.5, 1.5, const Color(0xFF111111));
    _rect(c, 171, 68, 17, 30, 5, _orange);
    _rect(c, 176, 72, 7, 8, 1.5, _yellow.withOpacity(0.9));
    _rect(c, 167, 70, 5, 18, 2.5, _orange);
    c.drawCircle(const Offset(180, 59), 8, _fill(_skin2));
    c.drawPath(
      Path()
        ..moveTo(172, 57)
        ..quadraticBezierTo(172, 49, 180, 49)
        ..quadraticBezierTo(188, 49, 188, 57)
        ..lineTo(170, 57)
        ..close(),
      _fill(_navy),
    );
    _rect(c, 166, 55.5, 10, 2.5, 1, _navy);
    c.drawCircle(const Offset(176, 60), 1, _fill(_hair));
    c.restore();
  }

  // ── Spanner + sparks at the bonnet ──────────────────────────────────────
  void _spannerAndSparks(Canvas c) {
    final o = _kf(t, const [[0, 0], [61, 0], [62, 1], [76, 1], [78, 0]]);
    if (o > 0) {
      final r = _kf(
        t,
        const [[0, 0], [61, 0], [64, -35], [66, 10], [68, -35], [70, 10], [72, -35], [74, 10], [76, 0], [100, 0]],
        Curves.easeInOut,
      );
      c.save();
      _rotate(c, 124, 74, r);
      _rect(c, 118, 72, 16, 3.4, 1.7, _steel.withOpacity(o));
      final head = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: const Offset(115.5, 73.7), radius: 4.8))
        ..addOval(Rect.fromCircle(center: const Offset(114.6, 72.8), radius: 2.1));
      c.drawPath(head, _fill(_steel, o));
      c.restore();
    }

    final a = _kf(t, const [[0, 0], [63, 0], [64, 1], [65, 0], [68, 1], [69, 0], [72, 1], [73, 0]]);
    final b = _kf(t, const [[0, 0], [65, 0], [66, 1], [67, 0], [70, 1], [71, 0], [74, 1], [75, 0]]);
    const spark = Color(0xFFFFB020);
    void tri(List<double> p, double op) {
      if (op <= 0) return;
      c.drawPath(
        Path()
          ..moveTo(p[0], p[1])
          ..lineTo(p[2], p[3])
          ..lineTo(p[4], p[5])
          ..close(),
        _fill(spark, op),
      );
    }

    tri(const [110, 66, 112, 70, 108, 69], a);
    tri(const [106, 72, 110, 72, 107, 75], a);
    tri(const [118, 64, 119, 69, 115, 67], b);
    tri(const [114, 62, 116, 66, 112, 65], b);
  }

  @override
  bool shouldRepaint(_StoryPainter old) => old.t != t;
}
