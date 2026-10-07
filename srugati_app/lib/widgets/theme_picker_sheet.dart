import 'package:flutter/material.dart';

import '../services/theme_settings.dart';
import '../theme/app_theme.dart';
import 'custom_color_sheet.dart';

/// Bottom sheet for choosing the app's colour preset.
class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const ThemePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<ThemePreset>(
          valueListenable: ThemeSettings.preset,
          builder: (context, current, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Theme',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Pick a colour scheme, or make your own.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 16,
                children: [
                  for (final preset in kThemePresets)
                    GestureDetector(
                      onTap: () => ThemeSettings.select(preset),
                      child: SizedBox(
                        width: 92,
                        child: Column(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: preset.surface,
                                border: Border.all(
                                  color: preset.id == current.id
                                      ? Colors.white
                                      : preset.surfaceMuted,
                                  width: preset.id == current.id ? 2.5 : 1.5,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: preset.gradient,
                                    shape: BoxShape.circle,
                                  ),
                                  child: preset.id == current.id
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              preset.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => CustomColorSheet.show(context),
                    child: SizedBox(
                      width: 92,
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: current.surface,
                              border: Border.all(
                                color: current.id == 'custom'
                                    ? Colors.white
                                    : current.surfaceMuted,
                                width: current.id == 'custom' ? 2.5 : 1.5,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: current.id == 'custom'
                                      ? current.gradient
                                      : const SweepGradient(
                                          colors: [
                                            Color(0xFFFF6B6B),
                                            Color(0xFFFFD166),
                                            Color(0xFF5BE3B0),
                                            Color(0xFF4FB3FF),
                                            Color(0xFF9A8CFF),
                                            Color(0xFFF472B6),
                                            Color(0xFFFF6B6B),
                                          ],
                                        ),
                                ),
                                child: Icon(
                                  current.id == 'custom'
                                      ? Icons.check_rounded
                                      : Icons.colorize_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Custom',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
