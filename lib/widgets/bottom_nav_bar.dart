import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

typedef _NavEntry = ({int index, IconData icon, String label});

const List<_NavEntry> _kNavEntries = [
  (index: 0, icon: Symbols.home, label: 'Home'),
  (index: 1, icon: Symbols.calendar_month, label: 'Bookings'),
  (index: 3, icon: Symbols.handyman, label: 'Services'),
  (index: 4, icon: Symbols.person, label: 'Profile'),
];

/// The frosted-glass 5-column tab bar (`grid-template-columns:repeat(5,1fr)`
/// in the prototype, with the 3rd column left empty for the floating
/// "Ask AI" button to sit above).
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: 92 + bottomInset,
          padding: EdgeInsets.only(top: 12, bottom: bottomInset),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.ink.withOpacity(0.4), AppColors.ink],
              stops: const [0, 0.4],
            ),
          ),
          child: Row(
            children: [
              _tab(_kNavEntries[0]),
              _tab(_kNavEntries[1]),
              const Expanded(child: SizedBox()),
              _tab(_kNavEntries[2]),
              _tab(_kNavEntries[3]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(_NavEntry entry) {
    final active = entry.index == currentIndex;
    final color = active ? AppColors.accent : AppColors.mut;
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(entry.index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(entry.icon, size: 23, color: color),
            const SizedBox(height: 5),
            Text(
              entry.label,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
