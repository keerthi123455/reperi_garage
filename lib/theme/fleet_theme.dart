import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// Colours for the fleet screens (login, dashboard, request pickup, request
/// details). Follows the app's light / dark setting (themeController), which
/// the fleet dashboard can switch with its ☀️ / 🌙 button.
class F {
  F._();

  static bool get dark => themeController.isDark;

  static Color get bg => dark ? const Color(0xFF121417) : const Color(0xFFF6F5F1);
  static Color get card => dark ? const Color(0xFF1C1F24) : Colors.white;
  static Color get sunken => dark ? const Color(0xFF23272D) : const Color(0xFFF1EFE9);
  static Color get line => dark ? const Color(0xFF2E333A) : const Color(0xFFE3E0D8);
  static Color get txt => dark ? const Color(0xFFF2F1EC) : const Color(0xFF15171A);
  static Color get mut => dark ? const Color(0xFFA9ADB5) : const Color(0xFF5F6168);
  static Color get faint => dark ? const Color(0xFF7D828B) : const Color(0xFF94969B);

  /// Text / icons / outlines that should stand out: navy in light, yellow in dark.
  static Color get accent => dark ? yellow : navy;

  static const Color navy = Color(0xFF022B57);
  static const Color yellow = Color(0xFFFDF003);

  static Color get green => dark ? const Color(0xFF4ADE80) : const Color(0xFF17803D);
  static Color get greenBg => dark ? const Color(0xFF14321F) : const Color(0xFFE3F6E8);
  static const Color greenSolid = Color(0xFF17803D);
  static Color get red => dark ? const Color(0xFFFF6B6E) : const Color(0xFFD93A3F);
  static Color get redBg => dark ? const Color(0xFF3A1A1C) : const Color(0xFFFDE8E8);
  static const Color redSolid = Color(0xFFE5484D);
  static Color get blue => dark ? const Color(0xFF8AB4FF) : const Color(0xFF1A4FB5);
  static Color get blueBg => dark ? const Color(0xFF16263F) : const Color(0xFFE6EEFF);
  static Color get amber => dark ? const Color(0xFFFDE68A) : const Color(0xFF8A5A00);
  static Color get amberBg => dark ? const Color(0xFF3A3310) : const Color(0xFFFFF4C2);

  static BoxDecoration box({Color? border, double radius = 20, double width = 1, Color? color}) => BoxDecoration(
        color: color ?? card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? line, width: width),
        boxShadow: dark
            ? null
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
      );

  static InputDecoration input(String hint, {Widget? prefixIcon, Widget? suffixIcon}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: faint, fontSize: 17, fontWeight: FontWeight.w600),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: line, width: 2)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: line, width: 2)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 2)),
      );

  /// Fleet request steps, in order.
  static const List<String> steps = ['Requested', 'Picked up', 'In garage', 'Done'];

  /// 0–3: which step a fleet request is on ('Pending', 'Picked Up', 'In Garage', 'Completed').
  static int stepOf(String? status) {
    final s = (status ?? '').toLowerCase();
    if (s.contains('complete') || s.contains('deliver') || s == 'done') return 3;
    if (s.contains('garage')) return 2;
    if (s.contains('picked')) return 1;
    return 0;
  }

  static String statusLabel(String? status) => steps[stepOf(status)];

  /// Colour pair for a step (text, background).
  static (Color, Color) stepColors(int step) => switch (step) {
        3 => (green, greenBg),
        2 => (blue, blueBg),
        1 => (blue, blueBg),
        _ => (amber, amberBg),
      };
}

/// The light / dark switch button used in the fleet screens' headers.
class FleetThemeButton extends StatelessWidget {
  const FleetThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = F.dark;
    return Tooltip(
      message: dark ? 'Switch to light mode' : 'Switch to dark mode',
      child: Material(
        color: F.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: themeController.toggle,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: F.line),
            ),
            child: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: F.accent, size: 23),
          ),
        ),
      ),
    );
  }
}

/// Square header button (back, log out…).
class FleetIconButton extends StatelessWidget {
  const FleetIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.badge = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: F.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: F.line),
                ),
                child: Icon(icon, color: F.accent, size: 23),
              ),
            ),
          ),
          if (badge)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: F.redSolid,
                  shape: BoxShape.circle,
                  border: Border.all(color: F.card, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small rounded tag ("Picked up", "⚠ Approve work"…).
class FleetPill extends StatelessWidget {
  const FleetPill(this.text, {super.key, required this.fg, required this.bg, this.icon});

  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4-part progress bar with step names underneath.
class FleetProgressBar extends StatelessWidget {
  const FleetProgressBar({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < F.steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= step ? F.greenSolid : F.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            for (var i = 0; i < F.steps.length; i++)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: i == 0
                      ? Alignment.centerLeft
                      : (i == F.steps.length - 1 ? Alignment.centerRight : Alignment.center),
                  child: Text(
                    F.steps[i],
                    maxLines: 1,
                    style: TextStyle(
                      color: i == step ? F.txt : F.mut,
                      fontSize: 12,
                      fontWeight: i == step ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Mixin for fleet screens: rebuild when light / dark is switched.
mixin FleetThemeListener<T extends StatefulWidget> on State<T> {
  void _onFleetTheme() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onFleetTheme);
  }

  @override
  void dispose() {
    themeController.removeListener(_onFleetTheme);
    super.dispose();
  }
}
