import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A pitch-wheel-style slider: zero sits dead center, dragging right of
/// center increases the value (filled teal), dragging left decreases it
/// (filled purple) — makes "0 in the middle" visually unambiguous rather
/// than relying on a plain Material [Slider] where the fill always starts
/// from the left edge.
class CenteredSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const CenteredSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
  });

  double _valueFromDx(double dx, double width) {
    final ratio = (dx / width).clamp(0.0, 1.0);
    return min + ratio * (max - min);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final zeroX = width * (0 - min) / (max - min);
        final valueX = width * (value - min) / (max - min);

        void handleDrag(Offset localPosition) {
          onChanged(_valueFromDx(localPosition.dx, width));
        }

        return GestureDetector(
          onHorizontalDragUpdate: (details) =>
              handleDrag(details.localPosition),
          onHorizontalDragEnd: (_) => onChangeEnd?.call(value),
          onTapDown: (details) => handleDrag(details.localPosition),
          onTapUp: (_) => onChangeEnd?.call(value),
          child: SizedBox(
            height: 40,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track.
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Fill from center (0) to the current value.
                Positioned(
                  left: value >= 0 ? zeroX : valueX,
                  child: Container(
                    height: 6,
                    width: (valueX - zeroX).abs(),
                    decoration: BoxDecoration(
                      color: value >= 0 ? AppColors.teal : AppColors.purple,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // Center (zero) tick.
                Positioned(
                  left: zeroX - 1,
                  child: Container(
                    width: 2,
                    height: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                // Thumb.
                Positioned(
                  left: (valueX - 11).clamp(-11, width - 11),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.purple, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
