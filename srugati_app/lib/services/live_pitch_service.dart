import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Singleton live pitch/tempo engine for Studio's instant preview: plays a
/// file through the SoLoud engine (via flutter_soloud) so pitch (semitones)
/// and tempo can be changed while it plays, with no re-render and no Apply
/// step — matching how Uptempo previews changes. Formant preservation is
/// intentionally left off: on full-mix karaoke tracks it introduces the
/// doubled-voice artifact seen in the real-time POC, and the user doesn't
/// need it for their use case (karaoke backing tracks, not solo vocals).
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

  bool get playing => _playing;
  String? get loadedPath => _loadedPath;
  bool isLoaded(String path) => _loadedPath == path;
  bool get hasHandle => _handle != null;

  Duration get length => _source == null ? Duration.zero : SoLoud.instance.getLength(_source!);
  Duration get position => _handle == null ? Duration.zero : SoLoud.instance.getPosition(_handle!);

  void seek(Duration position) {
    final handle = _handle;
    if (handle == null) return;
    SoLoud.instance.seek(handle, position);
    notifyListeners();
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

  Future<void> togglePlay() async {
    if (_source == null) return;
    if (_handle != null) {
      SoLoud.instance.pauseSwitch(_handle!);
      _playing = !_playing;
      _playing ? _startTicker() : _stopTicker();
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
    _startTicker();
    notifyListeners();
  }

  Future<void> stop() async {
    _stopTicker();
    if (_handle != null) {
      await SoLoud.instance.stop(_handle!);
    }
    _handle = null;
    _pitchFilter = null;
    _loadedPath = null;
    _source = null;
    _playing = false;
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

  /// Updates the live semitone shift. Takes effect immediately if playing;
  /// otherwise just remembered for the next play.
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
}
