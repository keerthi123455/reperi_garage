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

  // Theme-dependent surfaces — mutated by [applyMode]. Dark-mode values are
  // the defaults the prototype shipped with.
  static Color ink = const Color(0xFF08080A);
  static Color txt = const Color(0xFFF4F1EA);
  static Color surfaceRaised = const Color(0xFF101012);
  static Color surfaceSunken = const Color(0xFF0E0E10);
  static Color chipBg = const Color(0xFF131316);
  static Color photoPlaceholder = const Color(0xFF1D1D21);
  static Color toastBg = const Color(0xFF1B1B1F);
  static Color activeCardGradientStart = const Color(0xFF17171A);
  static Color activeCardGradientEnd = const Color(0xFF101012);

  /// Muted text — always derived from the current [txt], so it stays
  /// correct across a mode switch without needing its own field.
  static Color get mut => txt.withOpacity(0.52);

  /// Hairline borders — same derivation as [mut].
  static Color get line => txt.withOpacity(0.10);

  static bool _isDark = true;
  static bool get isDark => _isDark;

  /// Repaints every theme-dependent field for [isDark] true (the
  /// prototype's original dark/gold palette) or false (light mode, using
  /// the two neutral shades the user supplied: `#FCFCFC` and `#EFEFED`).
  static void applyMode({required bool isDark}) {
    _isDark = isDark;
    if (isDark) {
      ink = const Color(0xFF08080A);
      txt = const Color(0xFFF4F1EA);
      surfaceRaised = const Color(0xFF101012);
      surfaceSunken = const Color(0xFF0E0E10);
      chipBg = const Color(0xFF131316);
      photoPlaceholder = const Color(0xFF1D1D21);
      toastBg = const Color(0xFF1B1B1F);
      activeCardGradientStart = const Color(0xFF17171A);
      activeCardGradientEnd = const Color(0xFF101012);
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
