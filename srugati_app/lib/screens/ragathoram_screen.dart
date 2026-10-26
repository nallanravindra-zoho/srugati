import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../services/live_pitch_service.dart';
import '../services/stem_player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/help_note.dart';
import '../widgets/theme_picker_sheet.dart';
import 'home_shell.dart';

const _swaras = ['S', 'R', 'G', 'M', 'P', 'D', 'N', 'Ś'];

/// One colour per swara, spread around the colour wheel so each note is easy to
/// tell apart, then softened a little towards the current theme.
Color _swaraColor(int i) {
  final base = HSLColor.fromAHSL(1, (i * 45.0 + 8) % 360, 0.82, 0.62).toColor();
  return Color.lerp(base, AppColors.purple, 0.12)!;
}

/// A parsed pattern: each row is a list of swara indexes 0..7 (7 is the high Sa).
List<List<int>> parsePattern(String text) {
  final rows = <List<int>>[];
  for (final line in text.split('\n')) {
    final notes = <int>[];
    final runes = line.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final ch = String.fromCharCode(runes[i]);
      final up = ch.toUpperCase();
      if (up == 'Ś' || up == 'Ṡ') {
        notes.add(7);
        continue;
      }
      final idx = 'SRGMPDN'.indexOf(up);
      if (idx < 0) continue;
      // S followed by an apostrophe means the high Sa (S').
      if (idx == 0 && i + 1 < runes.length) {
        final next = String.fromCharCode(runes[i + 1]);
        if (next == "'" || next == '’' || next == 'ʼ') {
          notes.add(7);
          i++;
          continue;
        }
      }
      notes.add(idx);
    }
    if (notes.isNotEmpty) rows.add(notes);
  }
  return rows;
}

String _pyramid() {
  const up = [0, 1, 2, 3, 4, 5, 6, 7];
  final out = <String>[];
  for (var n = 0; n < up.length; n++) {
    final row = [...up.take(n + 1), ...up.take(n).toList().reversed];
    out.add(row.map((i) => _swaras[i]).join(' '));
  }
  return out.join('\n');
}

const _presets = <String, String>{
  'Pyramid': '', // filled from _pyramid()
  'Sarali': 'S R G M P D N Ś\nŚ N D P M G R S',
  'Janta': 'S S R R G G M M P P D D N N Ś Ś\nŚ Ś N N D D P P M M G G R R S S',
  'Alankaram': 'S R G R S R G M G R\nG M P M G M P D P M\nP D N D P D N Ś N D',
};

class RagaThoramScreen extends StatefulWidget {
  const RagaThoramScreen({super.key});

  @override
  State<RagaThoramScreen> createState() => _RagaThoramScreenState();
}

class _RagaThoramScreenState extends State<RagaThoramScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);

  String? _songPath;
  String _songName = '';
  Duration _duration = Duration.zero;
  bool _playing = false;

  // Song position, interpolated between the player's coarse updates.
  double _lastPos = 0;
  int _lastPosAt = 0;

  String _presetName = 'Pyramid';
  late final TextEditingController _pattern = TextEditingController(
    text: _pyramid(),
  );
  List<List<int>> _rows = [];
  double _rate = 3; // notes per second
  double _offset = 0; // song second at which the pattern starts

  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void initState() {
    super.initState();
    _rows = parsePattern(_pattern.text);
    _ticker = createTicker((_) => _frame.value++)..start();
    _subs = [
      _player.positionStream.listen((d) {
        _lastPos = d.inMilliseconds / 1000;
        _lastPosAt = DateTime.now().millisecondsSinceEpoch;
      }),
      _player.playerStateStream.listen((s) {
        final done = s.processingState == ProcessingState.completed;
        if (done) {
          _player.pause();
          _player.seek(Duration.zero);
        }
        if (mounted) setState(() => _playing = s.playing && !done);
      }),
      _player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _duration = d);
      }),
    ];
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _frame.dispose();
    _pattern.dispose();
    super.dispose();
  }

  double get _songPos {
    if (!_playing) return _lastPos;
    final dt = (DateTime.now().millisecondsSinceEpoch - _lastPosAt) / 1000;
    return _lastPos + math.min(dt, 0.5);
  }

  Future<void> _pickSong() async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked == null || picked.path == null) return;
    await _player.stop();
    try {
      await _player.setFilePath(picked.path!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't open that file. Try another song."),
          ),
        );
      }
      return;
    }
    setState(() {
      _songPath = picked.path;
      _songName = p.basenameWithoutExtension(picked.name);
      _offset = 0;
      _lastPos = 0;
    });
  }

  Future<void> _togglePlay() async {
    if (_songPath == null) {
      await _pickSong();
      return;
    }
    if (_playing) {
      await _player.pause();
      return;
    }
    // Only one thing plays at a time in the app.
    StemPlayerService.instance.pause();
    LivePitchService.instance.pause();
    await _player.play();
  }

  void _setPreset(String name) {
    setState(() {
      _presetName = name;
      _pattern.text = name == 'Pyramid' ? _pyramid() : _presets[name]!;
      _rows = parsePattern(_pattern.text);
    });
  }

  String _fmt(double s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => homeTab.value = 0,
        ),
        title: const Text('RagaThoram'),
        actions: [
          IconButton(
            tooltip: 'Theme',
            onPressed: () => ThemePickerSheet.show(context),
            icon: Icon(Icons.palette_outlined, color: AppColors.purple),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _songCard(),
          const SizedBox(height: 12),
          _stage(),
          const SizedBox(height: 12),
          _controls(),
          const SizedBox(height: 12),
          _patternCard(),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );

  Widget _songCard() {
    return _card(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.music_note_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _songPath == null ? 'No song yet' : _songName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _songPath == null
                      ? 'Choose a song to practise along with'
                      : _fmt(_duration.inMilliseconds / 1000),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _pickSong,
            child: Text(_songPath == null ? 'Choose song' : 'Change'),
          ),
        ],
      ),
    );
  }

  Widget _stage() {
    return _card(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: ValueListenableBuilder<int>(
        valueListenable: _frame,
        builder: (context, _, __) {
          // Nothing is highlighted until the song has been started.
          final started = _playing || _songPos > 0.05;
          final cur = started
              ? _Cursor.at(_rows, _songPos - _offset, 1 / _rate)
              : const _Cursor(-1, -1, 0, false);
          return Column(
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: CustomPaint(
                  painter: _LanePainter(cur, _rows, AppColors.background),
                ),
              ),
              const SizedBox(height: 10),
              _pyramidText(cur),
            ],
          );
        },
      ),
    );
  }

  Widget _pyramidText(_Cursor cur) {
    if (_rows.isEmpty) {
      return Text(
        'Type a pattern below, like S R G M G R S',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return Column(
      children: [
        for (var r = 0; r < _rows.length; r++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(
              textAlign: TextAlign.center,
              TextSpan(
                children: [
                  if (r == cur.row)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: AppColors.purple,
                        ),
                      ),
                    ),
                  for (var n = 0; n < _rows[r].length; n++)
                    TextSpan(
                      text:
                          '${_swaras[_rows[r][n]]}${n == _rows[r].length - 1 ? '' : ' '}',
                      style: TextStyle(
                        fontWeight: r == cur.row && n == cur.note
                            ? FontWeight.w900
                            : FontWeight.w600,
                        fontSize: r == cur.row && n == cur.note ? 22 : 16,
                        letterSpacing: 2,
                        color: r == cur.row
                            ? (n == cur.note
                                  ? _swaraColor(_rows[r][n])
                                  : (cur.active && n < cur.note
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary))
                            : AppColors.textSecondary.withValues(alpha: 0.55),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _controls() {
    final dur = math.max(_duration.inMilliseconds / 1000, 1.0);
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filled(
                iconSize: 32,
                onPressed: _togglePlay,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _frame,
                  builder: (context, _, __) => Slider(
                    value: _songPath == null
                        ? 0
                        : _songPos.clamp(0, dur).toDouble(),
                    max: dur,
                    onChanged: _songPath == null
                        ? null
                        : (v) {
                            _lastPos = v;
                            _lastPosAt = DateTime.now().millisecondsSinceEpoch;
                            _player.seek(
                              Duration(milliseconds: (v * 1000).round()),
                            );
                          },
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, __) => Text(
                  _fmt(_songPos),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pattern starts at',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _fmt(_offset),
                style: TextStyle(
                  color: AppColors.purple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _songPath == null
                    ? null
                    : () => setState(() => _offset = _songPos),
                child: const Text('Start here'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Speed',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: Slider(
                  value: _rate,
                  min: 1,
                  max: 6,
                  divisions: 20,
                  label: '${_rate.toStringAsFixed(1)} notes/sec',
                  onChanged: (v) => setState(() => _rate = v),
                ),
              ),
              Text(
                '${_rate.toStringAsFixed(1)}/s',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const HelpNote(
            'Play your song and press "Start here" at the moment the singing of the pattern begins. '
            'The pattern then plays along with the song at the speed you set. Move the slider or '
            'seek the song and the animation follows the song position, so it always stays in step.',
            title: 'How it works',
          ),
        ],
      ),
    );
  }

  Widget _patternCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pattern',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _presets.keys)
                ChoiceChip(
                  label: Text(name),
                  selected: _presetName == name,
                  onSelected: (_) => _setPreset(name),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pattern,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(fontSize: 16, letterSpacing: 2),
            decoration: const InputDecoration(
              labelText: 'One line per row. Use S R G M P D N Ś',
              alignLabelWithHint: true,
            ),
            onChanged: (t) => setState(() {
              _presetName = '';
              _rows = parsePattern(t);
            }),
          ),
          const HelpNote(
            'Write each row on its own line. The notes are S R G M P D N, and Ś (or S\') for the high Sa. '
            'Spaces and other characters are ignored.',
            title: 'Writing a pattern',
          ),
        ],
      ),
    );
  }
}

/// Where the pattern is at a given time: which row and note, and how far
/// through that note (0..1).
class _Cursor {
  final int row;
  final int note;
  final double t;
  final bool active;
  const _Cursor(this.row, this.note, this.t, this.active);

  /// Rows play one after another, with a short rest of 1.5 notes between them.
  factory _Cursor.at(List<List<int>> rows, double time, double noteSec) {
    if (rows.isEmpty || time < 0) return const _Cursor(-1, -1, 0, false);
    var start = 0.0;
    for (var r = 0; r < rows.length; r++) {
      final len = rows[r].length * noteSec;
      if (time < start + len) {
        final into = (time - start) / noteSec;
        final n = into.floor().clamp(0, rows[r].length - 1);
        return _Cursor(r, n, into - n, true);
      }
      start += len;
      final rest = noteSec * 1.5;
      if (time < start + rest) return _Cursor(r, rows[r].length - 1, 1, false);
      start += rest;
    }
    return _Cursor(rows.length - 1, rows.last.length - 1, 1, false);
  }
}

/// Eight lanes, one per swara. The active note lights its lane and launches a
/// glowing orb that rises to that swara's height, with rings and a trail of the
/// notes just played, so the row draws a shape as it goes up and back down.
class _LanePainter extends CustomPainter {
  final _Cursor cur;
  final List<List<int>> rows;
  final Color bg;
  _LanePainter(this.cur, this.rows, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final laneW = size.width / 8;
    final top = 14.0, bottom = size.height - 26;
    double yFor(int i) => bottom - (bottom - top) * (i / 7);

    // lanes
    for (var i = 0; i < 8; i++) {
      final cx = laneW * i + laneW / 2;
      final on = cur.active && cur.row >= 0 && rows[cur.row][cur.note] == i;
      final c = _swaraColor(i);
      canvas.drawLine(
        Offset(cx, top),
        Offset(cx, bottom),
        Paint()
          ..color = c.withValues(alpha: on ? 0.55 : 0.14)
          ..strokeWidth = on ? 3 : 1.5
          ..strokeCap = StrokeCap.round,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: _swaras[i],
          style: TextStyle(
            color: c.withValues(alpha: on ? 1 : 0.6),
            fontWeight: FontWeight.w800,
            fontSize: on ? 17 : 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - 22));
    }
    if (cur.row < 0) return;

    final row = rows[cur.row];
    // trail: the last few notes of this row
    final path = <Offset>[];
    final from = math.max(0, cur.note - 5);
    for (var n = from; n <= cur.note; n++) {
      path.add(Offset(laneW * row[n] + laneW / 2, yFor(row[n])));
    }
    if (path.length > 1) {
      final line = Path()..moveTo(path.first.dx, path.first.dy);
      for (final pt in path.skip(1)) {
        line.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [
              _swaraColor(row[from]).withValues(alpha: 0.05),
              _swaraColor(row[cur.note]).withValues(alpha: 0.9),
            ],
          ).createShader(Rect.fromPoints(path.first, path.last).inflate(2)),
      );
    }
    // earlier notes as fading dots
    for (var n = from; n < cur.note; n++) {
      final age = (cur.note - n) / 6;
      canvas.drawCircle(
        path[n - from],
        5 * (1 - age * 0.5),
        Paint()..color = _swaraColor(row[n]).withValues(alpha: 0.7 * (1 - age)),
      );
    }

    // the active note: orb glides to its lane, rings expand
    final i = row[cur.note];
    final prev = cur.note > 0 ? row[cur.note - 1] : i;
    final glide = Curves.easeOutCubic.transform(math.min(cur.t * 2.2, 1.0));
    final cx = lerpDouble(
      laneW * prev + laneW / 2,
      laneW * i + laneW / 2,
      glide,
    );
    final cy = lerpDouble(yFor(prev), yFor(i), glide);
    final col = _swaraColor(i);
    final fade = cur.active ? 1.0 : 0.0;
    final pulse = math.sin(cur.t * math.pi);
    for (var k = 0; k < 3; k++) {
      final q = (cur.t + k / 3) % 1.0;
      canvas.drawCircle(
        Offset(cx, cy),
        10 + q * 34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = col.withValues(alpha: (1 - q) * 0.5 * fade),
      );
    }
    canvas.drawCircle(
      Offset(cx, cy),
      16 + 5 * pulse,
      Paint()
        ..color = col.withValues(alpha: 0.35 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      9 + 2 * pulse,
      Paint()..color = col.withValues(alpha: fade),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      3.5,
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
  }

  double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(covariant _LanePainter old) => true;
}
