import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// The "OUR / PACKAGES →" side heading pinned to the left of the coverflow.
/// [opacity] is driven by how close the coverflow's current position is to
/// the first banner (index 0) — fully visible there, fading out as soon as
/// the user scrolls away, and back in when they return to it.
class PackagesSideHeading extends StatelessWidget {
  const PackagesSideHeading({super.key, required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'OUR',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppColors.mut,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'PACKAGES',
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 10),
            Icon(Symbols.arrow_forward, size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
