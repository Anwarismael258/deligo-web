import 'package:flutter/material.dart';

/// Deligo app color system.
class AppColors {
  // Brand anchors.
  static const Color primaryGreen = Color(0xFF1DB954);
  static const Color primaryRed = Color(0xFFE53935);
  static const Color accentYellow = Color(0xFFFFC107);
  static const Color primaryOrange = Color(0xFFFF8A3D);
  static const Color ratingGold = Color(0xFFF5A623);
  static const Color infoBlue = Color(0xFF2563EB);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color deepBlack = Color(0xFF121212);

  // Legacy aliases kept for compatibility with the current codebase.
  static const Color successGreen = primaryGreen;
  static const Color alertRed = primaryRed;

  // Splash gradient.
  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient actionGradient = LinearGradient(
    colors: [Color(0xFF22C55E), Color(0xFF1DB954)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Core neutrals.
  static const Color cleanWhite = Color(0xFFFFFFFF);
  static const Color neutralGray = Color(0xFF62666B);
  static const Color darkGray = Color(0xFF333333);
  static const Color lightGray = Color(0xFFF7F8FA);
  static const Color borderGray = Color(0xFFE0E0E0);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color softBackground = Color(0xFFF4F6F5);
  static const Color clientBackground = Color(0xFFFFFBFA);
  static const Color softRedBackground = Color(0xFFFFF3F1);
  static const Color softGreenBackground = Color(0xFFF1FBF5);
  static const Color softOrangeBackground = Color(0xFFFFF7F0);

  // Ripple system.
  static Color get rippleBase => primaryGreen.withValues(alpha: 0.14);
  static Color get rippleInteractive => accentYellow.withValues(alpha: 0.18);
  static Color get glowInteractive => primaryGreen.withValues(alpha: 0.18);
  static List<Color> get wowRipplePalette => const [
    primaryGreen,
    primaryRed,
    accentYellow,
  ];
}
