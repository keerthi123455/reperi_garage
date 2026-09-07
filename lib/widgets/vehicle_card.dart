import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import 'placeholder_box.dart';

class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.width,
    required this.onMore,
  });

  final Vehicle vehicle;
  final double width;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final active = vehicle.active;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? AppColors.accent.withOpacity(0.28) : AppColors.line,
        ),
        gradient: active
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.activeCardGradientStart, AppColors.activeCardGradientEnd],
              )
            : null,
        color: active ? null : AppColors.surfaceRaised,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            height: 96,
            child: PlaceholderBox(label: 'CAR PHOTO\n132×96'),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        vehicle.brand,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: AppColors.mut,
                        ),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      _ActiveBadge(),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onMore,
                        child: Icon(Symbols.more_vert,
                            size: 18, color: AppColors.mut),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  vehicle.model,
                  style: GoogleFonts.manrope(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: AppColors.txt,
                    letterSpacing: active ? 0.2 : 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'ACTIVE',
        style: GoogleFonts.manrope(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.onAccentDark,
        ),
      ),
    );
  }
}
