import 'package:flutter/material.dart';
import '../services/song_store.dart';
import '../theme/app_theme.dart';

/// Interactive waveform: tap or drag to seek, shows the playhead, the A–B
/// loop region and named markers. With [editableLoop] the A/B handles can be
/// dragged to reshape the loop.
class WaveformView extends StatefulWidget {
  final List<double> peaks;
  final double durationSec;
  final ValueNotifier<double> positionSec;
  final double? loopA;
  final double? loopB;
  final List<SongMarker> markers;
  final ValueChanged<double>? onSeek;
  final bool editableLoop;
  final void Function(double a, double b)? onLoopChanged;
  final double height;

  const WaveformView({
    super.key,
    required this.peaks,
    required this.durationSec,
    required this.positionSec,
    this.loopA,
    this.loopB,
    this.markers = const [],
    this.onSeek,
    this.editableLoop = false,
    this.onLoopChanged,
    this.height = 84,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  static const _handleGrab = 30.0;
  int _dragging = 0; // 0 none, 1 = A, 2 = B, 3 = seek

  double _toSeconds(double dx, double width) =>
      (dx / width).clamp(0.0, 1.0) * widget.durationSec;

  void _dragStart(double dx, double width) {
    final a = widget.loopA, b = widget.loopB;
    if (widget.editableLoop && a != null && b != null && widget.durationSec > 0) {
      final ax = a / widget.durationSec * width;
      final bx = b / widget.durationSec * width;
      final da = (dx - ax).abs(), db = (dx - bx).abs();
      if (da <= _handleGrab && da <= db) {
        _dragging = 1;
        return;
      }
      if (db <= _handleGrab) {
        _dragging = 2;
        return;
      }
    }
    _dragging = 3;
    widget.onSeek?.call(_toSeconds(dx, width));
  }

  void _dragUpdate(double dx, double width) {
    final seconds = _toSeconds(dx, width);
    final a = widget.loopA, b = widget.loopB;
    if (_dragging == 1 && a != null && b != null) {
      widget.onLoopChanged?.call(seconds.clamp(0, b - 0.5).toDouble(), b);
    } else if (_dragging == 2 && a != null && b != null) {
      widget.onLoopChanged?.call(a, seconds.clamp(a + 0.5, widget.durationSec).toDouble());
    } else if (_dragging == 3) {
      widget.onSeek?.call(seconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            _dragStart(d.localPosition.dx, width);
            _dragging = 0;
          },
          onHorizontalDragStart: (d) => _dragStart(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => _dragUpdate(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _dragging = 0,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                peaks: widget.peaks,
                durationSec: widget.durationSec,
                position: widget.positionSec,
                loopA: widget.loopA,
                loopB: widget.loopB,
                markers: widget.markers,
                editable: widget.editableLoop,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final double durationSec;
  final ValueNotifier<double> position;
  final double? loopA;
  final double? loopB;
  final List<SongMarker> markers;
  final bool editable;

  _WaveformPainter({
    required this.peaks,
    required this.durationSec,
    required this.position,
    required this.loopA,
    required this.loopB,
    required this.markers,
    required this.editable,
  }) : super(repaint: position);

  double _x(double seconds, double width) =>
      durationSec <= 0 ? 0 : (seconds / durationSec).clamp(0.0, 1.0) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final playheadX = _x(position.value, size.width);

    if (loopA != null && loopB != null) {
      final region = Rect.fromLTRB(_x(loopA!, size.width), 0, _x(loopB!, size.width), size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(region, const Radius.circular(8)),
        Paint()..color = AppColors.purple.withValues(alpha: 0.18),
      );
    }

    final count = peaks.length;
    if (count > 0) {
      final slot = size.width / count;
      final bar = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (slot * 0.55).clamp(1.5, 4.0);
      for (var i = 0; i < count; i++) {
        final x = (i + 0.5) * slot;
        final h = (peaks[i] * size.height * 0.46).clamp(1.5, size.height / 2);
        final inLoop = loopA != null && loopB != null && x >= _x(loopA!, size.width) && x <= _x(loopB!, size.width);
        bar.color = x <= playheadX
            ? AppColors.purple
            : (inLoop ? AppColors.purple.withValues(alpha: 0.7) : AppColors.purpleDeep.withValues(alpha: 0.55));
        canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), bar);
      }
    }

    for (final m in markers) {
      final x = _x(m.seconds, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = AppColors.teal.withValues(alpha: 0.8)
          ..strokeWidth = 1.2,
      );
      canvas.drawCircle(Offset(x, 4), 3.5, Paint()..color = AppColors.teal);
    }

    if (loopA != null && loopB != null) {
      for (final entry in {'A': loopA!, 'B': loopB!}.entries) {
        final x = _x(entry.value, size.width);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = AppColors.purple
            ..strokeWidth = 2,
        );
        if (editable) {
          canvas.drawCircle(Offset(x, size.height - 6), 9, Paint()..color = AppColors.purple);
          final tp = TextPainter(
            text: TextSpan(
              text: entry.key,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x - tp.width / 2, size.height - 6 - tp.height / 2));
        }
      }
    }

    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(playheadX, 0), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.peaks != peaks ||
      old.durationSec != durationSec ||
      old.loopA != loopA ||
      old.loopB != loopB ||
      old.markers != markers ||
      old.editable != editable;
}
