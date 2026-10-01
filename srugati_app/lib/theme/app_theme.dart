import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SruGati brand tokens — "Midnight Indigo / Gold" (wireframe variant B).
/// Names kept as `purple`/`teal` for minimal call-site churn, but they now
/// hold the indigo/gold palette, not literal purple/teal.
class AppColors {
  AppColors._();

  static const purple = Color(0xFF2E2560);
  static const purpleDeep = Color(0xFF4A3D8F);
  static const teal = Color(0xFFE8B84B);
  static const tealLight = Color(0xFFF0CC7A);

  static const background = Color(0xFFF5F3FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFE7E2F2);

  static const textPrimary = Color(0xFF1B1730);
  static const textSecondary = Color(0xFF6E6B85);

  static const brandGradient = LinearGradient(
    colors: [purple, purpleDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const brandGradientVertical = LinearGradient(
    colors: [purple, purpleDeep],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.purple,
        secondary: AppColors.teal,
        surface: AppColors.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.purple,
        inactiveTrackColor: AppColors.surfaceMuted,
        thumbColor: AppColors.teal,
        overlayColor: AppColors.teal.withValues(alpha: 0.15),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.purple,
        unselectedItemColor: AppColors.textSecondary,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
