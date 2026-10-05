import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An original SruGati mark: a curved "string" (Sruti — the drone/pitch)
/// resolving into a sound wave (Gati — the movement/rhythm), entirely
/// code-drawn so nothing is carried over from any prior asset.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BrandMarkPainter()),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gradientPaint = Paint()
      ..shader = AppColors.brandGradient.createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;

    // The "string": a single curved arc, evoking a tanpura string / sruti drone.
    final stringPath = Path()
      ..moveTo(w * 0.18, h * 0.28)
      ..quadraticBezierTo(w * 0.05, h * 0.55, w * 0.22, h * 0.78);
    canvas.drawPath(stringPath, gradientPaint);

    // The "wave": resolves into a sound-wave motif, evoking gati (motion).
    final wavePath = Path()..moveTo(w * 0.30, h * 0.62);
    wavePath.lineTo(w * 0.40, h * 0.62);
    wavePath.lineTo(w * 0.47, h * 0.32);
    wavePath.lineTo(w * 0.56, h * 0.82);
    wavePath.lineTo(w * 0.64, h * 0.50);
    wavePath.lineTo(w * 0.71, h * 0.62);
    wavePath.lineTo(w * 0.86, h * 0.62);
    canvas.drawPath(
      wavePath,
      gradientPaint
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // A small dot where the string meets the wave, tying the two halves together.
    canvas.drawCircle(
      Offset(w * 0.30, h * 0.62),
      w * 0.045,
      Paint()..color = AppColors.teal,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
