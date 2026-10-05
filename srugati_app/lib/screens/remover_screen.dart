import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../services/song_store.dart';
import '../services/take_recorder.dart';
import '../services/srugati_api.dart' show SrugatiApiException;
import '../services/stem_player_service.dart';
import '../services/stem_store.dart';
import '../services/vocal_remover_api.dart';
import '../services/wav_peaks.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import '../widgets/stem_orb.dart';
import '../widgets/studio_sheets.dart' show formatSeconds;
import '../widgets/theme_picker_sheet.dart';
import '../widgets/waveform_view.dart';
import 'home_shell.dart';

enum _Stage { idle, working, result }

enum _Phase { uploading, queued, separating, fetching }

enum _MixMode { karaoke, original, vocalsOnly, custom }

const _pickableExtensions = [
  'mp3',
  'wav',
  'm4a',
  'flac',
  'aac',
  'ogg',
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
];

class RemoverScreen extends StatefulWidget {
  const RemoverScreen({super.key});

  @override
  State<RemoverScreen> createState() => RemoverScreenState();
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024)
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}

class RemoverScreenState extends State<RemoverScreen> {
  _Stage _stage = _Stage.idle;
  _Phase _phase = _Phase.uploading;
  double _uploadProgress = 0;
  double _separationProgress = 0;
  double _fetchProgress = 0;
  String _title = '';
  String _sizeLabel = '';
  String? _error;

  http.Client? _client;
  String? _jobId;
  bool _cancelled = false;

  final _stopwatch = Stopwatch();
  Timer? _clockTimer;
  Timer? _positionTimer;
  final _pos = ValueNotifier<double>(0);

  StemResult? _current;
  bool _taking = false;
  double _takeStartSec = 0;
  bool _wasPlaying = false;
  _MixMode _mix = _MixMode.original;

  StemPlayerService get _player => StemPlayerService.instance;

  @override
  void initState() {
    super.initState();
    StemStore.instance.load();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (_stage != _Stage.result) return;
      _player.syncEnded();
      final nowPlaying = _player.playing;
      if (_taking) {
        final dur = _player.duration.inMilliseconds / 1000;
        if (!nowPlaying && _wasPlaying && dur > 0 && _pos.value >= dur - 0.7) {
          _finishTake();
        } else {
          TakeRecorder.instance.setPaused(!nowPlaying);
        }
      }
      _wasPlaying = nowPlaying;
      _pos.value = _player.position.inMilliseconds / 1000;
    });
  }

  @override
  void dispose() {
    TakeRecorder.instance.discard();
    _clockTimer?.cancel();
    _positionTimer?.cancel();
    _client?.close();
    _pos.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Job lifecycle
  // ---------------------------------------------------------------------

  Future<void> _startTake() async {
    if (_taking || _current == null) return;
    if (!await TakeRecorder.instance.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission is needed to record your vocal.',
            ),
          ),
        );
      }
      return;
    }
    if (!_player.playing) await _player.play(from: _player.position);
    if (await TakeRecorder.instance.start()) {
      _takeStartSec = _player.position.inMilliseconds / 1000;
      setState(() => _taking = true);
    }
  }

  Future<void> _finishTake() async {
    if (!_taking) return;
    setState(() => _taking = false);
    _player.pause();
    final path = await TakeRecorder.instance.stop();
    if (!mounted || path == null) return;
    await TakeRecorder.askToSave(
      context,
      path,
      _current?.title ?? 'song',
      trackPath: _current?.instrumentalPath,
      startSongSec: _takeStartSec,
    );
    libraryKey.currentState?.refresh();
  }

  /// Entry point for other screens (e.g. Studio's "Remove vocals").
  Future<void> startWithPath(String path, String title) => _start(path, title);

  double get _overall => switch (_phase) {
    _Phase.uploading => 0.15 * _uploadProgress,
    _Phase.queued => 0.18,
    _Phase.separating => 0.18 + 0.70 * _separationProgress,
    _Phase.fetching => 0.88 + 0.12 * _fetchProgress,
  };

  Future<void> _start(String path, String title) async {
    if (_stage == _Stage.working) return;
    String size = '';
    try {
      size = _formatBytes(await File(path).length());
    } catch (_) {}
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Remove vocals?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '"$title"${size.isEmpty ? '' : ' ($size)'} will be uploaded to the cloud to separate the vocals. You can cancel at any time.',
          style: const TextStyle(fontSize: 17, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upload & remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _player.stop();
    final client = http.Client();
    _client = client;
    _cancelled = false;
    _jobId = null;
    _stopwatch
      ..reset()
      ..start();
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() {
      _stage = _Stage.working;
      _phase = _Phase.uploading;
      _uploadProgress = 0;
      _separationProgress = 0;
      _fetchProgress = 0;
      _title = title;
      _sizeLabel = '';
      _error = null;
      _current = null;
    });
    try {
      final bytes = await File(path).length();
      if (mounted) setState(() => _sizeLabel = _formatBytes(bytes));
    } catch (_) {}

    try {
      final job = await VocalRemoverApi.createJob(
        p.basename(path),
        VocalRemoverApi.contentTypeFor(path),
        client: client,
      );
      _jobId = job.jobId;
      if (_cancelled) return;

      var lastShown = 0.0;
      await VocalRemoverApi.upload(
        job.uploadUrl,
        path,
        job.contentType,
        client: client,
        onProgress: (v) {
          if (v - lastShown >= 0.01 || v >= 1) {
            lastShown = v;
            if (mounted) setState(() => _uploadProgress = v);
          }
        },
      );
      if (_cancelled) return;
      await VocalRemoverApi.confirm(job.jobId, client: client);
      if (mounted) setState(() => _phase = _Phase.queued);

      StemJob status;
      while (true) {
        await Future.delayed(const Duration(milliseconds: 2500));
        if (_cancelled || !mounted) return;
        status = await VocalRemoverApi.getJob(job.jobId, client: client);
        if (status.status == 'cancelled') return;
        if (status.status == 'failed') {
          throw const SrugatiApiException(
            "Couldn't separate this song. Please try a different file.",
          );
        }
        if (status.status == 'done') break;
        setState(() {
          _phase = status.status == 'processing'
              ? _Phase.separating
              : _Phase.queued;
          _separationProgress = status.progress / 100;
        });
      }

      setState(() {
        _phase = _Phase.fetching;
        _fetchProgress = 0;
      });
      final dir = await StemStore.instance.stemDir(job.jobId);
      final vocalsPath = p.join(dir.path, 'vocals.wav');
      final instrumentalPath = p.join(dir.path, 'instrumental.wav');
      await VocalRemoverApi.download(
        status.stems['vocals']!,
        vocalsPath,
        client: client,
        onProgress: (v) {
          if (mounted) setState(() => _fetchProgress = v * 0.5);
        },
      );
      await VocalRemoverApi.download(
        status.stems['instrumental']!,
        instrumentalPath,
        client: client,
        onProgress: (v) {
          if (mounted) setState(() => _fetchProgress = 0.5 + v * 0.5);
        },
      );
      if (_cancelled) return;

      final vocals = await computeWavPeaks(vocalsPath);
      final instrumental = await computeWavPeaks(instrumentalPath);
      final result = StemResult(
        id: job.jobId,
        title: title,
        createdAt: DateTime.now(),
        vocalsPath: vocalsPath,
        instrumentalPath: instrumentalPath,
        durationSec: vocals.durationSec,
        vocalsPeaks: vocals.peaks,
        instrumentalPeaks: instrumental.peaks,
      );
      await StemStore.instance.add(result);
      await _open(result);
    } catch (e) {
      if (_cancelled || e is http.ClientException || !mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = '$e';
      });
    } finally {
      _stopwatch.stop();
      _clockTimer?.cancel();
      if (_client == client) _client = null;
      client.close();
    }
  }

  /// Stops waiting AND tells the service to abandon the job, so the server
  /// stops its separation instead of finishing it for nobody.
  void _cancel() {
    _cancelled = true;
    final id = _jobId;
    if (id != null) VocalRemoverApi.cancel(id);
    _client?.close();
    _stopwatch.stop();
    _clockTimer?.cancel();
    setState(() {
      _stage = _Stage.idle;
      _error = null;
    });
  }

  Future<void> _open(StemResult result) async {
    await _player.load(result);
    _player.updateMix(
      vocals: 1,
      instrumental: 1,
      muteVocals: false,
      muteInstrumental: false,
      vocalsSolo: false,
      instrumentalSolo: false,
    );
    if (!mounted) return;
    setState(() {
      _current = result;
      _mix = _MixMode.original;
      _stage = _Stage.result;
    });
  }

  Future<void> _closeResult() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.idle;
      _current = null;
    });
  }

  // ---------------------------------------------------------------------
  // Picking sources
  // ---------------------------------------------------------------------

  Future<void> _pickFile({required bool audioOnly}) async {
    final picked = await FilePicker.pickFile(
      type: audioOnly ? FileType.audio : FileType.custom,
      allowedExtensions: audioOnly ? null : _pickableExtensions,
    );
    if (picked == null || picked.path == null) return;
    await _start(picked.path!, p.basenameWithoutExtension(picked.name));
  }

  Future<void> _pickFromSongs() async {
    await SongStore.instance.load();
    if (!mounted) return;
    final songs = SongStore.instance.songs;
    final chosen = await showModalBottomSheet<SongRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose a song',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: songs.isEmpty
                    ? const Center(
                        child: Text(
                          'No songs in your Library yet',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: songs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final s = songs[i];
                          return Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              leading: Icon(
                                s.isVideo
                                    ? Icons.movie_rounded
                                    : Icons.music_note_rounded,
                                color: AppColors.purple,
                              ),
                              title: Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(ctx, s),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) await _start(chosen.path, chosen.name);
  }

  // ---------------------------------------------------------------------
  // Mix controls
  // ---------------------------------------------------------------------

  void _setMix(_MixMode mode) {
    setState(() => _mix = mode);
    switch (mode) {
      case _MixMode.karaoke:
        _player.updateMix(
          vocals: 0,
          instrumental: 1,
          muteVocals: false,
          muteInstrumental: false,
          vocalsSolo: false,
          instrumentalSolo: false,
        );
      case _MixMode.original:
        _player.updateMix(
          vocals: 1,
          instrumental: 1,
          muteVocals: false,
          muteInstrumental: false,
          vocalsSolo: false,
          instrumentalSolo: false,
        );
      case _MixMode.vocalsOnly:
        _player.updateMix(
          vocals: 1,
          instrumental: 0,
          muteVocals: false,
          muteInstrumental: false,
          vocalsSolo: false,
          instrumentalSolo: false,
        );
      case _MixMode.custom:
        break;
    }
  }

  Future<void> _save(StemResult r, {required bool vocals}) async {
    try {
      await FileSaver.instance.saveAs(
        name: '${r.title} - ${vocals ? 'vocals' : 'instrumental'}',
        filePath: vocals ? r.vocalsPath : r.instrumentalPath,
        fileExtension: 'wav',
        mimeType: MimeType.other,
      );
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save the file.");
    }
  }

  void _practiceInStudio(StemResult r) {
    _player.pause();
    homeTab.value = 0;
    studioKey.currentState?.importPath(
      r.instrumentalPath,
      '${r.title} (instrumental).wav',
    );
  }

  Future<void> _delete(StemResult r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete these stems?'),
        content: Text(
          '“${r.title}” vocals and instrumental will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_current?.id == r.id) await _closeResult();
    await StemStore.instance.remove(r);
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

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
        title: const Text('Vocal Remover'),
        actions: [
          IconButton(
            tooltip: 'Theme',
            icon: Icon(Icons.palette_outlined, color: AppColors.purple),
            onPressed: () => ThemePickerSheet.show(context),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.75),
            radius: 1.1,
            colors: [
              AppColors.purple.withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: switch (_stage) {
              _Stage.idle => _buildIdle(),
              _Stage.working => _buildWorking(),
              _Stage.result => _buildResult(),
            },
          ),
        ),
      ),
    );
  }

  Widget _glass({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.22)),
      ),
      child: child,
    );
  }

  // ---- idle -----------------------------------------------------------

  Widget _sourceTile(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: AppColors.surfaceMuted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
            child: Column(
              children: [
                Icon(icon, color: AppColors.purple, size: 26),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: StemOrb(
            size: 230,
            center: Icon(
              Icons.graphic_eq_rounded,
              size: 46,
              color: AppColors.purple,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'STEM LAB',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Split any song into vocals and instrumental',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 20),
        _glass(
          child: Row(
            children: [
              _sourceTile(
                Icons.library_music_rounded,
                'My songs',
                _pickFromSongs,
              ),
              const SizedBox(width: 10),
              _sourceTile(
                Icons.folder_rounded,
                'Files',
                () => _pickFile(audioOnly: false),
              ),
              const SizedBox(width: 10),
              _sourceTile(
                Icons.queue_music_rounded,
                'Device music',
                () => _pickFile(audioOnly: true),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ListenableBuilder(
          listenable: StemStore.instance,
          builder: (context, _) {
            final results = StemStore.instance.results;
            if (results.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 26),
                const Text(
                  'Recent results',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                for (final r in results) ...[
                  _resultTile(r),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _resultTile(StemResult r) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(r),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Vocals + instrumental · ${formatSeconds(r.durationSec)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _delete(r),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- working --------------------------------------------------------

  String get _phaseTitle => switch (_phase) {
    _Phase.uploading => 'Uploading your song',
    _Phase.queued => 'Waiting for a free AI core',
    _Phase.separating => 'Separating vocals',
    _Phase.fetching => 'Fetching your stems',
  };

  String get _phaseHint => switch (_phase) {
    _Phase.uploading => 'Sending it securely to the cloud…',
    _Phase.queued =>
      'Starting the separation engine — the first run can take a minute.',
    _Phase.separating => 'The AI is pulling the voice apart from the music. Longer songs take longer.',
    _Phase.fetching => 'Almost there — bringing the stems to your phone.',
  };

  Widget _buildWorking() {
    final overall = _overall;
    final elapsed = _stopwatch.elapsed;
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    const steps = [
      (Icons.cloud_upload_rounded, 'Upload'),
      (Icons.hourglass_top_rounded, 'Queue'),
      (Icons.auto_awesome_rounded, 'Separate'),
      (Icons.download_rounded, 'Fetch'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: StemOrb(
            size: 290,
            progress: overall,
            spinning: true,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(overall * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$mm:$ss',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _phaseTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _sizeLabel.isEmpty ? _title : '$_title · $_sizeLabel',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.purple,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _phaseHint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 22),
        _glass(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: i <= _phase.index
                              ? AppColors.brandGradient
                              : null,
                          color: i <= _phase.index
                              ? null
                              : AppColors.surfaceMuted,
                          boxShadow: i == _phase.index
                              ? [
                                  BoxShadow(
                                    color: AppColors.purple.withValues(
                                      alpha: 0.6,
                                    ),
                                    blurRadius: 16,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          i < _phase.index ? Icons.check_rounded : steps[i].$1,
                          size: 20,
                          color: i <= _phase.index
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        steps[i].$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == _phase.index
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: i <= _phase.index
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: _cancel,
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  // ---- result ---------------------------------------------------------

  Widget _mixChip(String label, IconData icon, _MixMode mode) {
    final selected = _mix == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setMix(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brandGradient : null,
            color: selected
                ? null
                : AppColors.surfaceMuted.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.purple.withValues(alpha: 0.4),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleButton(
    String letter,
    bool on,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: on ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _lane({required StemResult result, required bool vocals}) {
    final tint = vocals ? AppColors.teal : AppColors.purple;
    final level = vocals ? _player.vocalsLevel : _player.instrumentalLevel;
    final muted = vocals ? _player.vocalsMuted : _player.instrumentalMuted;
    final solo = vocals ? _player.soloVocals : _player.soloInstrumental;
    return _glass(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                vocals ? Icons.record_voice_over_rounded : Icons.piano_rounded,
                color: tint,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                vocals ? 'Vocals' : 'Instrumental',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              _toggleButton('M', muted, () {
                setState(() => _mix = _MixMode.custom);
                _player.updateMix(
                  muteVocals: vocals ? !muted : null,
                  muteInstrumental: vocals ? null : !muted,
                );
              }, AppColors.warning),
              const SizedBox(width: 8),
              _toggleButton('S', solo, () {
                setState(() => _mix = _MixMode.custom);
                _player.updateMix(
                  vocalsSolo: vocals ? !solo : null,
                  instrumentalSolo: vocals ? null : !solo,
                );
              }, tint),
            ],
          ),
          const SizedBox(height: 8),
          WaveformView(
            peaks: vocals ? result.vocalsPeaks : result.instrumentalPeaks,
            durationSec: result.durationSec,
            positionSec: _pos,
            spectrum: _player.spectrum,
            tint: tint,
            height: 58,
            onSeek: (s) =>
                _player.seek(Duration(milliseconds: (s * 1000).round())),
          ),
          Row(
            children: [
              Icon(
                level == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              Expanded(
                child: Slider(
                  value: level,
                  onChanged: (v) {
                    setState(() => _mix = _MixMode.custom);
                    _player.updateMix(
                      vocals: vocals ? v : null,
                      instrumental: vocals ? null : v,
                    );
                  },
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${(level * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final result = _current!;
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final playing = _player.playing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Stems ready',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _closeResult,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: StemOrb(
                size: 250,
                spectrum: _player.spectrum,
                center: GestureDetector(
                  onTap: _player.toggle,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purple.withValues(alpha: 0.55),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _pos,
              builder: (_, pos, __) => Text(
                '${formatSeconds(pos)}  /  ${formatSeconds(result.durationSec)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.5,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _mixChip('Karaoke', Icons.mic_off_rounded, _MixMode.karaoke),
                const SizedBox(width: 8),
                _mixChip(
                  'Original',
                  Icons.queue_music_rounded,
                  _MixMode.original,
                ),
                const SizedBox(width: 8),
                _mixChip('Vocals', Icons.mic_rounded, _MixMode.vocalsOnly),
              ],
            ),
            const SizedBox(height: 14),
            _lane(result: result, vocals: true),
            const SizedBox(height: 12),
            _lane(result: result, vocals: false),
            const SizedBox(height: 18),
            _taking
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _finishTake,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text(
                      'Recording your vocal · Stop & save',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _startTake,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text(
                      'Sing along & record',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Practise with the instrumental',
              icon: Icons.tune_rounded,
              onPressed: () => _practiceInStudio(result),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _save(result, vocals: true),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save vocals'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _save(result, vocals: false),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save instrumental'),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        );
      },
    );
  }
}
