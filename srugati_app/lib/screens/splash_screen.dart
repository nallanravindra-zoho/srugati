import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late VideoPlayerController _controller;
  static const _zoomDuration = Duration(milliseconds: 700);
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: _zoomDuration,
  );
  // Slow clock for the drifting music symbols that fill the whole screen.
  late final AnimationController _notes = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();
  bool _transitionStarted = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset('assets/srugati1.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
        _controller.addListener(_checkVideoFinished);
      });
  }

  void _checkVideoFinished() {
    final v = _controller.value;
    if (v.isInitialized && v.position >= v.duration && !_transitionStarted) {
      _transitionStarted = true;
      _goToHome();
    }
  }

  /// Zoom through: the logo grows toward the viewer and fades while the
  /// Studio eases in from slightly smaller. Both run on the same 0.7 s clock.
  void _goToHome() {
    _zoom.forward();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: _zoomDuration,
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, animation, __, child) {
          final e = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.1, 0.9, curve: Curves.easeInOut),
          );
          return FadeTransition(
            opacity: e,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(e),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_checkVideoFinished);
    _controller.dispose();
    _zoom.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([_zoom, _notes]),
        builder: (context, _) {
          final p = _zoom.value;
          final gone = 1 - _smooth(p, 0.1, 0.6); // logo fades as it grows
          final grow = _lerp(1, 2.4, _smooth(p, 0.1, 0.9));
          if (!_controller.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return LayoutBuilder(
            builder: (context, c) {
              final aspect = _controller.value.aspectRatio;
              final vw = math.min(c.maxWidth, c.maxHeight * aspect);
              final vh = vw / aspect;
              final videoRect = Rect.fromLTWH(
                (c.maxWidth - vw) / 2,
                (c.maxHeight - vh) / 2,
                vw,
                vh,
              );
              return Stack(
                children: [
                  // Music symbols across the whole screen, including the
                  // bands above and below the 9:16 video.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _NotesPainter(
                        t: _notes.value,
                        color: AppColors.purple,
                        fade: gone,
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: videoRect,
                    // Fade the video's top and bottom edges into the
                    // symbols so there is no visible seam where it ends.
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (b) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.1, 0.9, 1.0],
                      ).createShader(b),
                      child: Opacity(
                        opacity: gone,
                        child: Transform.scale(
                          scale: grow,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

double _smooth(double t, double a, double b) {
  final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Drifting music notes (vector-drawn, so no font support is needed) spread
/// over the whole screen, faint and slowly twinkling, in the app's violet.
class _NotesPainter extends CustomPainter {
  final double t; // 0..1, loops every 40 s
  final Color color;
  final double fade;

  _NotesPainter({required this.t, required this.color, required this.fade});

  static final _items = () {
    final r = math.Random(11);
    return List.generate(
      36,
      (i) => (
        x: (i % 6 + 0.15 + r.nextDouble() * 0.7) / 6,
        y: r.nextDouble(),
        size: 14 + r.nextDouble() * 26,
        kind: r.nextInt(4),
        tilt: (r.nextDouble() - 0.5) * 0.7,
        loops: 1 + r.nextInt(2),
        phase: r.nextDouble() * 6.28,
        alpha: 0.10 + r.nextDouble() * 0.16,
      ),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0) return;
    for (final n in _items) {
      final margin = n.size * 4;
      final y =
          ((n.y - t * n.loops) % 1.0 + 1.0) % 1.0 * (size.height + 2 * margin) -
          margin;
      final a =
          n.alpha * (0.65 + 0.35 * math.sin(t * 6.28 * 8 + n.phase)) * fade;
      _note(canvas, Offset(n.x * size.width, y), n.size, n.kind, n.tilt, a);
    }
  }

  void _note(
    Canvas canvas,
    Offset at,
    double u,
    int kind,
    double tilt,
    double a,
  ) {
    final fill = Paint()..color = color.withValues(alpha: a);
    final stroke = Paint()
      ..color = color.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.14
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(tilt);

    void head(double x, {bool open = false}) {
      canvas.save();
      canvas.translate(x, 0);
      canvas.rotate(-0.35);
      final r = Rect.fromCenter(
        center: Offset.zero,
        width: u * 0.62,
        height: u * 0.44,
      );
      if (open) {
        canvas.drawOval(r, stroke);
      } else {
        canvas.drawOval(r, fill);
      }
      canvas.restore();
    }

    void stem(double x, double top) {
      canvas.drawLine(
        Offset(x + u * 0.28, -u * 0.04),
        Offset(x + u * 0.28, top),
        stroke,
      );
    }

    switch (kind) {
      case 0: // quarter note
        head(0);
        stem(0, -u * 1.5);
      case 1: // eighth note with a flag
        head(0);
        stem(0, -u * 1.5);
        final f = Path()
          ..moveTo(u * 0.28, -u * 1.5)
          ..quadraticBezierTo(u * 0.85, -u * 1.2, u * 0.62, -u * 0.62);
        canvas.drawPath(f, stroke);
      case 2: // two beamed eighths
        head(0);
        head(u * 0.95);
        stem(0, -u * 1.45);
        stem(u * 0.95, -u * 1.45);
        canvas.drawLine(
          Offset(u * 0.28, -u * 1.45),
          Offset(u * 1.23, -u * 1.45),
          stroke..strokeWidth = u * 0.22,
        );
      default: // half note (open head)
        head(0, open: true);
        stem(0, -u * 1.5);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NotesPainter old) =>
      old.t != t || old.fade != fade;
}
