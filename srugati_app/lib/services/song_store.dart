import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SongMarker {
  final String name;
  final double seconds;
  const SongMarker(this.name, this.seconds);

  Map<String, dynamic> toJson() => {'name': name, 'seconds': seconds};
  factory SongMarker.fromJson(Map<String, dynamic> j) =>
      SongMarker(j['name'] as String, (j['seconds'] as num).toDouble());
}

/// One imported song plus its saved "practice recipe" (key, tempo, voice
/// mode, loop and markers), so reopening it restores exactly where you were.
class SongRecord {
  final String id;
  String name;
  String path;
  bool isVideo;
  String? originalTonic;
  String? keyMode;
  double? originalBpm;
  double? durationSec;
  List<double> waveform;

  int semitones;
  int cents;
  double tempo;
  bool naturalVoice;
  int countInBeats;
  double? loopA;
  double? loopB;
  int loopRepeats;
  List<SongMarker> markers;

  /// Beat grid (from detection) and the metronome / training settings.
  double? beatOffset;
  bool metronomeOn;
  double metronomeVolume;
  double metronomeRate;
  int trainStartPct;
  int trainStepPct;
  int trainRepeats;

  bool favorite;
  DateTime lastOpened;

  SongRecord({
    required this.id,
    required this.name,
    required this.path,
    required this.isVideo,
    this.originalTonic,
    this.keyMode,
    this.originalBpm,
    this.durationSec,
    this.waveform = const [],
    this.semitones = 0,
    this.cents = 0,
    this.tempo = 1.0,
    this.naturalVoice = false,
    this.countInBeats = 0,
    this.loopA,
    this.loopB,
    this.loopRepeats = 0,
    this.markers = const [],
    this.beatOffset,
    this.metronomeOn = false,
    this.metronomeVolume = 0.8,
    this.metronomeRate = 1.0,
    this.trainStartPct = 70,
    this.trainStepPct = 10,
    this.trainRepeats = 2,
    this.favorite = false,
    DateTime? lastOpened,
  }) : lastOpened = lastOpened ?? DateTime.now();

  bool get hasRecipe =>
      semitones != 0 || cents != 0 || (tempo - 1.0).abs() > 1e-6;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'isVideo': isVideo,
    'originalTonic': originalTonic,
    'keyMode': keyMode,
    'originalBpm': originalBpm,
    'durationSec': durationSec,
    'waveform': waveform,
    'semitones': semitones,
    'cents': cents,
    'tempo': tempo,
    'naturalVoice': naturalVoice,
    'countInBeats': countInBeats,
    'loopA': loopA,
    'loopB': loopB,
    'loopRepeats': loopRepeats,
    'markers': markers.map((m) => m.toJson()).toList(),
    'beatOffset': beatOffset,
    'metronomeOn': metronomeOn,
    'metronomeVolume': metronomeVolume,
    'metronomeRate': metronomeRate,
    'trainStartPct': trainStartPct,
    'trainStepPct': trainStepPct,
    'trainRepeats': trainRepeats,
    'favorite': favorite,
    'lastOpened': lastOpened.toIso8601String(),
  };

  factory SongRecord.fromJson(Map<String, dynamic> j) => SongRecord(
    id: j['id'] as String,
    name: j['name'] as String,
    path: j['path'] as String,
    isVideo: j['isVideo'] as bool? ?? false,
    originalTonic: j['originalTonic'] as String?,
    keyMode: j['keyMode'] as String?,
    originalBpm: (j['originalBpm'] as num?)?.toDouble(),
    durationSec: (j['durationSec'] as num?)?.toDouble(),
    waveform: ((j['waveform'] as List?) ?? const [])
        .map((v) => (v as num).toDouble())
        .toList(),
    semitones: j['semitones'] as int? ?? 0,
    cents: j['cents'] as int? ?? 0,
    tempo: (j['tempo'] as num?)?.toDouble() ?? 1.0,
    naturalVoice: j['naturalVoice'] as bool? ?? false,
    countInBeats: j['countInBeats'] as int? ?? 0,
    loopA: (j['loopA'] as num?)?.toDouble(),
    loopB: (j['loopB'] as num?)?.toDouble(),
    loopRepeats: j['loopRepeats'] as int? ?? 0,
    markers: ((j['markers'] as List?) ?? const [])
        .map((m) => SongMarker.fromJson(m as Map<String, dynamic>))
        .toList(),
    beatOffset: (j['beatOffset'] as num?)?.toDouble(),
    metronomeOn: j['metronomeOn'] as bool? ?? false,
    metronomeVolume: (j['metronomeVolume'] as num?)?.toDouble() ?? 0.8,
    metronomeRate: (j['metronomeRate'] as num?)?.toDouble() ?? 1.0,
    trainStartPct: j['trainStartPct'] as int? ?? 70,
    trainStepPct: j['trainStepPct'] as int? ?? 10,
    trainRepeats: j['trainRepeats'] as int? ?? 2,
    favorite: j['favorite'] as bool? ?? false,
    lastOpened: DateTime.tryParse(j['lastOpened'] as String? ?? ''),
  );
}

class SongStore extends ChangeNotifier {
  SongStore._();
  static final SongStore instance = SongStore._();

  final List<SongRecord> _songs = [];
  bool _loaded = false;

  List<SongRecord> get songs => List.unmodifiable(
    _songs.toList()..sort((a, b) => b.lastOpened.compareTo(a.lastOpened)),
  );

  Future<File> _indexFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'songs.json'));
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _indexFile();
      if (await file.exists()) {
        final list = jsonDecode(await file.readAsString()) as List;
        _songs
          ..clear()
          ..addAll(
            list
                .map((e) => SongRecord.fromJson(e as Map<String, dynamic>))
                .where((s) => File(s.path).existsSync()),
          );
        await _migrateRecordings();
        notifyListeners();
      }
    } catch (_) {
      // A corrupt index just means starting with an empty library.
    }
  }

  /// Sing-along takes and mixes used to be stored as songs. They belong with
  /// the Library's "Saved versions" (inline play), so move any old ones there.
  Future<void> _migrateRecordings() async {
    final docs = await getApplicationDocumentsDirectory();
    final moved = <SongRecord>[];
    for (final s in _songs) {
      final isRecording =
          s.originalTonic == null &&
          (s.name.startsWith('Take - ') || s.name.startsWith('Mix - '));
      if (!isRecording) continue;
      try {
        final dest = p.join(
          docs.path,
          '${s.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}${p.extension(s.path)}',
        );
        await File(s.path).copy(dest);
        await File(s.path).delete();
        moved.add(s);
      } catch (_) {}
    }
    if (moved.isEmpty) return;
    _songs.removeWhere((s) => moved.contains(s));
    await _save();
  }

  Future<void> _save() async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(_songs.map((s) => s.toJson()).toList()),
    );
  }

  SongRecord? byId(String id) {
    for (final s in _songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Copies a picked/recorded file into app storage (the picker's cache copy
  /// can be cleared by the OS) and returns the new, not-yet-analysed record.
  Future<SongRecord> importFile(String sourcePath, String displayName) async {
    await load();
    final docs = await getApplicationDocumentsDirectory();
    final songsDir = Directory(p.join(docs.path, 'songs'));
    await songsDir.create(recursive: true);

    final id = '${DateTime.now().millisecondsSinceEpoch}';
    final dest = p.join(songsDir.path, '${id}_${p.basename(displayName)}');
    await File(sourcePath).copy(dest);

    final ext = p.extension(displayName).toLowerCase().replaceFirst('.', '');
    final record = SongRecord(
      id: id,
      name: p.basenameWithoutExtension(displayName),
      path: dest,
      isVideo: const {'mp4', 'mov', 'mkv', 'webm', 'avi'}.contains(ext),
    );
    _songs.add(record);
    await _save();
    notifyListeners();
    return record;
  }

  Future<void> update(SongRecord song) async {
    if (byId(song.id) == null) return;
    await _save();
    notifyListeners();
  }

  Future<void> remove(SongRecord song) async {
    _songs.removeWhere((s) => s.id == song.id);
    try {
      await File(song.path).delete();
    } catch (_) {}
    await _save();
    notifyListeners();
  }
}
