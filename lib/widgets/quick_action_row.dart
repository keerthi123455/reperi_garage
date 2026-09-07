import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// The "BOOK SERVICE" / "BOOK WASHING" quick-action row shown below the
/// vehicle tile — two equal-width buttons (each roughly half the vehicle
/// tile's width) with the same gold-tinted chrome as the active vehicle
/// card's border.
class QuickActionRow extends StatelessWidget {
  const QuickActionRow({
    super.key,
    required this.onBookService,
    required this.onBookWashing,
  });

  final VoidCallback onBookService;
  final VoidCallback onBookWashing;

  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            icon: Symbols.build,
            label: 'Book Service',
            onTap: onBookService,
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: _QuickActionButton(
            icon: Symbols.local_car_wash,
            label: 'Book Washing',
            onTap: onBookWashing,
          ),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppColors.surfaceRaised,
            border: Border.all(color: AppColors.accent.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.manrope(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.txt,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
