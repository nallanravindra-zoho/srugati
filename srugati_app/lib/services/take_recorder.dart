import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'song_store.dart';
import 'srugati_api.dart';

/// Records the singer's microphone while a song plays. The take is mic-only
/// (echo-cancelled so the speaker bleed is reduced) and is saved to the
/// Library as its own recording.
class TakeRecorder {
  TakeRecorder._();
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
      const RecordConfig(echoCancel: true, noiseSuppress: true),
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
      builder: (ctx) => SimpleDialog(
        title: const Text(
          'Save your vocal take?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        children: [
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
    );
    if (choice == null || choice == 'discard' || !context.mounted) return;
    final stamp = DateTime.now();
    final when =
        '${stamp.day}-${stamp.month} ${stamp.hour}:${stamp.minute.toString().padLeft(2, '0')}';
    String? previewPath;
    String previewName = 'Take - $songName $when';
    if (choice == 'vocal' || choice == 'both') {
      await SongStore.instance.importFile(path, 'Take - $songName $when.m4a');
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
        await SongStore.instance.importFile(out, 'Mix - $songName $when.m4a');
        previewPath = out;
        previewName = 'Mix - $songName $when';
      }
    }
    if (previewPath == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SavedPreviewDialog(path: previewPath!, name: previewName),
    );
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
        vocalDelaySec: startSongSec / tempo,
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

/// Shown after a take or mix is saved to the Library: plays the result so it
/// can be checked, and can also copy it to a place the user picks on the device.
class _SavedPreviewDialog extends StatefulWidget {
  final String path;
  final String name;
  const _SavedPreviewDialog({required this.path, required this.name});

  @override
  State<_SavedPreviewDialog> createState() => _SavedPreviewDialogState();
}

class _SavedPreviewDialogState extends State<_SavedPreviewDialog> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final done = s.processingState == ProcessingState.completed;
      setState(() => _playing = s.playing && !done);
      if (done) {
        _player.pause();
        _player.seek(Duration.zero);
      }
    });
    _player
        .setFilePath(widget.path)
        .then((_) => _player.play())
        .catchError((_) {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _saveToDevice() async {
    try {
      await FileSaver.instance.saveAs(
        name: widget.name,
        filePath: widget.path,
        fileExtension: 'm4a',
        mimeType: MimeType.other,
      );
      if (mounted) setState(() => _note = 'Saved to the location you chose');
    } catch (_) {
      if (mounted) setState(() => _note = "Couldn't save to that location");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Saved to your Library',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _playing ? _player.pause() : _player.play(),
            icon: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(_playing ? 'Pause' : 'Play'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saveToDevice,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Save to my device…'),
          ),
          if (_note != null) ...[
            const SizedBox(height: 10),
            Text(_note!, style: const TextStyle(fontSize: 16)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
