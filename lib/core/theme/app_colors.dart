import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Water/RO Themed Palette - Light Theme
  static const Color primaryLight = Color(0xFF0F4C81);     // Deep Ocean Blue
  static const Color secondaryLight = Color(0xFF00A8CC);   // Pure Aqua Cyan
  static const Color accentLight = Color(0xFF36EEE0);      // Electric Ice Blue
  static const Color backgroundLight = Color(0xFFF7FBFC);  // Soft Water Mist Light Background
  static const Color surfaceLight = Color(0xFFFFFFFF);     // Pure White
  static const Color errorLight = Color(0xFFD32F2F);       // Alert Red
  static const Color warningLight = Color(0xFFF57C00);     // Warning Orange
  static const Color successLight = Color(0xFF388E3C);     // Purified Green

  // Water/RO Themed Palette - Dark Theme
  static const Color primaryDark = Color(0xFF0A2E5C);      // Abyssal Navy Blue
  static const Color secondaryDark = Color(0xFF0081A7);    // Deep Sea Aqua
  static const Color accentDark = Color(0xFF00F5D4);       // Neon Aqua
  static const Color backgroundDark = Color(0xFF0A1118);   // Dark Ocean Depth Background
  static const Color surfaceDark = Color(0xFF131C26);      // Deep Surface Slate Blue
  static const Color errorDark = Color(0xFFE57373);
  static const Color warningDark = Color(0xFFFFB74D);
  static const Color successDark = Color(0xFF81C784);

  // Neutral Colors (Shared)
  static const Color textPrimaryLight = Color(0xFF1A2530); // Deep Charcoal
  static const Color textSecondaryLight = Color(0xFF5A6E7F);// Medium Mist Grey
  static const Color textPrimaryDark = Color(0xFFE4F9F5);  // Very Light Mint/Aqua
  static const Color textSecondaryDark = Color(0xFF8DA2B4);// Muted Steel Grey

  // Gradients
  static const LinearGradient waterGradientLight = LinearGradient(
    colors: [primaryLight, secondaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient waterGradientDark = LinearGradient(
    colors: [primaryDark, secondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Colors.white24, Colors.white10],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
