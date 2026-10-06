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
  static const _morphDuration = Duration(milliseconds: 1100);
  late VideoPlayerController _controller;
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: _morphDuration,
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

  /// Pitch dial: the logo shrinks away and a note dial turns from A to B (a
  /// two-semitone shift), then settles into the Studio's upload badge while
  /// the Studio fades in. Both run on the same 1.1 s clock.
  void _goToHome() {
    _morph.forward();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: _morphDuration,
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.6, 0.92, curve: Curves.easeInOut),
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
    _morph.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final morph = _morph;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([morph, _notes]),
        builder: (context, _) {
          final p = morph.value;
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
                        fade: 1 - _smooth(p, 0.3, 0.9),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: videoRect,
                    // Fade the video's top and bottom edges into the symbols
                    // so there is no visible seam where it ends.
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
                        opacity: 1 - _smooth(p, 0, 0.2),
                        child: Transform.scale(
                          scale: _lerp(1, 0.8, _smooth(p, 0, 0.2)),
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  ),
                  if (p > 0)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PitchDialPainter(
                          p: p,
                          video: videoRect,
                          main: AppColors.purple,
                          disc: AppColors.surface,
                          muted: AppColors.textSecondary,
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

const _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];

/// A ring of the twelve note names that turns from A to B (+2 semitones),
/// then shrinks into the Studio's round upload badge as it fades out.
class _PitchDialPainter extends CustomPainter {
  final double p;
  final Rect video;
  final Color main;
  final Color disc;
  final Color muted;

  _PitchDialPainter({
    required this.p,
    required this.video,
    required this.main,
    required this.disc,
    required this.muted,
  });

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
    FontWeight weight,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final appear = _smooth(p, 0.05, 0.25);
    final move = _smooth(p, 0.68, 0.95);
    final fade = 1 - _smooth(p, 0.9, 1.0);
    final alpha = appear * fade;
    if (alpha <= 0) return;

    final turn = _smooth(p, 0.25, 0.62) * 2; // semitones turned: A -> B
    final start = Offset(
      video.center.dx,
      video.top + video.height * 0.502, // the logo's centre
    );
    final end = Offset(size.width / 2, size.height * 0.182); // upload badge
    final c = Offset.lerp(start, end, move)!;
    final big = size.width * 0.33;
    final small = size.width * 0.075;
    final r = _lerp(big, small, move) * appear;

    canvas.drawCircle(
      c,
      r + (move < 0.5 ? 12 : 4) * size.height / 600,
      Paint()..color = disc.withValues(alpha: alpha),
    );
    if (r < big * 0.45) return; // too small for note names

    for (var i = 0; i < 12; i++) {
      final a = (i - 9 - turn) * math.pi / 6 - math.pi / 2;
      final pos = c + Offset(math.cos(a), math.sin(a)) * (r * 0.82);
      final top = (i - 9 - turn).abs() < 0.5;
      _text(
        canvas,
        _noteNames[i],
        pos,
        (top ? 16 : 11) * size.height / 600,
        (top ? main : muted).withValues(alpha: alpha),
        top ? FontWeight.w600 : FontWeight.w400,
      );
    }
    _text(
      canvas,
      turn > 1.5 ? 'A \u2192 B' : 'A',
      c,
      19 * size.height / 600,
      Colors.white.withValues(alpha: alpha),
      FontWeight.w600,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchDialPainter old) =>
      old.p != p || old.video != video;
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
