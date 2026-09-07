import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// The diagonal-striped "photo not supplied yet" block from the prototype
/// (`.ph { background-image: repeating-linear-gradient(115deg, ...) }`),
/// with a monospace size label centered on top. Swap for a real `Image`
/// widget once photography is available — the label text stays useful as
/// the `semanticLabel` / alt text in the meantime.
class PlaceholderBox extends StatelessWidget {
  const PlaceholderBox({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.borderRadius = 14,
  });

  final String label;

  /// Defaults to the current [AppColors.photoPlaceholder] — resolved at
  /// build time (not a constructor default) since that field changes with
  /// the light/dark toggle.
  final Color? backgroundColor;
  final Color? textColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        color: backgroundColor ?? AppColors.photoPlaceholder,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _StripePainter(color: AppColors.txt.withOpacity(0.055))),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? AppColors.txt.withOpacity(0.45),
                    letterSpacing: 0.4,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter({required this.color});

  final Color color;

  static const double _angleDeg = 115;
  static const double _stripeWidth = 7;
  static const double _gapWidth = 8;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..color = color;
    final period = _stripeWidth + _gapWidth;
    final diagonal = size.width + size.height;
    final angle = _angleDeg * 3.1415926535 / 180;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    for (double x = -diagonal; x < diagonal; x += period) {
      canvas.drawRect(
        Rect.fromLTWH(x, -diagonal, _stripeWidth, diagonal * 2),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StripePainter oldDelegate) =>
      oldDelegate.color != color;
}
