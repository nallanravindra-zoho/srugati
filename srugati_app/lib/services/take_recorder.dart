import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'srugati_api.dart';

/// Records the singer's microphone while a song plays. The take is mic-only
/// (echo-cancelled so the speaker bleed is reduced) and is saved to the
/// Library as its own recording.
class TakeRecorder {
  TakeRecorder._();

  /// How much earlier (ms) the vocal is placed in the mix. Singers hear the
  /// song a little late (speaker/Bluetooth output) and the mic adds its own
  /// delay, so the take trails the real song; this pulls it back. Remembered.
  static int advanceMs = 150;

  static Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/take_settings.json');
  }

  static Future<void> loadSettings() async {
    try {
      final f = await _settingsFile();
      if (await f.exists()) {
        advanceMs =
            ((jsonDecode(await f.readAsString()) as Map)['advanceMs'] as num)
                .round();
      }
    } catch (_) {}
  }

  static Future<void> _saveSettings() async {
    try {
      await (await _settingsFile()).writeAsString(
        jsonEncode({'advanceMs': advanceMs}),
      );
    } catch (_) {}
  }

  static final TakeRecorder instance = TakeRecorder._();

  final AudioRecorder _rec = AudioRecorder();
  bool _active = false;
  bool _paused = false;
  DateTime? _startedAt;

  bool get active => _active;

  Future<bool> hasPermission() => _rec.hasPermission();

  Future<bool> start() async {
    if (_active) return true;
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/take_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        autoGain: true,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: path,
    );
    _active = true;
    _paused = false;
    _startedAt = DateTime.now();
    return true;
  }

  /// Follows the song: paused while it is paused.
  Future<void> setPaused(bool paused) async {
    if (!_active || _paused == paused) return;
    _paused = paused;
    if (paused) {
      await _rec.pause();
    } else {
      await _rec.resume();
    }
  }

  /// Stops and returns the file path (null if nothing usable was recorded).
  Future<String?> stop() async {
    if (!_active) return null;
    _active = false;
    final started = _startedAt;
    final path = await _rec.stop();
    if (started != null && DateTime.now().difference(started).inSeconds < 2)
      return null;
    return path;
  }

  Future<void> discard() async {
    if (_active) {
      _active = false;
      await _rec.stop();
    }
  }

  /// Asks what to keep. [trackPath] is the backing track the singer heard;
  /// when given, "Mix with the song" sends the take and track to the server,
  /// which mixes them at [semitones]/[tempo] with the vocal entering at
  /// [startSongSec] (a position in the original song).
  static Future<void> askToSave(
    BuildContext context,
    String path,
    String songName, {
    String? trackPath,
    double semitones = 0,
    double tempo = 1.0,
    double startSongSec = 0,
  }) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SimpleDialog(
          title: const Text(
            'Save your vocal take?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          children: [
            if (trackPath != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vocal timing',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setLocal(() => advanceMs -= 25),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text(
                        advanceMs == 0
                            ? 'exact'
                            : '${advanceMs.abs()} ms ${advanceMs > 0 ? 'earlier' : 'later'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setLocal(() => advanceMs += 25),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
            if (trackPath != null)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'mix'),
                child: const Text(
                  'Mix with the song',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'vocal'),
              child: const Text('Vocal only', style: TextStyle(fontSize: 18)),
            ),
            if (trackPath != null)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'both'),
                child: const Text('Both', style: TextStyle(fontSize: 18)),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
    _saveSettings();
    if (choice == null || choice == 'discard' || !context.mounted) return;
    final stamp = DateTime.now();
    final when =
        '${stamp.day}-${stamp.month} ${stamp.hour}:${stamp.minute.toString().padLeft(2, '0')}';
    String? previewPath;
    if (choice == 'vocal' || choice == 'both') {
      await _saveVersion(path, 'Take - $songName $when.m4a');
      previewPath = path;
    }
    if ((choice == 'mix' || choice == 'both') && trackPath != null) {
      final out = await _mixOnServer(
        context,
        trackPath,
        path,
        semitones,
        tempo,
        startSongSec,
      );
      if (out != null) {
        await _saveVersion(out, 'Mix - $songName $when.m4a');
        previewPath = out;
      }
    }
    if (previewPath == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${choice == 'vocal' ? 'Take' : 'Mix'} saved to your Library',
        ),
      ),
    );
  }

  /// Saves into the Library's "Saved versions" (the app documents folder),
  /// where each file gets an inline play button.
  static Future<void> _saveVersion(String source, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    await File(source).copy('${dir.path}/$safe');
  }

  /// Runs the server mix behind a dialog with a Cancel that also stops the
  /// server's work. Returns the mixed file, or null if cancelled / failed.
  static Future<String?> _mixOnServer(
    BuildContext context,
    String trackPath,
    String vocalPath,
    double semitones,
    double tempo,
    double startSongSec,
  ) async {
    final client = http.Client();
    final jobId = SrugatiApi.newJobId();
    var cancelled = false;
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/mix_${DateTime.now().millisecondsSinceEpoch}.m4a';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: const Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                'Mixing your voice with the song…',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              SrugatiApi.cancelJob(jobId);
              client.close();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    String? result;
    String? error;
    try {
      result = await SrugatiApi.mix(
        trackPath: trackPath,
        vocalPath: vocalPath,
        semitones: semitones,
        tempo: tempo,
        // The track plays tempo-times faster, so a position in the song lands earlier in the mix.
        vocalDelaySec: startSongSec / tempo - advanceMs / 1000,
        label: 'mix',
        outputPath: outPath,
        client: client,
        jobId: jobId,
      );
    } catch (e) {
      if (!cancelled && e is! http.ClientException) error = '$e';
    } finally {
      client.close();
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    }
    return cancelled ? null : result;
  }
}
