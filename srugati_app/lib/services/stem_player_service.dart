import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_engine.dart';
import 'live_pitch_service.dart';
import 'player_service.dart';
import 'stem_store.dart';

/// Plays a separation's vocal and instrumental stems together, sample-synced
/// (they live in one SoLoud voice group), with an independent level per stem.
class StemPlayerService extends ChangeNotifier {
  StemPlayerService._();
  static final StemPlayerService instance = StemPlayerService._();

  StemResult? _result;
  AudioSource? _vocalsSource;
  AudioSource? _instrumentalSource;
  SoundHandle? _vocalsHandle;
  SoundHandle? _instrumentalHandle;
  SoundHandle? _group;
  Timer? _ticker;
  bool _playing = false;
  bool _listening = false;

  double vocalsLevel = 1.0;
  double instrumentalLevel = 1.0;
  bool vocalsMuted = false;
  bool instrumentalMuted = false;
  bool soloVocals = false;
  bool soloInstrumental = false;

  /// Live frequency-band levels (0..1) while playing; empty otherwise.
  final ValueNotifier<List<double>> spectrum = ValueNotifier<List<double>>(
    const [],
  );

  StemResult? get result => _result;
  bool get playing => _playing;
  bool isLoaded(StemResult r) => _result?.id == r.id;
  Duration get duration =>
      Duration(milliseconds: ((_result?.durationSec ?? 0) * 1000).round());

  Duration get position {
    final handle = _vocalsHandle;
    if (handle == null) return Duration.zero;
    try {
      return SoLoud.instance.getPosition(handle);
    } catch (_) {
      return Duration.zero;
    }
  }

  double get _vocalsEffective {
    if (soloInstrumental && !soloVocals) return 0;
    if (soloVocals || !vocalsMuted) return vocalsLevel;
    return 0;
  }

  double get _instrumentalEffective {
    if (soloVocals && !soloInstrumental) return 0;
    if (soloInstrumental || !instrumentalMuted) return instrumentalLevel;
    return 0;
  }

  Future<void> load(StemResult result) async {
    if (isLoaded(result) && _vocalsSource != null) return;
    await AudioEngine.ensure();
    if (!_listening) {
      _listening = true;
      SoLoud.instance.audioVisualizationEvents.listen(_onVisualization);
    }
    await stop();
    _vocalsSource = await SoLoud.instance.loadFile(result.vocalsPath);
    _instrumentalSource = await SoLoud.instance.loadFile(
      result.instrumentalPath,
    );
    _result = result;
    notifyListeners();
  }

  bool _voiceEnded() {
    final handle = _vocalsHandle;
    if (handle == null) return false;
    try {
      return !SoLoud.instance.getIsValidVoiceHandle(handle);
    } catch (_) {
      return true;
    }
  }

  /// Call while playing; flips [playing] off when the stems reach the end.
  void syncEnded() {
    if (_playing && _voiceEnded()) {
      _vocalsHandle = _instrumentalHandle = _group = null;
      _playing = false;
      spectrum.value = const [];
      _ticker?.cancel();
      notifyListeners();
    }
  }

  void _applyLevels() {
    final v = _vocalsHandle, i = _instrumentalHandle;
    if (v == null || i == null) return;
    SoLoud.instance.setVolume(v, _vocalsEffective);
    SoLoud.instance.setVolume(i, _instrumentalEffective);
  }

  /// Changes a level and applies it immediately if playing.
  void updateMix({
    double? vocals,
    double? instrumental,
    bool? muteVocals,
    bool? muteInstrumental,
    bool? vocalsSolo,
    bool? instrumentalSolo,
  }) {
    vocalsLevel = vocals ?? vocalsLevel;
    instrumentalLevel = instrumental ?? instrumentalLevel;
    vocalsMuted = muteVocals ?? vocalsMuted;
    instrumentalMuted = muteInstrumental ?? instrumentalMuted;
    soloVocals = vocalsSolo ?? soloVocals;
    soloInstrumental = instrumentalSolo ?? soloInstrumental;
    _applyLevels();
    notifyListeners();
  }

  Future<void> play({Duration from = Duration.zero}) async {
    if (_vocalsSource == null || _instrumentalSource == null) return;
    // Only one thing plays at a time across the app.
    LivePitchService.instance.pause();
    await PlayerService.instance.pause();

    if (_vocalsHandle != null && _voiceEnded()) {
      _vocalsHandle = _instrumentalHandle = _group = null;
    }
    if (_group != null) {
      SoLoud.instance.setPause(_group!, false);
    } else {
      final v = SoLoud.instance.play(
        _vocalsSource!,
        volume: _vocalsEffective,
        paused: true,
      );
      final i = SoLoud.instance.play(
        _instrumentalSource!,
        volume: _instrumentalEffective,
        paused: true,
      );
      final group = SoLoud.instance.createVoiceGroup();
      SoLoud.instance.addVoicesToGroup(group, [v, i]);
      if (from > Duration.zero) SoLoud.instance.seek(group, from);
      _vocalsHandle = v;
      _instrumentalHandle = i;
      _group = group;
      SoLoud.instance.setPause(group, false);
    }
    _playing = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => notifyListeners(),
    );
    notifyListeners();
  }

  void pause() {
    final group = _group;
    if (group == null) return;
    SoLoud.instance.setPause(group, true);
    _playing = false;
    spectrum.value = const [];
    _ticker?.cancel();
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_playing && !_voiceEnded()) {
      pause();
    } else {
      await play();
    }
  }

  void seek(Duration target) {
    final group = _group;
    if (group == null) return;
    final limit = duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > limit ? limit : target);
    SoLoud.instance.seek(group, clamped);
    notifyListeners();
  }

  Future<void> stop() async {
    _ticker?.cancel();
    final sources = [_vocalsSource, _instrumentalSource];
    for (final handle in [_group, _vocalsHandle, _instrumentalHandle]) {
      if (handle == null) continue;
      try {
        await SoLoud.instance.stop(handle);
      } catch (_) {}
    }
    _vocalsHandle = _instrumentalHandle = _group = null;
    _vocalsSource = _instrumentalSource = null;
    _playing = false;
    spectrum.value = const [];
    for (final source in sources) {
      if (source == null) continue;
      try {
        await SoLoud.instance.disposeSource(source);
      } catch (_) {}
    }
    notifyListeners();
  }

  static const _bands = 32;

  void _onVisualization(AudioVisualizationData data) {
    final fft = data.fftData;
    if (!_playing || fft == null || fft.isEmpty) {
      if (spectrum.value.isNotEmpty) spectrum.value = const [];
      return;
    }
    final previous = spectrum.value;
    final bands = List<double>.filled(_bands, 0);
    for (var b = 0; b < _bands; b++) {
      final from = pow(fft.length, b / _bands).floor().clamp(0, fft.length - 1);
      final to = pow(
        fft.length,
        (b + 1) / _bands,
      ).ceil().clamp(from + 1, fft.length);
      var sum = 0.0;
      for (var i = from; i < to; i++) {
        sum += fft[i];
      }
      final level = (sqrt(sum / (to - from)) * 2.4).clamp(0.0, 1.0);
      final old = previous.length == _bands ? previous[b] : 0.0;
      bands[b] = max(level, old * 0.78);
    }
    spectrum.value = bands;
  }
}
