import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A row of small pill dots marking which item of a horizontal scroller is
/// currently active — the active dot stretches into a pill, the rest stay
/// small circles. Shared by the vehicle carousel, the 3D coverflow, and the
/// flat 2-up service banner row.
class DotIndicatorRow extends StatelessWidget {
  const DotIndicatorRow({
    super.key,
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: on ? 18 : 5,
          height: 4,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : AppColors.txt.withOpacity(0.22),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
