import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Centered single-line section heading: a bold gold label flanked by thin
/// gold rules that fade out towards the outer edges — e.g. "PACKAGES".
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Fades out towards the outer (left) end, solid gold near the text.
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent.withOpacity(0), AppColors.accent],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        // Fades out towards the outer (right) end.
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.accent, AppColors.accent.withOpacity(0)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
