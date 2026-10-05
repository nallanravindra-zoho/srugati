import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton live pitch/tempo engine for Studio's instant preview: plays a
/// file through the SoLoud engine (via flutter_soloud) so pitch (semitones,
/// fractional allowed) and tempo can be changed while it plays, with no
/// re-render and no Apply step. Formant preservation is intentionally left
/// off here: it needs the server render (see Studio's Natural Voice mode).
class LivePitchService extends ChangeNotifier {
  LivePitchService._();
  static final LivePitchService instance = LivePitchService._();

  bool _engineReady = false;
  String? _loadedPath;
  AudioSource? _source;
  SoundHandle? _handle;
  // flutter_soloud doesn't export the PitchShiftSingle type from its public
  // barrel file, so this is held untyped (still type-checked at each call
  // site via the getter it came from).
  dynamic _pitchFilter;

  bool _playing = false;
  double _semitones = 0;
  double _tempo = 1.0;
  Timer? _positionTicker;
  AudioSource? _click;

  bool get playing => _playing;
  String? get loadedPath => _loadedPath;
  bool isLoaded(String path) => _loadedPath == path;
  bool get hasHandle => _handle != null;

  Duration get length => _source == null ? Duration.zero : SoLoud.instance.getLength(_source!);

  Duration get position {
    final handle = _handle;
    if (handle == null) return Duration.zero;
    try {
      return SoLoud.instance.getPosition(handle);
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<void> _ensureEngine() async {
    if (_engineReady) return;
    await SoLoud.instance.init();
    _engineReady = true;
  }

  /// Loads [path] ready for playback. Safe to call repeatedly; a no-op if
  /// already loaded.
  Future<void> load(String path) async {
    await _ensureEngine();
    if (_loadedPath == path) return;
    await stop();
    _source = await SoLoud.instance.loadFile(path);
    _loadedPath = path;
    _semitones = 0;
    _tempo = 1.0;
    notifyListeners();
  }

  void seek(Duration target) {
    final handle = _handle;
    if (handle == null) return;
    SoLoud.instance.seek(handle, target);
    notifyListeners();
  }

  /// True if the voice played to the end on its own (so the next play must
  /// start a fresh voice rather than un-pause a dead one).
  bool _voiceEnded() {
    final handle = _handle;
    if (handle == null) return false;
    try {
      return !SoLoud.instance.getIsValidVoiceHandle(handle);
    } catch (_) {
      return true;
    }
  }

  /// Call periodically while playing; flips [playing] off at end of track.
  void syncEnded() {
    if (_playing && _voiceEnded()) {
      _handle = null;
      _playing = false;
      _stopTicker();
      notifyListeners();
    }
  }

  Future<void> play({Duration from = Duration.zero}) async {
    if (_source == null) return;
    if (_handle != null && _voiceEnded()) _handle = null;

    if (_handle != null) {
      SoLoud.instance.setPause(_handle!, false);
      _playing = true;
      _startTicker();
      notifyListeners();
      return;
    }

    final handle = SoLoud.instance.play(_source!);
    final pitchFilter = _source!.filters.pitchShiftFilter;
    pitchFilter.activate();
    _handle = handle;
    _pitchFilter = pitchFilter;
    _playing = true;
    _apply();
    if (from > Duration.zero) SoLoud.instance.seek(handle, from);
    _startTicker();
    notifyListeners();
  }

  void pause() {
    final handle = _handle;
    if (handle == null) return;
    SoLoud.instance.setPause(handle, true);
    _playing = false;
    _stopTicker();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_playing && !_voiceEnded()) {
      pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    _stopTicker();
    if (_handle != null) {
      try {
        await SoLoud.instance.stop(_handle!);
      } catch (_) {}
    }
    final source = _source;
    _handle = null;
    _pitchFilter = null;
    _loadedPath = null;
    _source = null;
    _playing = false;
    if (source != null) {
      try {
        await SoLoud.instance.disposeSource(source);
      } catch (_) {}
    }
    notifyListeners();
  }

  void _startTicker() {
    _positionTicker?.cancel();
    _positionTicker = Timer.periodic(const Duration(milliseconds: 250), (_) => notifyListeners());
  }

  void _stopTicker() {
    _positionTicker?.cancel();
    _positionTicker = null;
  }

  /// Updates the live shift in (possibly fractional) semitones. Takes effect
  /// immediately if playing; otherwise remembered for the next play.
  void setSemitones(double value) {
    _semitones = value;
    _apply();
  }

  /// Updates the live tempo ratio (pitch stays independent of it).
  void setTempo(double value) {
    _tempo = value;
    _apply();
  }

  void _apply() {
    final handle = _handle;
    final pitchFilter = _pitchFilter;
    if (handle == null || pitchFilter == null) return;

    final semitoneFactor = pow(2, _semitones / 12).toDouble();
    final tempoCompensation = 1.0 / _tempo;

    SoLoud.instance.setRelativePlaySpeed(handle, _tempo);
    pitchFilter.shift(soundHandle: handle).value = semitoneFactor * tempoCompensation;
  }

  /// One metronome-style click (used for the count-in), through the same
  /// audio engine so it never fights with the player for the output device.
  Future<void> playClick({bool accent = false}) async {
    await _ensureEngine();
    _click ??= await SoLoud.instance.loadFile(await _clickFile());
    SoLoud.instance.play(_click!, volume: accent ? 1.0 : 0.7);
  }

  Future<String> _clickFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/srugati_click.wav');
    if (await file.exists()) return file.path;

    const rate = 44100;
    final samples = (rate * 0.045).round();
    final data = ByteData(44 + samples * 2);
    void text(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    data.setUint32(4, 36 + samples * 2, Endian.little);
    text(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, samples * 2, Endian.little);
    for (var i = 0; i < samples; i++) {
      final envelope = exp(-i / (rate * 0.008));
      final value = sin(2 * pi * 1400 * i / rate) * envelope * 0.9;
      data.setInt16(44 + i * 2, (value * 32767).round(), Endian.little);
    }
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }
}
