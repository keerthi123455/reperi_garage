import 'package:flutter/material.dart';

/// A more deliberate page transition than the platform default — the
/// incoming screen fades in while rising slightly and scaling up from a
/// hair smaller, rather than the flat slide-over `MaterialPageRoute` gives.
/// The reverse (back button, edge swipe) mirrors it exactly since both
/// directions are driven by the same [CurvedAnimation].
///
/// Drop this in wherever `Navigator.push(context, MaterialPageRoute(builder:
/// ...))` is used today. home_screen.dart's `_openPollutionScreen` is the
/// first screen using it, as a trial before rolling it out further.
Route<T> premiumPageRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
