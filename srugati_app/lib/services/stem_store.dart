import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A finished vocal/instrumental separation, kept on the device so it can be
/// replayed offline long after the server's copies expire.
class StemResult {
  final String id;
  final String title;
  final DateTime createdAt;
  final String vocalsPath;
  final String instrumentalPath;
  final double durationSec;
  final List<double> vocalsPeaks;
  final List<double> instrumentalPeaks;

  const StemResult({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.vocalsPath,
    required this.instrumentalPath,
    required this.durationSec,
    required this.vocalsPeaks,
    required this.instrumentalPeaks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'vocalsPath': vocalsPath,
    'instrumentalPath': instrumentalPath,
    'durationSec': durationSec,
    'vocalsPeaks': vocalsPeaks,
    'instrumentalPeaks': instrumentalPeaks,
  };

  factory StemResult.fromJson(Map<String, dynamic> j) => StemResult(
    id: j['id'] as String,
    title: j['title'] as String,
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    vocalsPath: j['vocalsPath'] as String,
    instrumentalPath: j['instrumentalPath'] as String,
    durationSec: (j['durationSec'] as num).toDouble(),
    vocalsPeaks: (j['vocalsPeaks'] as List)
        .map((v) => (v as num).toDouble())
        .toList(),
    instrumentalPeaks: (j['instrumentalPeaks'] as List)
        .map((v) => (v as num).toDouble())
        .toList(),
  );
}

class StemStore extends ChangeNotifier {
  StemStore._();
  static final StemStore instance = StemStore._();

  final List<StemResult> _results = [];
  bool _loaded = false;

  List<StemResult> get results => List.unmodifiable(
    _results.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  Future<Directory> stemDir(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'stems', id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _index() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'stems.json'));
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _index();
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List;
      _results
        ..clear()
        ..addAll(
          list
              .map((e) => StemResult.fromJson(e as Map<String, dynamic>))
              .where(
                (r) =>
                    File(r.vocalsPath).existsSync() &&
                    File(r.instrumentalPath).existsSync(),
              ),
        );
      notifyListeners();
    } catch (_) {
      // A damaged index just starts empty; the stem files stay on disk.
    }
  }

  Future<void> _save() async {
    await (await _index()).writeAsString(
      jsonEncode(_results.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> add(StemResult result) async {
    await load();
    _results.removeWhere((r) => r.id == result.id);
    _results.add(result);
    await _save();
    notifyListeners();
  }

  Future<void> remove(StemResult result) async {
    _results.removeWhere((r) => r.id == result.id);
    try {
      await Directory(p.dirname(result.vocalsPath)).delete(recursive: true);
    } catch (_) {}
    await _save();
    notifyListeners();
  }
}
