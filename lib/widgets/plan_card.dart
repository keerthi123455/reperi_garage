import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/plan.dart';
import '../theme/app_colors.dart';
import 'placeholder_box.dart';

const double kPlanCardWidth = 192;
const double kPlanCardHeight = 376;

/// The static visual content of one subscription-plan card. Positioning,
/// 3D transform, opacity and stacking order are handled by the parent
/// coverflow — this widget only knows how to render itself "selected" or
/// "not selected", mirroring the `on ? ... : ...` ternaries in the
/// prototype's `planVals()`.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
    required this.onSubscribe,
  });

  final Plan plan;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? AppColors.onAccentDarker : AppColors.txt;
    final subColor = selected
        ? AppColors.onAccentDarker.withOpacity(0.66)
        : AppColors.mut;
    final lineColor =
        selected ? AppColors.onAccentDarker.withOpacity(0.22) : AppColors.line;
    final imageBg = selected ? Colors.black.withOpacity(0.22) : const Color(0xFF1C1C20);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: kPlanCardWidth,
        height: kPlanCardHeight,
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment(-0.26, -0.97),
                  end: Alignment(0.26, 0.97),
                  colors: [Color(0xFFF6D889), AppColors.accent, AppColors.accent2],
                  stops: [0, 0.48, 1],
                )
              : null,
          color: selected ? null : AppColors.surfaceRaised,
          border: selected ? null : Border.all(color: AppColors.line),
          boxShadow: selected
              ? [
                  const BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 44,
                    offset: Offset(0, 18),
                  ),
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.25),
                    blurRadius: 34,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 26,
                    offset: Offset(0, 10),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.title,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              plan.subtitle,
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: subColor,
              ),
            ),
            const SizedBox(height: 11),
            SizedBox(
              height: 92,
              width: double.infinity,
              child: PlaceholderBox(
                label: plan.photoLabel,
                backgroundColor: imageBg,
                textColor: subColor,
                borderRadius: 13,
              ),
            ),
            const SizedBox(height: 11),
            for (var i = 0; i < plan.features.length; i++) ...[
              if (i != 0) const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Symbols.check_circle, size: 15, color: textColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      plan.features[i],
                      style: GoogleFonts.manrope(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: lineColor)),
              ),
              child: Row(
                children: [
                  Icon(Symbols.event_available, size: 14, color: subColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      plan.scheduleLabel,
                      style: GoogleFonts.manrope(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: subColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 11),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  plan.price,
                  style: GoogleFonts.manrope(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ month',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: subColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: selected ? const Color(0xFF111014) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onSubscribe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: selected
                          ? null
                          : Border.all(color: AppColors.accent),
                    ),
                    child: Text(
                      'Subscribe Now',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? const Color(0xFFF7DE9B) : AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
