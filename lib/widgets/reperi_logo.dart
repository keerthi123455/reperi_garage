import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reperi logo mark: yellow disc with the navy spanner — the same look as
/// the yellow hub button on Home. Drawn in code so it's sharp at any size
/// and keeps its colours in light and dark mode. Shown next to the REPERI
/// wordmark (app header, sign-up and login screens).
class ReperiLogoMark extends StatelessWidget {
  const ReperiLogoMark({super.key, this.size = 36});

  final double size;

  static const Color yellow = Color(0xFFFDF003);
  static const Color navy = Color(0xFF022B57);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Reperi',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: yellow,
          border: Border.all(color: Colors.white, width: math.max(1.5, size * 0.05)),
          boxShadow: [
            BoxShadow(color: yellow.withOpacity(0.45), blurRadius: size * 0.3),
            BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: size * 0.15, offset: Offset(0, size * 0.06)),
          ],
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size.square(size * 0.62),
          painter: const _SpannerPainter(navy, yellow),
        ),
      ),
    );
  }
}

/// Same spanner shape as the hub button (100×100 box, rotated 45°).
class _SpannerPainter extends CustomPainter {
  const _SpannerPainter(this.color, this.background);
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
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
