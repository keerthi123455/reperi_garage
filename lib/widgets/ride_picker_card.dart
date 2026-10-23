import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import 'vehicle_card.dart' show VehicleCartoonAvatar;

/// Home screen, for guests and customers with no vehicle saved yet:
/// "What do you ride?  Car · Bike · Both". The choice decides which
/// packages Home shows (car, bike, or a Car | Bike switch for both).
/// Once a vehicle is added, Home shows the normal vehicle card instead.
///
/// [value] is 'car' | 'bike' | 'both'.
class RidePickerCard extends StatelessWidget {
  const RidePickerCard({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onAddVehicle,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddVehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you ride?',
            style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.txt),
          ),
          const SizedBox(height: 2),
          Text(
            "We'll show the right services.",
            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.mut),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _option('car', 'Car', const VehicleCartoonAvatar(isBike: false, size: 44)),
              const SizedBox(width: 8),
              _option('bike', 'Bike', const VehicleCartoonAvatar(isBike: true, size: 44)),
              const SizedBox(width: 8),
              _option(
                'both',
                'Both',
                const SizedBox(
                  width: 64,
                  height: 44,
                  child: Stack(
                    children: [
                      Positioned(left: 0, top: 0, child: VehicleCartoonAvatar(isBike: false, size: 40)),
                      Positioned(right: 0, bottom: 0, child: VehicleCartoonAvatar(isBike: true, size: 40)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddVehicle,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              icon: const Icon(Symbols.add_circle, size: 20),
              label: Text(
                'Add your vehicle',
                style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(String key, String label, Widget art) {
    final selected = value == key;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line,
                width: selected ? 1.6 : 1.2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(fit: BoxFit.scaleDown, child: art),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.txt,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Car | Bike switch shown under [RidePickerCard] when "Both" is picked.
/// [value] is 'car' | 'bike'.
class CarBikeSwitch extends StatelessWidget {
  const CarBikeSwitch({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String key, String label, bool isBike) {
      final selected = value == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(key),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: selected ? 1 : 0.6,
                      child: VehicleCartoonAvatar(isBike: isBike, size: 28),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: selected ? AppColors.txt : AppColors.mut,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          seg('car', 'Car', false),
          seg('bike', 'Bike', true),
        ],
      ),
    );
  }
}
