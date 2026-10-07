import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One selectable colour scheme. All presets share the premium dark base;
/// they differ in the accent gradient and the tint of the navy surfaces.
class ThemePreset {
  final String id;
  final String name;
  final Color primary;
  final Color primaryDeep;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceMuted;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryDeep,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
  });

  LinearGradient get gradient => LinearGradient(
    colors: [primary, primaryDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Builds a whole scheme from one chosen colour. The colour sets the hue;
  /// saturation and lightness are kept in a range that stays readable on the
  /// dark surfaces, and the navy backgrounds are tinted with the same hue.
  factory ThemePreset.fromColor(
    Color base, {
    String id = 'custom',
    String name = 'Custom',
  }) {
    final hsl = HSLColor.fromColor(base);
    final h = hsl.hue;
    final s = hsl.saturation.clamp(0.45, 1.0);
    final l = hsl.lightness.clamp(0.5, 0.8);
    Color c(double hue, double sat, double light) =>
        HSLColor.fromAHSL(1, hue % 360, sat, light).toColor();
    return ThemePreset(
      id: id,
      name: name,
      primary: c(h, s, l),
      primaryDeep: c(h, s, (l - 0.2).clamp(0.3, 0.7)),
      accent: c(h + 140, 0.7, 0.66),
      background: c(h, 0.58, 0.10),
      surface: c(h, 0.54, 0.17),
      surfaceMuted: c(h, 0.5, 0.25),
    );
  }
}

const kThemePresets = <ThemePreset>[
  ThemePreset(
    id: 'violet',
    name: 'Violet',
    primary: Color(0xFF9A8CFF),
    primaryDeep: Color(0xFF6C5CE7),
    accent: Color(0xFF5BE3B0),
    background: Color(0xFF0A0E2A),
    surface: Color(0xFF131A45),
    surfaceMuted: Color(0xFF1E2760),
  ),
  ThemePreset(
    id: 'ocean',
    name: 'Ocean',
    primary: Color(0xFF4FB3FF),
    primaryDeep: Color(0xFF2563EB),
    accent: Color(0xFF5BE3D0),
    background: Color(0xFF06142A),
    surface: Color(0xFF0D2347),
    surfaceMuted: Color(0xFF16335F),
  ),
  ThemePreset(
    id: 'emerald',
    name: 'Emerald',
    primary: Color(0xFF34C38F),
    primaryDeep: Color(0xFF138A63),
    accent: Color(0xFFFFD166),
    background: Color(0xFF06201A),
    surface: Color(0xFF0D3027),
    surfaceMuted: Color(0xFF16463A),
  ),
  ThemePreset(
    id: 'sunset',
    name: 'Sunset',
    primary: Color(0xFFFF8A65),
    primaryDeep: Color(0xFFE5484D),
    accent: Color(0xFFFFD166),
    background: Color(0xFF1F0E14),
    surface: Color(0xFF2E1520),
    surfaceMuted: Color(0xFF45202F),
  ),
  ThemePreset(
    id: 'rose',
    name: 'Rose',
    primary: Color(0xFFF472B6),
    primaryDeep: Color(0xFFC026D3),
    accent: Color(0xFF7CF0D0),
    background: Color(0xFF1D0A23),
    surface: Color(0xFF2B1236),
    surfaceMuted: Color(0xFF401B4F),
  ),
];

/// SruGati colour tokens. They read the active [ThemePreset], so changing the
/// preset recolours the app. `purple`/`purpleDeep` are the brand gradient
/// pair and `teal` the "active / confirmed" accent (names kept for history).
class AppColors {
  AppColors._();

  static ThemePreset _preset = kThemePresets.first;
  static ThemePreset get preset => _preset;
  static void apply(ThemePreset preset) => _preset = preset;

  static Color get purple => _preset.primary;
  static Color get purpleDeep => _preset.primaryDeep;
  static Color get teal => _preset.accent;
  static Color get tealLight => Color.lerp(_preset.accent, Colors.white, 0.35)!;
  static const warning = Color(0xFFFFB454);

  static Color get background => _preset.background;
  static Color get surface => _preset.surface;
  static Color get surfaceMuted => _preset.surfaceMuted;

  static const textPrimary = Color(0xFFF1F2FF);
  static const textSecondary = Color(0xFF9CA6DC);

  static LinearGradient get brandGradient => _preset.gradient;

  static LinearGradient get brandGradientVertical => LinearGradient(
    colors: [purple, purpleDeep],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// Slider track whose filled part uses the brand gradient (as in the design
/// mockups) instead of a flat colour.
class GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  const GradientSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor ?? AppColors.surfaceMuted,
    );

    final active = Rect.fromLTRB(
      rect.left,
      rect.top,
      thumbCenter.dx.clamp(rect.left, rect.right),
      rect.bottom,
    );
    if (active.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(active, radius),
        Paint()
          ..shader = LinearGradient(
            colors: [AppColors.purpleDeep, AppColors.purple],
          ).createShader(rect),
      );
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData build() {
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
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
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
        trackHeight: 5,
        trackShape: const GradientSliderTrackShape(),
        activeTrackColor: AppColors.purple,
        inactiveTrackColor: AppColors.surfaceMuted,
        thumbColor: Colors.white,
        overlayColor: AppColors.purple.withValues(alpha: 0.18),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.purpleDeep
              : AppColors.surfaceMuted,
        ),
      ),
    );
  }
}
