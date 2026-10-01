import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Big circular readout for a detected note — the tuner-style focal point
/// of the Studio and Practice screens.
class NoteDial extends StatelessWidget {
  final String? note;
  final int? octave;
  final double? frequencyHz;
  final double confidence;
  final double size;

  const NoteDial({
    super.key,
    required this.note,
    required this.octave,
    required this.frequencyHz,
    required this.confidence,
    this.size = 220,
  });

  @override
  Widget build(BuildContext context) {
    final hasResult = note != null;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: hasResult ? confidence.clamp(0.0, 1.0) : 0,
              strokeWidth: 10,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: const AlwaysStoppedAnimation(AppColors.teal),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasResult ? note! : '—',
                style: TextStyle(
                  fontSize: size * 0.24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasResult ? '${frequencyHz!.toStringAsFixed(1)} Hz' : 'Waiting…',
                style: TextStyle(fontSize: size * 0.07, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
