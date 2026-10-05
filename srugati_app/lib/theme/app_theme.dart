import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SruGati brand tokens — premium dark navy base with soft purple-blue
/// accents (the Music Practice brief's direction). `teal` is the mint
/// "active / confirmed" accent; `purple`/`purpleDeep` form the brand gradient.
class AppColors {
  AppColors._();

  static const purple = Color(0xFF9A8CFF);
  static const purpleDeep = Color(0xFF6C5CE7);
  static const teal = Color(0xFF5BE3B0);
  static const tealLight = Color(0xFF8FF0CB);
  static const warning = Color(0xFFFFB454);

  static const background = Color(0xFF0A0E2A);
  static const surface = Color(0xFF131A45);
  static const surfaceMuted = Color(0xFF1E2760);

  static const textPrimary = Color(0xFFF1F2FF);
  static const textSecondary = Color(0xFF9CA6DC);

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

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
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
        onSurface: AppColors.textPrimary,
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
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.purple,
        inactiveTrackColor: AppColors.surfaceMuted,
        thumbColor: AppColors.purple,
        overlayColor: AppColors.purple.withValues(alpha: 0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.purpleDeep : AppColors.surfaceMuted,
        ),
      ),
    );
  }
}
