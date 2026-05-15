import 'package:flutter/material.dart';

/// Task Nibbles colour palette.
abstract final class AppColors {
  /// Primary seed — leafy green, ties to the tree motif (BLU-004 §10).
  static const seedGreen = Color(0xFF4CAF50);

  /// Accent shades (light)
  static const greenLight = Color(0xFFA5D6A7);
  static const greenDark = Color(0xFF2E7D32);

  /// Semantic colours
  static const priorityCritical = Color(0xFFD32F2F);
  static const priorityHigh = Color(0xFFFF7043);
  static const priorityMedium = Color(0xFFFFA726);
  static const priorityLow = Color(0xFF66BB6A);

  /// Gamification hero gradient
  static const heroGradientStart = Color(0xFF2E7D32);
  static const heroGradientEnd = Color(0xFF66BB6A);

  /// Offline banner
  static const offlineBanner = Color(0xFF616161);
}
