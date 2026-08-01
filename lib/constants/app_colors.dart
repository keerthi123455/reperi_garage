import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const gold = Color(0xFFD4A017); // Accent color (unchanged)
  static const yellow = Color(0xFFFFD600);
  static const white = Color(0xFFF7F7F7);
  static const grey = Color(0xFFBDBDBD);
  static const lightGrey = Color(0xFFEAEAEA);
  
  // Dark Theme Background Colors (Lighter for better readability)
  static const darkBg0 = Color(0xFF1A1A1A);      // Darkest - replaces 0xFF0A0A0A
  static const darkBg1 = Color(0xFF2A2A2A);      // Dark - replaces 0xFF111111
  static const darkBg2 = Color(0xFF3A3A3A);      // Medium Dark - replaces 0xFF1A1A1A
  static const darkBg3 = Color(0xFF4A4A4A);      // Medium - replaces 0xFF2A2A2A
  static const darkBg4 = Color(0xFF555555);      // Light Medium - replaces 0xFF333333
  static const darkBg5 = Color(0xFF666666);      // Lighter - replaces 0xFF444444
  static const darkBg6 = Color(0xFF777777);      // Lightest Dark - replaces 0xFF555555
  
  // Text Colors for Dark Theme
  static const darkText1 = Color(0xFFFFFFFF);    // Primary text (white)
  static const darkText2 = Color(0xFFE0E0E0);    // Secondary text (light gray)
  static const darkText3 = Color(0xFFA0A0A0);    // Tertiary text (medium gray)
  
  // Legacy compatibility (kept for gradual migration)
  static const black = Color(0xFF2A2A2A);
}