import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Premium blue-and-white RO palette.
  static const Color primaryLight = Color(0xFF0F62FE);
  static const Color secondaryLight = Color(0xFF3478D4);
  static const Color accentLight = Color(0xFFB9D9FF);
  static const Color backgroundLight = Color(0xFFF4F8FE);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color errorLight = Color(0xFFD32F2F); // Alert Red
  static const Color warningLight = Color(0xFFF57C00); // Warning Orange
  static const Color successLight = Color(0xFF388E3C); // Purified Green

  // Water/RO Themed Palette - Dark Theme
  static const Color primaryDark = Color(0xFF8BBEFF);
  static const Color secondaryDark = Color(0xFF5A9BEE);
  static const Color accentDark = Color(0xFFB9D9FF);
  static const Color backgroundDark = Color(0xFF0B1423);
  static const Color surfaceDark = Color(0xFF142238);
  static const Color errorDark = Color(0xFFE57373);
  static const Color warningDark = Color(0xFFFFB74D);
  static const Color successDark = Color(0xFF81C784);

  // Neutral Colors (Shared)
  static const Color textPrimaryLight = Color(0xFF172B46);
  static const Color textSecondaryLight = Color(0xFF61758F);
  static const Color textPrimaryDark = Color(0xFFF0F6FF);
  static const Color textSecondaryDark = Color(0xFFA3B4CC);

  // Gradients
  static const LinearGradient waterGradientLight = LinearGradient(
    colors: [primaryLight, secondaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient waterGradientDark = LinearGradient(
    colors: [Color(0xFF123366), Color(0xFF245AA3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Colors.white24, Colors.white10],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
