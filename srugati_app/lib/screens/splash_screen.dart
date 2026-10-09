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
  static const _waveDuration = Duration(milliseconds: 950);
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

  /// Grid wave: the Studio assembles itself from square tiles that pop up in a
  /// diagonal wave over the splash (the tiles are a clip on the Studio page).
  void _goToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: _waveDuration,
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, animation, __, child) => AnimatedBuilder(
          animation: animation,
          // Same widget type before and after, so the Studio keeps its state;
          // once the wave is done the clip is switched off.
          builder: (_, c) => ClipPath(
            clipper: _GridWaveClipper(animation),
            clipBehavior: animation.isCompleted ? Clip.none : Clip.antiAlias,
            child: c,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_checkVideoFinished);
    _controller.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _notes,
        builder: (context, _) {
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
                        fade: 1,
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
                      child: ColorFiltered(
                        colorFilter: _themeTint(
                          AppColors.background,
                          AppColors.purple,
                        ),
                        child: VideoPlayer(_controller),
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

/// The splash video is a grey brightness map (black background, logo at 85%
/// grey). This maps black to the app's background and 85% grey to the logo
/// colour, so the video recolours with the active theme and its background is
/// always exactly the app's background. Brighter-than-logo pixels (flame core,
/// sparkles) go a little lighter than the logo colour.
ColorFilter _themeTint(Color bg, Color fg) {
  const gain = 0.85 * 255;
  double k(double f, double b) => (f - b) * 255 / gain;
  final r = bg.r * 255, g = bg.g * 255, b = bg.b * 255;
  return ColorFilter.matrix(<double>[
    k(fg.r, bg.r), 0, 0, 0, r, //
    k(fg.g, bg.g), 0, 0, 0, g,
    k(fg.b, bg.b), 0, 0, 0, b,
    0, 0, 0, 1, 0,
  ]);
}

double _smooth(double t, double a, double b) {
  final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// The Studio revealed as a grid of square tiles that grow from their centres,
/// starting top-left and sweeping diagonally to the bottom-right.
class _GridWaveClipper extends CustomClipper<Path> {
  final Animation<double> t;

  _GridWaveClipper(this.t) : super(reclip: t);

  static const _cols = 6;

  @override
  Path getClip(Size size) {
    final tile = size.width / _cols;
    final rows = (size.height / tile).ceil();
    final path = Path();
    for (var i = 0; i < _cols; i++) {
      for (var j = 0; j < rows; j++) {
        final delay = (i + j) / (_cols + rows) * 0.5;
        final s = _smooth(t.value, 0.05 + delay, 0.45 + delay);
        if (s <= 0) continue;
        final w = math.min(tile, size.width - i * tile);
        final h = math.min(tile, size.height - j * tile);
        final overlap = s >= 1 ? 1.0 : 0.0; // no hairline seams once grown
        path.addRect(
          Rect.fromCenter(
            center: Offset(i * tile + w / 2, j * tile + h / 2),
            width: w * s + overlap,
            height: h * s + overlap,
          ),
        );
      }
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _GridWaveClipper old) => true;
}

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
