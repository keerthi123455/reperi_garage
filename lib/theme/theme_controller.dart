import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// App-wide dark/light switch. Kept as a plain singleton `ChangeNotifier`
/// (not routed through `InheritedWidget`/state-management) so the small
/// toggle in [AppHeader] and the root [ReperiGarageApp] can both reach it
/// without prop-drilling — flipping it mutates [AppColors]'s fields in
/// place via [AppColors.applyMode] and notifies listeners to trigger a
/// full-tree rebuild, so every widget's next `build()` re-reads the new
/// colours automatically.
class ThemeController extends ChangeNotifier {
  ThemeController() {
    _applySystemOverlay();
  }

  bool get isDark => AppColors.isDark;

  void toggle() => setDark(!isDark);

  void setDark(bool value) {
    if (value == isDark) return;
    AppColors.applyMode(isDark: value);
    _applySystemOverlay();
    notifyListeners();
  }

  void _applySystemOverlay() {
    SystemChrome.setSystemUIOverlayStyle(
      isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
  }
}

final themeController = ThemeController();
