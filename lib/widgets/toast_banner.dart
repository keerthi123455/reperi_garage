import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// The brief confirmation banner (`{{ toast }}` in the prototype) that
/// fades/slides in above the tab bar and self-dismisses after ~2.2s — the
/// dismiss timer lives in [HomeScreen], this widget only renders the
/// current message.
class ToastBanner extends StatelessWidget {
  const ToastBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.toastBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.accent.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.check_circle, size: 19, color: AppColors.accent),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.txt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
