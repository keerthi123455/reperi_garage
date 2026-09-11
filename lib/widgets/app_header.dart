import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'hex_logo.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.onMenu,
    required this.onSearch,
  });

  final VoidCallback onMenu;

  /// Opens the Services screen with its search field focused and ready
  /// to type — this icon used to be a notification bell, but there was
  /// no notification center to open, so it's now a direct search shortcut.
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _IconButtonChip(icon: Symbols.menu, onTap: onMenu),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HexLogo(),
              const SizedBox(width: 10),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7DE9B), AppColors.accent, AppColors.accent2],
                  stops: [0, 0.6, 1],
                ).createShader(bounds),
                child: Text(
                  'REPERI',
                  style: GoogleFonts.manrope(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemeToggleSwitch(
                isDark: themeController.isDark,
                onChanged: (_) => themeController.toggle(),
              ),
              const SizedBox(width: 10),
              _IconButtonChip(
                icon: Symbols.search,
                onTap: onSearch,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small dark/light switch placed next to the notification bell — flipping
/// it calls [ThemeController.toggle], which repaints [AppColors] in place
/// and triggers a full-app rebuild (see `theme_controller.dart`).
class _ThemeToggleSwitch extends StatelessWidget {
  const _ThemeToggleSwitch({required this.isDark, required this.onChanged});

  final bool isDark;
  final ValueChanged<bool> onChanged;

  static const double _width = 52;
  static const double _height = 28;
  static const double _thumbSize = 22;
  static const double _pad = 3;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isDark),
      child: Container(
        width: _width,
        height: _height,
        padding: const EdgeInsets.all(_pad),
        decoration: BoxDecoration(
          color: AppColors.chipBg,
          borderRadius: BorderRadius.circular(_height / 2),
          border: Border.all(color: AppColors.line),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          alignment: isDark ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            width: _thumbSize,
            height: _thumbSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButtonChip extends StatelessWidget {
  const _IconButtonChip({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.chipBg,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Icon(icon, size: 22, color: AppColors.txt, weight: 400, fill: 0),
        ),
      ),
    );
  }
}
