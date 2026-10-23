import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _prefKey = 'theme_is_dark';

  void setDark(bool value) {
    if (value == isDark) return;
    AppColors.applyMode(isDark: value);
    _applySystemOverlay();
    notifyListeners();
    _save(value);
  }

  /// Called once in main() before the app starts, so the customer's last
  /// choice (light/dark) is back on the very first frame. Light is the
  /// default when nothing was saved yet.
  Future<void> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefKey);
      if (saved != null && saved != isDark) {
        AppColors.applyMode(isDark: saved);
        _applySystemOverlay();
        notifyListeners();
      }
    } catch (_) {
      // Storage unavailable — just stay on the default (light).
    }
  }

  Future<void> _save(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  void _applySystemOverlay() {
    SystemChrome.setSystemUIOverlayStyle(
      isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );
  }
}

final themeController = ThemeController();
