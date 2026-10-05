import 'package:flutter/foundation.dart';
import 'song_store.dart';

/// What the Studio bottom sheets (Key & Tempo, Natural Voice, Loop & Markers)
/// need from the Studio screen. They rebuild whenever [changes] fires, so a
/// slider moved in a sheet and the player behind it always agree.
abstract class StudioController {
  Listenable get changes;

  bool get isVideo;

  // Key
  String get originalKey;
  String get currentNote;
  String get currentKeyLabel;
  int get semitones;
  int get cents;
  void selectNote(String note);
  void setSemitones(int value);
  void setCents(int value);

  // Tempo
  double get tempo;
  double get originalBpm;
  double get currentBpm;
  void setTempo(double ratio);
  void setOriginalBpm(double bpm);
  int get countInBeats;
  void setCountIn(int beats);

  void resetShift();

  // Natural Voice
  bool get naturalVoice;
  void setNaturalVoice(bool value);

  // Waveform / loop / markers
  List<double> get peaks;
  double get durationSec;
  ValueNotifier<double> get positionSec;
  double? get loopA;
  double? get loopB;
  int get loopRepeats;
  List<SongMarker> get markers;
  void seekTo(double seconds);
  void setLoop(double a, double b);
  void clearLoop();
  void setLoopRepeats(int repeats);
  void addMarker(String name);
  void removeMarker(SongMarker marker);
}
