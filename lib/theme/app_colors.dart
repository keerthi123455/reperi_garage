import 'package:flutter/material.dart';

/// Colour tokens lifted from the Claude Design prototype's `:root` custom
/// properties (`--acc`, `--acc2`, `--ink`, `--txt`, `--mut`, `--line`).
///
/// Most fields are mutable `static Color`s (not `const`) rather than fixed
/// constants — [applyMode] repaints them in place when the light/dark
/// toggle flips, and every widget that reads `AppColors.xxx` picks up the
/// new value on its next rebuild automatically, with no per-widget changes
/// needed. [ThemeController] (`theme_controller.dart`) owns calling
/// [applyMode] and triggering that rebuild.
class AppColors {
  const AppColors._();

  // Brand colours — identical in both modes.
  static const Color accent = Color(0xFFE3B23C);

  /// `color-mix(in oklab, var(--acc), #000 26%)` from the prototype —
  /// pre-computed as a linear RGB blend of [accent] toward black (close
  /// enough for a solid fill) so it stays usable inside `const` gradients.
  static const Color accent2 = Color(0xFFA9842C);

  /// Text/icon colour painted on top of a solid gold ([accent]) surface —
  /// independent of light/dark mode since it's about contrast against
  /// gold, not against the page background.
  static const Color onAccentDark = Color(0xFF12100B);
  static const Color onAccentDarker = Color(0xFF15120A);

  // Theme-dependent surfaces — mutated by [applyMode]. The app now starts in
  // LIGHT mode, so these start with the light values (same as applyMode(false)).
  static Color ink = const Color(0xFFEFEFED);
  static Color txt = onAccentDark;
  static Color surfaceRaised = const Color(0xFFFCFCFC);
  static Color surfaceSunken = const Color(0xFFEFEFED);
  static Color chipBg = const Color(0xFFFCFCFC);
  static Color photoPlaceholder = const Color(0xFFEFEFED);
  static Color toastBg = const Color(0xFFFCFCFC);
  static Color activeCardGradientStart = const Color(0xFFFCFCFC);
  static Color activeCardGradientEnd = const Color(0xFFEFEFED);

  /// Muted text — always derived from the current [txt], so it stays
  /// correct across a mode switch without needing its own field.
  static Color get mut => txt.withOpacity(_isDark ? 0.62 : 0.52);

  /// Hairline borders — same derivation as [mut].
  static Color get line => txt.withOpacity(_isDark ? 0.12 : 0.10);

  static bool _isDark = false;
  static bool get isDark => _isDark;

  /// Repaints every theme-dependent field for [isDark] true (the
  /// prototype's original dark/gold palette) or false (light mode, using
  /// the two neutral shades the user supplied: `#FCFCFC` and `#EFEFED`).
  static void applyMode({required bool isDark}) {
    _isDark = isDark;
    if (isDark) {
      // Softer charcoal (was near-black #08080A with cards almost the same
      // shade): the page is a dark grey, cards sit clearly lighter on it,
      // and text is a warm off-white rather than bright white.
      ink = const Color(0xFF17181C);
      txt = const Color(0xFFEDEAE3);
      surfaceRaised = const Color(0xFF23252B);
      surfaceSunken = const Color(0xFF1C1E22);
      chipBg = const Color(0xFF26282E);
      photoPlaceholder = const Color(0xFF2C2E34);
      toastBg = const Color(0xFF2A2C32);
      activeCardGradientStart = const Color(0xFF2A2C32);
      activeCardGradientEnd = const Color(0xFF23252B);
    } else {
      ink = const Color(0xFFEFEFED);
      txt = onAccentDark; // near-black, matches the brand's warm neutral.
      surfaceRaised = const Color(0xFFFCFCFC);
      surfaceSunken = const Color(0xFFEFEFED);
      chipBg = const Color(0xFFFCFCFC);
      photoPlaceholder = const Color(0xFFEFEFED);
      toastBg = const Color(0xFFFCFCFC);
      activeCardGradientStart = const Color(0xFFFCFCFC);
      activeCardGradientEnd = const Color(0xFFEFEFED);
    }
  }
}
