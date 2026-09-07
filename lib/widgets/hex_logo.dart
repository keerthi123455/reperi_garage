import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// The hexagonal "REPERI" wordmark badge — `clip-path: polygon(50% 0, 100%
/// 26%, 100% 74%, 50% 100%, 0 74%, 0 26%)` in the prototype, filled with the
/// gold gradient and a centered wrench glyph.
class HexLogo extends StatelessWidget {
  const HexLogo({super.key, this.width = 30, this.height = 33});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _HexClipper(),
      child: Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.64, -1),
            end: Alignment(0.64, 1),
            colors: [Color(0xFFF3CE72), AppColors.accent, AppColors.accent2],
            stops: [0, 0.55, 1],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Symbols.build,
          size: 19,
          color: AppColors.onAccentDark,
          weight: 400,
          fill: 0,
        ),
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.26)
      ..lineTo(w, h * 0.74)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.74)
      ..lineTo(0, h * 0.26)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
