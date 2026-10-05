import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A glowing, rotating "core" used by the Vocal Remover. While a job runs it
/// shows a progress ring; while stems play its radial bars dance to the live
/// frequency spectrum of the music.
class StemOrb extends StatefulWidget {
  final double size;
  final ValueNotifier<List<double>>? spectrum;

  /// 0..1 draws a determinate progress ring; null with [spinning] draws an
  /// endless scanning arc.
  final double? progress;
  final bool spinning;
  final Widget? center;

  const StemOrb({
    super.key,
    this.size = 260,
    this.spectrum,
    this.progress,
    this.spinning = false,
    this.center,
  });

  @override
  State<StemOrb> createState() => _StemOrbState();
}

class _StemOrbState extends State<StemOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: _OrbPainter(
              clock: _controller,
              spectrum: widget.spectrum,
              progress: widget.progress,
              spinning: widget.spinning,
            ),
          ),
          if (widget.center != null) widget.center!,
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final Animation<double> clock;
  final ValueNotifier<List<double>>? spectrum;
  final double? progress;
  final bool spinning;

  _OrbPainter({
    required this.clock,
    required this.spectrum,
    required this.progress,
    required this.spinning,
  }) : super(
         repaint: spectrum == null
             ? clock
             : Listenable.merge([clock, spectrum]),
       );

  static const _bars = 72;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final t = clock.value;
    final purple = AppColors.purple;
    final deep = AppColors.purpleDeep;
    final accent = AppColors.teal;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Soft outer glow.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [purple.withValues(alpha: 0.32), purple.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // Slowly rotating dashed outer ring.
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = purple.withValues(alpha: 0.55);
    final outer = Rect.fromCircle(center: c, radius: r * 0.96);
    for (var k = 0; k < 28; k++) {
      final start = t * 2 * pi + k * (2 * pi / 28);
      canvas.drawArc(outer, start, 0.09, false, dash);
    }
    final counter = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.45);
    final mid = Rect.fromCircle(center: c, radius: r * 0.88);
    for (var k = 0; k < 40; k++) {
      final start = -t * 3 * pi + k * (2 * pi / 40);
      canvas.drawArc(mid, start, 0.035, false, counter);
    }

    // Inner thin ring.
    canvas.drawCircle(
      c,
      r * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = deep.withValues(alpha: 0.7),
    );

    // Radial spectrum bars (mirrored left/right so it reads as one shape).
    final levels = spectrum?.value ?? const <double>[];
    final sweep = SweepGradient(
      colors: [accent, purple, deep, purple, accent],
      transform: GradientRotation(t * 2 * pi),
    ).createShader(rect);
    final barPaint = Paint()
      ..shader = sweep
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (r * 0.032).clamp(2.0, 5.0);
    final glowPaint = Paint()
      ..shader = sweep
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (r * 0.05).clamp(3.0, 8.0)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    for (var i = 0; i < _bars; i++) {
      final mirrored = i < _bars / 2 ? i : _bars - 1 - i;
      double level;
      if (levels.isNotEmpty) {
        level =
            levels[(mirrored / (_bars / 2) * levels.length).floor().clamp(
              0,
              levels.length - 1,
            )];
      } else {
        level = 0.1 + 0.07 * sin(t * 2 * pi * 4 + i * 0.5);
      }
      final angle = i * 2 * pi / _bars - pi / 2;
      final inner = r * 0.66;
      final outerEdge = inner + r * (0.04 + level * 0.26);
      final from = c + Offset(cos(angle), sin(angle)) * inner;
      final to = c + Offset(cos(angle), sin(angle)) * outerEdge;
      canvas.drawLine(from, to, glowPaint);
      canvas.drawLine(from, to, barPaint);
    }

    // Progress ring / scanning arc.
    final ringRect = Rect.fromCircle(center: c, radius: r * 0.8);
    if (progress != null) {
      canvas.drawCircle(
        c,
        r * 0.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = Colors.white.withValues(alpha: 0.08),
      );
      canvas.drawArc(
        ringRect,
        -pi / 2,
        2 * pi * progress!.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [deep, purple, accent],
            transform: const GradientRotation(-pi / 2),
          ).createShader(ringRect),
      );
    } else if (spinning) {
      canvas.drawArc(
        ringRect,
        t * 2 * pi * 2,
        pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [purple.withValues(alpha: 0), accent],
            transform: GradientRotation(t * 2 * pi * 2),
          ).createShader(ringRect),
      );
    }

    // Dark core so the centre widget reads clearly.
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.surfaceMuted, AppColors.background],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.5)),
    );
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = purple.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.progress != progress ||
      old.spinning != spinning ||
      old.spectrum != spectrum;
}
