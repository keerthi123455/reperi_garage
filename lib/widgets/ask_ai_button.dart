import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

class AskAiButton extends StatelessWidget {
  const AskAiButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ink, width: 5),
            gradient: const LinearGradient(
              begin: Alignment(-0.36, -1),
              end: Alignment(0.36, 1),
              colors: [Color(0xFFF6D889), AppColors.accent, AppColors.accent2],
              stops: [0, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.4),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.auto_awesome,
                  size: 22, color: AppColors.onAccentDarker, weight: 400),
              const SizedBox(height: 1),
              Text(
                'ASK AI',
                style: GoogleFonts.manrope(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: AppColors.onAccentDarker,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
