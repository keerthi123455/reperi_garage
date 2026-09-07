import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

class BenefitsStrip extends StatelessWidget {
  const BenefitsStrip({super.key});

  static const _items = [
    (icon: Symbols.replay, title: 'Cancel Anytime', sub: 'No lock-in period'),
    (icon: Symbols.percent, title: 'Save More', sub: 'Up to 32% off jobs'),
    (icon: Symbols.tune, title: 'Flexible Plan', sub: 'Switch any month'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceSunken,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i != 0)
              Container(
                width: 1,
                height: 40,
                color: AppColors.line,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
            Expanded(child: _BenefitItem(item: _items[i])),
          ],
        ],
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  const _BenefitItem({required this.item});

  final ({IconData icon, String title, String sub}) item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.icon, size: 20, color: AppColors.accent),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.sub,
                style: GoogleFonts.manrope(
                  fontSize: 9.5,
                  color: AppColors.mut,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
