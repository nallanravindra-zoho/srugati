import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/live_pitch_service.dart';
import '../services/player_service.dart';
import '../services/song_store.dart';
import '../services/stem_player_service.dart';
import '../services/srugati_api.dart';
import '../services/studio_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/add_song_panel.dart';
import '../widgets/download_format_sheet.dart';
import '../widgets/gradient_button.dart';
import '../widgets/note_chip_row.dart';
import '../widgets/record_dialog.dart';
import '../widgets/studio_sheets.dart';
import '../widgets/theme_picker_sheet.dart';
import '../widgets/waveform_view.dart';
import '../services/take_recorder.dart';
import 'home_shell.dart';
import 'video_player_screen.dart';

const _acceptedExtensions = [
  'mp3',
  'wav',
  'm4a',
  'aac',
  'flac',
  'ogg',
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
];

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => StudioScreenState();
}

enum _Stage { idle, analyzing, ready, shifting }

class _Changes extends ChangeNotifier {
  void bump() => notifyListeners();
}

class StudioScreenState extends State<StudioScreen>
    implements StudioController {
  _Stage _stage = _Stage.idle;
  SongRecord? _song;
  String? _error;

  /// Library file produced by "Save"; never the playback engine's file.
  String? _shiftedPath;
  String? _lastSavedSignature;

  /// Natural Voice (server) render currently loaded into the shared player.
  String? _previewPath;
  bool _serverEngine = false;
  bool _serverBusy = false;
  String _busyLabel = 'Working on the server…';
  bool _cancelled = false;
  String? _jobId;
  bool _downloading = false;
  http.Client? _activeClient;

  final _changes = _Changes();
  final _pos = ValueNotifier<double>(0);
  double _pendingStart = 0;
  double _lastPos = 0;
  int _loopPasses = 0;
  bool _wasPlaying = false;
  bool _countingIn = false;
  bool _taking = false;
  double _takeStartSec = 0;
  double _takeSemitones = 0;
  double _takeTempo = 1.0;

  /// Sing along: records the microphone while the song plays.
  Future<void> _startTake() async {
    if (_song == null || isVideo || _taking || _countingIn) return;
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
    if (!_enginePlaying) await _togglePlay();
    if (!mounted) return;
    final startAt = _enginePosSec;
    if (await TakeRecorder.instance.start()) {
      _takeStartSec = startAt;
      _takeSemitones = totalSemitones;
      _takeTempo = tempo;
      setState(() => _taking = true);
    }
  }

  /// Stops the take and asks whether to keep it.
  Future<void> _finishTake() async {
    if (!_taking) return;
    setState(() => _taking = false);
    _enginePause();
    final path = await TakeRecorder.instance.stop();
    if (!mounted || path == null) return;
    await TakeRecorder.askToSave(
      context,
      path,
      _song?.name ?? 'song',
      trackPath: _song?.path,
      semitones: _takeSemitones,
      tempo: _takeTempo,
      startSongSec: _takeStartSec,
    );
  }

  // Metronome click scheduling + progressive training state.
  Timer? _clickTimer;
  int _lastBeat = -1;
  bool _training = false;
  int _trainPct = 70;
  int _trainPassCount = 0;

  Timer? _tickTimer;
  Timer? _renderDebounce;
  Timer? _persistDebounce;

  LivePitchService get _live => LivePitchService.instance;

  @override
  void initState() {
    super.initState();
    SongStore.instance.load();
    _tickTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _tick(),
    );
    _clickTimer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _clickTick(),
    );
  }

  // The bottom sheets listen to [changes]; every Studio rebuild also bumps it.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.bump();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _clickTimer?.cancel();
    TakeRecorder.instance.discard();
    _renderDebounce?.cancel();
    _persistDebounce?.cancel();
    _flushPersist();
    _live.stop();
    _activeClient?.close();
    _changes.dispose();
    _pos.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Recipe state (stored on the SongRecord so it persists per song)
  // ---------------------------------------------------------------------

  String get _originalTonic => _song?.originalTonic ?? 'C';

  @override
  bool get analysed => _song?.originalTonic != null;

  @override
  Listenable get changes => _changes;

  @override
  bool get isVideo => _song?.isVideo ?? false;

  @override
  String get originalKey => analysed ? _originalTonic : '—';

  @override
  int get semitones => _song?.semitones ?? 0;

  @override
  int get cents => _song?.cents ?? 0;

  double get totalSemitones => semitones + cents / 100.0;

  @override
  String get currentNote {
    final idx = kNoteNames.indexOf(_originalTonic);
    return kNoteNames[(((idx < 0 ? 0 : idx) + semitones) % 12 + 12) % 12];
  }

  @override
  String get currentKeyLabel => analysed
      ? currentNote
      : (semitones == 0 ? '—' : '${semitones > 0 ? '+' : ''}$semitones st');

  @override
  double get tempo => _song?.tempo ?? 1.0;

  @override
  double get originalBpm => _song?.originalBpm ?? 120;

  @override
  double get currentBpm => originalBpm * tempo;

  @override
  int get countInBeats => _song?.countInBeats ?? 0;

  @override
  bool get naturalVoice => _song?.naturalVoice ?? false;

  @override
  List<double> get peaks => _song?.waveform ?? const [];

  @override
  double get durationSec {
    final stored = _song?.durationSec;
    if (stored != null && stored > 0) return stored;
    return _live.length.inMilliseconds / 1000;
  }

  @override
  ValueNotifier<double> get positionSec => _pos;

  @override
  double? get loopA => _song?.loopA;

  @override
  double? get loopB => _song?.loopB;

  @override
  int get loopRepeats => _song?.loopRepeats ?? 0;

  @override
  List<SongMarker> get markers => _song?.markers ?? const [];

  bool get _hasShift =>
      semitones != 0 || cents != 0 || (tempo - 1.0).abs() > 1e-6;

  bool get _serverMode =>
      naturalVoice && !isVideo && !_training && (semitones != 0 || cents != 0);

  String _currentSaveSignature() =>
      '$semitones|$cents|${tempo.toStringAsFixed(3)}|${isVideo ? true : naturalVoice}';

  /// False once "Save"/"Shift" already produced a Library file for exactly
  /// these settings — tapping again just re-opens the download sheet.
  bool get _needsSave => _lastSavedSignature != _currentSaveSignature();

  bool get _showingShiftedVideo => _hasShift && !_needsSave;

  String get _pitchSummary {
    final st = semitones > 0 ? '+$semitones' : '$semitones';
    if (cents == 0) return '$st semitones';
    return '$st st ${cents > 0 ? '+' : ''}$cents¢';
  }

  void _persistSoon() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), _flushPersist);
  }

  void _flushPersist() {
    final song = _song;
    if (song != null) SongStore.instance.update(song);
  }

  // ---------------------------------------------------------------------
  // Opening songs
  // ---------------------------------------------------------------------

  /// Entry point shared by the Studio empty state and the Library "+" sheet.
  Future<void> importFrom(ImportSource source) async {
    String? path;
    String? name;
    switch (source) {
      case ImportSource.files:
      case ImportSource.deviceMusic:
        final picked = await FilePicker.pickFile(
          type: source == ImportSource.deviceMusic
              ? FileType.audio
              : FileType.custom,
          allowedExtensions: source == ImportSource.deviceMusic
              ? null
              : _acceptedExtensions,
        );
        if (picked == null || picked.path == null) return;
        path = picked.path;
        name = picked.name;
      case ImportSource.record:
        final recorded = await RecordDialog.show(context);
        if (recorded == null) return;
        path = recorded;
        final stamp = DateTime.now();
        name =
            'Recording ${stamp.day}-${stamp.month} ${stamp.hour}:${stamp.minute.toString().padLeft(2, '0')}.m4a';
    }
    await _beginImport(path!, name);
  }

  /// Opens a file from elsewhere in the app (e.g. a separated instrumental).
  Future<void> importPath(String path, String name) => _beginImport(path, name);

  Future<void> _beginImport(String path, String name) async {
    await _closeSong(keepStage: true);
    final SongRecord record;
    try {
      record = await SongStore.instance.importFile(path, name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _stage = _Stage.idle;
      });
      return;
    }
    if (!mounted) return;
    final analyse = await _askToAnalyse(record);
    if (!mounted) return;
    if (analyse == null) {
      // Dismissed: drop the import entirely.
      await SongStore.instance.remove(record);
      setState(() => _stage = _Stage.idle);
      return;
    }
    if (!analyse) {
      await openSong(record);
      return;
    }
    await _analyse(record, removeOnFail: true);
  }

  /// Detection uses the server, so it is the user's choice, not automatic.
  Future<bool?> _askToAnalyse(SongRecord record) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Detect key & tempo?'),
        content: Text(
          '"${record.name}" can be analysed on the server to find its key, tempo and beat so notes and BPM show correctly. '
          'Skip it to load the song right away — pitch and tempo shifting still work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Detect'),
          ),
        ],
      ),
    );
  }

  /// Runs key/tempo detection for [record] and opens it. With
  /// [removeOnFail] a failed or cancelled run discards the new import;
  /// otherwise the song just opens as it was.
  Future<void> _analyse(SongRecord record, {required bool removeOnFail}) async {
    await _closeSong(keepStage: true);
    final client = http.Client();
    _activeClient = client;
    _cancelled = false;
    _jobId = SrugatiApi.newJobId();
    setState(() {
      _error = null;
      _stage = _Stage.analyzing;
    });

    try {
      final result = await SrugatiApi.detectPitch(
        record.path,
        client: client,
        jobId: _jobId,
      );
      if (_cancelled) throw http.ClientException('cancelled');
      record
        ..originalTonic = result.tonic
        ..keyMode = result.keyMode
        ..originalBpm = result.bpm
        ..beatOffset = result.beatOffsetSec
        ..durationSec = result.durationSec
        ..waveform = result.waveform;
      await SongStore.instance.update(record);
      await openSong(record);
    } catch (e) {
      if (!mounted) return;
      final quiet = _cancelled || e is http.ClientException;
      if (removeOnFail) {
        await SongStore.instance.remove(record);
        setState(() {
          _error = quiet ? null : '$e';
          _stage = _Stage.idle;
        });
      } else {
        await openSong(record);
        if (!quiet && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    } finally {
      if (_activeClient == client) _activeClient = null;
      client.close();
    }
  }

  /// Stops the analysis: the request is dropped, which also tells the
  /// server to abandon the work, and the half-imported copy is removed.
  void _cancelImport() {
    _cancelled = true;
    _cancelServerJob();
    _activeClient?.close();
  }

  void _cancelServerJob() {
    final id = _jobId;
    _jobId = null;
    if (id != null) SrugatiApi.cancelJob(id);
  }

  /// Back arrow / system back. Returns true if it handled the press.
  bool handleBack() {
    if (_stage == _Stage.analyzing) {
      _cancelImport();
      return true;
    }
    if (_serverBusy) {
      _cancelBusy();
      return true;
    }
    if (_song != null) {
      _closeSong();
      return true;
    }
    return false;
  }

  /// Opens an already-imported song with its saved key, tempo, loop, etc.
  Future<void> openSong(SongRecord song) async {
    await _closeSong(keepStage: true);
    song.lastOpened = DateTime.now();
    setState(() {
      _song = song;
      _stage = _Stage.ready;
      _shiftedPath = null;
      _previewPath = null;
      _serverEngine = false;
      _lastSavedSignature = null;
      _pendingStart = 0;
      _loopPasses = 0;
      _error = null;
      _pos.value = 0;
    });
    _flushPersist();
    if (isVideo) return;
    await _ensureLiveLoaded();
    if (_serverMode) _scheduleServerRender(immediate: true);
  }

  Future<void> _closeSong({bool keepStage = false}) async {
    if (_taking) await _finishTake();
    _renderDebounce?.cancel();
    _persistDebounce?.cancel();
    _flushPersist();
    _activeClient?.close();
    _activeClient = null;
    if (_serverEngine) await PlayerService.instance.pause();
    await _live.stop();
    if (!mounted) return;
    setState(() {
      _song = null;
      _serverEngine = false;
      _serverBusy = false;
      _previewPath = null;
      _shiftedPath = null;
      if (!keepStage) _stage = _Stage.idle;
    });
  }

  Future<void> _ensureLiveLoaded() async {
    final song = _song;
    if (song == null || song.isVideo) return;
    await _live.load(song.path);
    _live.setSemitones(totalSemitones);
    _live.setTempo(tempo);
  }

  // ---------------------------------------------------------------------
  // Playback transport (live engine or the Natural Voice render)
  // ---------------------------------------------------------------------

  bool get _serverActive =>
      _serverEngine &&
      _previewPath != null &&
      PlayerService.instance.currentPath == _previewPath;

  bool get _enginePlaying =>
      _serverActive ? PlayerService.instance.player.playing : _live.playing;

  /// Position in *song* seconds, whichever engine is active (a rendered file
  /// is time-scaled by the tempo, so convert back).
  double get _enginePosSec {
    if (_serverActive)
      return PlayerService.instance.player.position.inMilliseconds /
          1000 *
          tempo;
    return _live.hasHandle
        ? _live.position.inMilliseconds / 1000
        : _pendingStart;
  }

  void _seekEngine(double seconds) {
    if (_serverActive) {
      PlayerService.instance.seek(
        Duration(milliseconds: (seconds / tempo * 1000).round()),
      );
    } else if (_live.hasHandle) {
      _live.seek(Duration(milliseconds: (seconds * 1000).round()));
    } else {
      _pendingStart = seconds;
    }
  }

  Future<void> _enginePlay() async {
    StemPlayerService.instance.pause();
    if (_serverActive) {
      await PlayerService.instance.play();
      return;
    }
    await _ensureLiveLoaded();
    await _live.play(
      from: Duration(milliseconds: (_pendingStart * 1000).round()),
    );
    _pendingStart = 0;
  }

  void _enginePause() {
    if (_serverActive) {
      PlayerService.instance.pause();
    } else if (_live.hasHandle) {
      _live.pause();
    }
  }

  Future<void> _togglePlay() async {
    if (_countingIn || _song == null) return;
    if (_enginePlaying) {
      _enginePause();
      return;
    }
    if (countInBeats > 0) {
      setState(() => _countingIn = true);
      final gap = Duration(milliseconds: (60000 / currentBpm).round());
      for (var i = 0; i < countInBeats; i++) {
        await _live.playClick(accent: i == 0);
        await Future.delayed(gap);
      }
      if (!mounted) return;
      setState(() => _countingIn = false);
    }
    await _enginePlay();
  }

  void _tick() {
    if (!mounted || _song == null || _stage != _Stage.ready || isVideo) return;
    _live.syncEnded();
    final playing = _enginePlaying;
    final pos = _enginePosSec;
    if (_taking) {
      final ended =
          !playing &&
          _wasPlaying &&
          durationSec > 0 &&
          _lastPos >= durationSec - 0.7;
      if (ended) {
        _finishTake();
      } else {
        TakeRecorder.instance.setPaused(!playing);
      }
    }
    if (playing) _handleLoop(pos);
    _pos.value = pos;
    _lastPos = pos;
    if (playing != _wasPlaying) setState(() => _wasPlaying = playing);
  }

  void _handleLoop(double pos) {
    if (_training) {
      _handleTraining(pos);
      return;
    }
    final a = loopA, b = loopB;
    if (a == null || b == null) {
      _loopPasses = 0;
      return;
    }
    if (pos < a - 0.5) _loopPasses = 0;
    if (_lastPos < b && pos >= b) {
      _loopPasses++;
      final repeats = loopRepeats;
      if (repeats == 0 || _loopPasses < repeats) _seekEngine(a);
    }
  }

  // ---------------------------------------------------------------------
  // Metronome
  // ---------------------------------------------------------------------

  @override
  bool get metronomeOn => _song?.metronomeOn ?? false;

  @override
  double get metronomeVolume => _song?.metronomeVolume ?? 0.8;

  @override
  double get metronomeRate => _song?.metronomeRate ?? 1.0;

  @override
  int get beatNudgeMs => _beatNudgeMs;
  int _beatNudgeMs = 0;

  @override
  void setMetronomeOn(bool on) {
    _song?.metronomeOn = on;
    if (on) {
      _live.preloadClick();
      _lastBeat = -1;
    }
    setState(() {});
    _persistSoon();
  }

  @override
  void setMetronomeVolume(double v) {
    _song?.metronomeVolume = v;
    setState(() {});
    _persistSoon();
  }

  @override
  void setMetronomeRate(double rate) {
    _song?.metronomeRate = rate;
    _lastBeat = -1;
    setState(() {});
    _persistSoon();
  }

  @override
  void nudgeBeat(int deltaMs) {
    final song = _song;
    if (song == null) return;
    song.beatOffset = (song.beatOffset ?? 0) + deltaMs / 1000;
    _beatNudgeMs += deltaMs;
    _lastBeat = -1;
    setState(() {});
    _persistSoon();
  }

  @override
  void tapClick() {
    _live.preloadClick().then(
      (_) => _live.clickNow(accent: true, volume: metronomeVolume),
    );
  }

  /// Fires the click when playback crosses a beat of the song's own grid, so
  /// it stays aligned whatever the tempo is set to.
  void _clickTick() {
    final song = _song;
    if (song == null ||
        !song.metronomeOn ||
        _stage != _Stage.ready ||
        isVideo ||
        _countingIn)
      return;
    final bpm = song.originalBpm;
    if (bpm == null || bpm <= 0 || !_enginePlaying) return;
    final period = 60.0 / bpm / song.metronomeRate;
    final pos = _enginePosSec - (song.beatOffset ?? 0);
    if (pos < 0) return;
    final beat = (pos / period).floor();
    if (beat == _lastBeat) return;
    final late = pos - beat * period;
    final first = _lastBeat < 0;
    _lastBeat = beat;
    // Skip beats we only reached by seeking, or ones we're too late for.
    if (first || late > 0.06) return;
    final perBar = (4 * song.metronomeRate).round().clamp(1, 16);
    _live.clickNow(accent: beat % perBar == 0, volume: song.metronomeVolume);
  }

  // ---------------------------------------------------------------------
  // Progressive tempo training
  // ---------------------------------------------------------------------

  @override
  bool get training => _training;

  @override
  int get trainStartPct => _song?.trainStartPct ?? 70;

  @override
  int get trainStepPct => _song?.trainStepPct ?? 10;

  @override
  int get trainRepeats => _song?.trainRepeats ?? 2;

  @override
  int get trainCurrentPct => _trainPct;

  @override
  int get trainPass => _trainPassCount;

  @override
  bool get hasLoop => loopA != null && loopB != null;

  @override
  void setTrainStart(int pct) {
    _song?.trainStartPct = pct.clamp(50, 100);
    setState(() {});
    _persistSoon();
  }

  @override
  void setTrainStep(int pct) {
    _song?.trainStepPct = pct.clamp(5, 25);
    setState(() {});
    _persistSoon();
  }

  @override
  void setTrainRepeats(int n) {
    _song?.trainRepeats = n.clamp(1, 10);
    setState(() {});
    _persistSoon();
  }

  (double, double) get _trainRegion {
    final a = loopA, b = loopB;
    if (a != null && b != null) return (a, b);
    return (0, (durationSec - 0.2).clamp(1, double.infinity));
  }

  @override
  Future<void> startTraining() async {
    final song = _song;
    if (song == null || isVideo || _countingIn) return;
    _training = true;
    _trainPassCount = 0;
    _trainPct = song.trainStartPct;
    song.tempo = _trainPct / 100;
    _pitchTempoChanged();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted || !_training) return;
    _seekEngine(_trainRegion.$1);
    _lastPos = _trainRegion.$1;
    if (_enginePlaying) {
      setState(() {});
    } else {
      await _togglePlay();
    }
  }

  @override
  void stopTraining() {
    if (!_training) return;
    _training = false;
    _trainPassCount = 0;
    _pitchTempoChanged();
  }

  void _handleTraining(double pos) {
    final (a, b) = _trainRegion;
    if (_lastPos < b && pos >= b) {
      _trainPassCount++;
      if (_trainPassCount >= trainRepeats) {
        _trainPassCount = 0;
        final next = _trainPct + trainStepPct;
        if (next > 100) {
          // Finished: land on full speed and stop.
          _training = false;
          _song?.tempo = 1.0;
          _enginePause();
          _pitchTempoChanged();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Training complete — you reached full speed 🎉'),
              ),
            );
          return;
        }
        _trainPct = next;
        _song?.tempo = next / 100;
        _pitchTempoChanged();
      }
      setState(() {});
      _seekEngine(a);
    }
  }

  @override
  void seekTo(double seconds) {
    final limit = durationSec > 0 ? durationSec : seconds;
    final target = seconds.clamp(0, limit).toDouble();
    _loopPasses = 0;
    _seekEngine(target);
    _pos.value = target;
    _lastPos = target;
  }

  // ---------------------------------------------------------------------
  // StudioController: pitch / tempo / voice / loop / markers
  // ---------------------------------------------------------------------

  @override
  void selectNote(String note) {
    final song = _song;
    if (song == null) return;
    song.semitones =
        kNoteNames.indexOf(note) - kNoteNames.indexOf(_originalTonic);
    _pitchTempoChanged();
  }

  @override
  void setSemitones(int value) {
    _song?.semitones = value.clamp(-12, 12);
    _pitchTempoChanged();
  }

  @override
  void setCents(int value) {
    _song?.cents = value.clamp(-50, 50);
    _pitchTempoChanged();
  }

  @override
  void setTempo(double ratio) {
    _song?.tempo = ratio.clamp(0.5, 2.0);
    _pitchTempoChanged();
  }

  @override
  void setCountIn(int beats) {
    _song?.countInBeats = beats;
    setState(() {});
    _persistSoon();
  }

  @override
  void resetShift() {
    final song = _song;
    if (song == null) return;
    song
      ..semitones = 0
      ..cents = 0
      ..tempo = 1.0;
    _pitchTempoChanged();
  }

  void _pitchTempoChanged() {
    setState(() {});
    _persistSoon();
    if (isVideo || _song == null) return;
    if (_serverMode) {
      _scheduleServerRender();
    } else {
      _renderDebounce?.cancel();
      _activeClient?.close();
      _activeClient = null;
      if (_serverBusy) setState(() => _serverBusy = false);
      _switchToLocal();
    }
  }

  @override
  void setNaturalVoice(bool value) {
    final song = _song;
    if (song == null || song.isVideo || song.naturalVoice == value) return;
    song.naturalVoice = value;
    setState(() {});
    _persistSoon();
    if (value) {
      if (_serverMode) _scheduleServerRender(immediate: true);
    } else {
      _renderDebounce?.cancel();
      _activeClient?.close();
      _activeClient = null;
      setState(() => _serverBusy = false);
      _switchToLocal();
    }
  }

  /// Leaves the Natural Voice render (if it was active) and carries the
  /// playhead and play state over to the instant on-device engine.
  Future<void> _switchToLocal() async {
    final wasServer = _serverActive;
    final resume = _enginePosSec;
    final wasPlaying = _enginePlaying;
    if (wasServer) {
      await PlayerService.instance.pause();
      _serverEngine = false;
    }
    await _ensureLiveLoaded();
    if (wasServer) {
      _seekEngine(resume);
      if (wasPlaying) await _enginePlay();
    }
  }

  void _scheduleServerRender({bool immediate = false}) {
    _renderDebounce?.cancel();
    if (immediate) {
      _runServerPreview();
    } else {
      _renderDebounce = Timer(
        const Duration(milliseconds: 700),
        _runServerPreview,
      );
    }
  }

  /// Renders the current settings with Natural Voice on the server and
  /// swaps playback over to the result, keeping the playhead where it was.
  Future<void> _runServerPreview() async {
    final song = _song;
    if (song == null || song.isVideo) return;
    _cancelServerJob();
    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;
    final jobId = _jobId = SrugatiApi.newJobId();

    final resume = _enginePosSec;
    final wasPlaying = _enginePlaying;
    _enginePause();
    _cancelled = false;
    setState(() {
      _serverBusy = true;
      _busyLabel = 'Applying Natural Voice on the server…';
      _error = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/natural_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final saved = await SrugatiApi.shift(
        filePath: song.path,
        semitones: totalSemitones,
        tempo: tempo,
        label: currentNote,
        outputPath: outPath,
        preserveFormant: true,
        client: client,
        jobId: jobId,
      );
      if (!mounted || _activeClient != client) return;

      setState(() {
        _previewPath = saved;
        _serverBusy = false;
      });
      await PlayerService.instance.load(
        saved,
        '${song.name} · $currentKeyLabel',
      );
      _serverEngine = true;
      await PlayerService.instance.seek(
        Duration(milliseconds: (resume / tempo * 1000).round()),
      );
      if (wasPlaying) await PlayerService.instance.play();
    } catch (e) {
      if (!mounted || _activeClient != client) return;
      setState(() {
        _serverBusy = false;
        if (e is! http.ClientException) _error = '$e';
      });
    } finally {
      if (_activeClient == client) _activeClient = null;
    }
  }

  /// Cancels whatever server job is running (render, save or download).
  /// Closing the request makes the server stop its ffmpeg work too.
  void _cancelBusy() {
    _cancelled = true;
    _renderDebounce?.cancel();
    _cancelServerJob();
    _activeClient?.close();
    _activeClient = null;
    setState(() {
      _serverBusy = false;
      if (_stage == _Stage.shifting) _stage = _Stage.ready;
    });
  }

  @override
  void setLoop(double a, double b) {
    final song = _song;
    if (song == null) return;
    song
      ..loopA = a
      ..loopB = b;
    _loopPasses = 0;
    setState(() {});
    _persistSoon();
  }

  @override
  void clearLoop() {
    final song = _song;
    if (song == null) return;
    song
      ..loopA = null
      ..loopB = null;
    _loopPasses = 0;
    setState(() {});
    _persistSoon();
  }

  @override
  void setLoopRepeats(int repeats) {
    _song?.loopRepeats = repeats;
    _loopPasses = 0;
    setState(() {});
    _persistSoon();
  }

  @override
  void addMarker(String name) {
    final song = _song;
    if (song == null) return;
    song.markers = [...song.markers, SongMarker(name, _pos.value)]
      ..sort((a, b) => a.seconds.compareTo(b.seconds));
    setState(() {});
    _persistSoon();
  }

  @override
  void removeMarker(SongMarker marker) {
    final song = _song;
    if (song == null) return;
    song.markers = song.markers.where((m) => m != marker).toList();
    setState(() {});
    _persistSoon();
  }

  // ---------------------------------------------------------------------
  // Save / download
  // ---------------------------------------------------------------------

  String get _sourceExt => p.extension(_song!.path);

  String get _shiftedBaseName =>
      '${currentNote}_${_song!.name}${isVideo ? _sourceExt : '.m4a'}';

  Future<void> _applyShift() async {
    final song = _song;
    if (song == null) return;
    final client = http.Client();
    _activeClient = client;
    _cancelled = false;
    final jobId = _jobId = SrugatiApi.newJobId();
    setState(() {
      _stage = _Stage.shifting;
      _serverBusy = true;
      _busyLabel = isVideo
          ? 'Rendering the shifted video on the server…'
          : 'Rendering your version on the server…';
      _error = null;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final saved = await SrugatiApi.shift(
        filePath: song.path,
        semitones: totalSemitones,
        tempo: tempo,
        label: currentNote,
        preserveFormant: isVideo ? true : naturalVoice,
        outputPath: '${dir.path}/$_shiftedBaseName',
        client: client,
        jobId: jobId,
      );
      if (!mounted || _cancelled) return;
      setState(() {
        _shiftedPath = saved;
        _lastSavedSignature = _currentSaveSignature();
        _stage = _Stage.ready;
        _serverBusy = false;
      });
      libraryKey.currentState?.refresh();

      // Video's "Shift" tap only renders; its download sheet opens from the
      // relabelled "Save ... version" button. Audio opens it right away.
      if (mounted && !isVideo) await _openDownloadSheet();
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() {
        _serverBusy = false;
        _stage = _Stage.ready;
        if (e is! http.ClientException) _error = '$e';
      });
    } finally {
      if (_activeClient == client) _activeClient = null;
      client.close();
    }
  }

  Future<void> _openDownloadSheet() async {
    if (_shiftedPath == null || _downloading) return;
    final choice = await DownloadFormatSheet.show(context, isVideo: isVideo);
    if (choice == null || !mounted) return;
    await _performDownload(choice);
  }

  /// Re-renders on the server in the requested track/format, then hands the
  /// result to the native "Save As" dialog.
  Future<void> _performDownload(DownloadChoice choice) async {
    final song = _song;
    if (song == null) return;
    final client = http.Client();
    _activeClient = client;
    _cancelled = false;
    final jobId = _jobId = SrugatiApi.newJobId();
    setState(() {
      _downloading = true;
      _serverBusy = true;
      _busyLabel = 'Preparing your download on the server…';
    });
    try {
      final ext = choice.kind == DownloadKind.video
          ? (choice.format == 'auto' ? _sourceExt : '.${choice.format}')
          : '.${choice.format}';
      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/download_${DateTime.now().millisecondsSinceEpoch}$ext';

      final saved = await SrugatiApi.shift(
        filePath: song.path,
        semitones: totalSemitones,
        tempo: tempo,
        label: currentNote,
        outputPath: outPath,
        preserveFormant: isVideo ? true : naturalVoice,
        want: choice.kind == DownloadKind.video ? 'video' : 'audio',
        outputFormat: choice.format,
        client: client,
        jobId: jobId,
      );
      if (!mounted || _cancelled) return;
      setState(() => _serverBusy = false);

      await FileSaver.instance.saveAs(
        name: '${currentNote}_${song.name}',
        filePath: saved,
        fileExtension: ext.substring(1),
        mimeType: MimeType.other,
      );
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() {
        _serverBusy = false;
        if (e is! http.ClientException) _error = '$e';
      });
    } finally {
      if (_activeClient == client) _activeClient = null;
      client.close();
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: _stage == _Stage.idle
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: handleBack,
              ),
        title: const Text('Studio'),
        actions: [
          IconButton(
            tooltip: 'Theme',
            icon: Icon(Icons.palette_outlined, color: AppColors.purple),
            onPressed: () => ThemePickerSheet.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_stage == _Stage.idle) AddSongPanel(onPick: importFrom),
              if (_stage == _Stage.analyzing) _buildAnalyzing(),
              if ((_stage == _Stage.ready || _stage == _Stage.shifting) &&
                  _song != null)
                _buildResults(),
              if (_error != null) _buildError(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyzing() {
    Widget row(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              strokeWidth: 6,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Analyzing song…',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          row('Key / Pitch'),
          row('BPM (tempo)'),
          row('Waveform'),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: _cancelImport, child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final content = _buildReady();
    if (!_serverBusy) return content;
    return Stack(
      children: [
        IgnorePointer(child: content),
        Positioned.fill(
          child: Container(
            color: AppColors.background.withValues(alpha: 0.88),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.purple),
                  const SizedBox(height: 16),
                  Text(
                    _busyLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _cancelBusy,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReady() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        const SizedBox(height: 14),
        _buildSummaryCard(),
        const SizedBox(height: 14),
        if (isVideo) ...[_buildVideoPlayRow(), const SizedBox(height: 14)],
        _buildWaveformCard(),
        const SizedBox(height: 14),
        if (_training) ...[_buildTrainingBanner(), const SizedBox(height: 14)],
        if (!isVideo) ...[_buildTakeBar(), const SizedBox(height: 14)],
        _buildQuickActions(),
        const SizedBox(height: 18),
        _buildSaveButton(),
        const SizedBox(height: 6),
        Text(
          _saveCaption,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildTakeBar() {
    if (!_taking) {
      return OutlinedButton.icon(
        onPressed: _startTake,
        icon: const Icon(Icons.mic_rounded),
        label: const Text(
          'Sing along & record',
          style: TextStyle(fontSize: 16),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.18),
        border: Border.all(color: Colors.redAccent),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.fiber_manual_record_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Recording your vocal',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          TextButton(onPressed: _finishTake, child: const Text('Stop & save')),
        ],
      ),
    );
  }

  Widget _buildTrainingBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Training · $_trainPct% · pass ${_trainPassCount + 1}/$trainRepeats',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: stopTraining,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  String get _metaLine {
    final parts = <String>[if (analysed) originalKey];
    final bpm = _song?.originalBpm;
    if (bpm != null) parts.add('${bpm.round()} BPM');
    if (durationSec > 0) parts.add(formatSeconds(durationSec));
    return parts.join(' • ');
  }

  Widget _buildHeader() {
    final song = _song!;
    return Row(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            song.isVideo ? Icons.movie_rounded : Icons.music_note_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _metaLine,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _openMore,
          icon: const Icon(
            Icons.more_vert_rounded,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final centsLabel = cents == 0 ? '' : ' ${cents > 0 ? '+' : ''}$cents¢';

    Widget block(String label, String value, {bool accent = false}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: accent ? AppColors.purple : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _openKeyTempo,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  block('Original Key', originalKey),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  block(
                    'Current Key',
                    '$currentKeyLabel$centsLabel',
                    accent: true,
                  ),
                ],
              ),
              Divider(height: 22, color: AppColors.surfaceMuted),
              Row(
                children: [
                  block('Pitch', _pitchSummary),
                  block(
                    'Tempo',
                    _song?.originalBpm == null
                        ? '${(tempo * 100).round()}%'
                        : '${currentBpm.round()} BPM',
                  ),
                  if (_hasShift)
                    TextButton(
                      onPressed: resetShift,
                      child: const Text(
                        'Reset',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skip15({required bool forward}) {
    return IconButton(
      onPressed: () => seekTo(_pos.value + (forward ? 15 : -15)),
      iconSize: 34,
      icon: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            forward ? Icons.rotate_right_rounded : Icons.rotate_left_rounded,
            color: AppColors.textPrimary,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Text(
              '15',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          WaveformView(
            peaks: peaks,
            durationSec: durationSec,
            positionSec: _pos,
            spectrum: _live.spectrum,
            loopA: loopA,
            loopB: loopB,
            markers: markers,
            onSeek: isVideo ? null : seekTo,
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<double>(
            valueListenable: _pos,
            builder: (_, pos, __) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isVideo ? '' : formatSeconds(pos),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_countingIn)
                  Text(
                    'Count-in…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.purple,
                    ),
                  ),
                Text(
                  formatSeconds(durationSec),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!isVideo) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _skip15(forward: false),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _wasPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                _skip15(forward: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickAction(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool active = false,
  }) {
    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: active ? AppColors.purpleDeep : AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: active ? Border.all(color: AppColors.purple) : null,
                ),
                child: Icon(
                  icon,
                  color: active ? Colors.white : AppColors.purple,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        _quickAction(
          Icons.repeat_rounded,
          'Loop',
          isVideo ? null : _openLoop,
          active: loopA != null,
        ),
        _quickAction(
          Icons.tune_rounded,
          'Key & Tempo',
          _openKeyTempo,
          active: _hasShift,
        ),
        _quickAction(
          Icons.record_voice_over_rounded,
          'Voice',
          _openNaturalVoice,
          active: naturalVoice || isVideo,
        ),
        _quickAction(
          Icons.timer_outlined,
          'Metronome',
          isVideo ? null : _openMetronome,
          active: metronomeOn || _training,
        ),
        _quickAction(Icons.more_horiz_rounded, 'More', _openMore),
      ],
    );
  }

  void _openKeyTempo() => StudioSheet.show(
    context,
    title: 'Key & Tempo',
    controller: this,
    bodyBuilder: (_) => KeyTempoBody(c: this),
  );

  void _openNaturalVoice() => StudioSheet.show(
    context,
    title: 'Natural Voice',
    controller: this,
    bodyBuilder: (_) => NaturalVoiceBody(c: this),
  );

  void _openMetronome() => StudioSheet.show(
    context,
    title: 'Metronome & Training',
    controller: this,
    bodyBuilder: (_) => MetronomeBody(c: this),
  );

  void _openLoop() => StudioSheet.show(
    context,
    title: 'Loop & Markers',
    controller: this,
    bodyBuilder: (_) => LoopMarkersBody(c: this),
  );

  void _openMore() {
    final song = _song;
    if (song == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  song.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: AppColors.purple,
                ),
                title: Text(
                  song.favorite ? 'Remove from favorites' : 'Add to favorites',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  song.favorite = !song.favorite;
                  setState(() {});
                  _flushPersist();
                },
              ),
              if (!analysed)
                ListTile(
                  leading: Icon(
                    Icons.graphic_eq_rounded,
                    color: AppColors.purple,
                  ),
                  title: const Text('Detect key & tempo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _analyse(song, removeOnFail: false);
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.purple,
                ),
                title: const Text('Remove vocals (stems)'),
                onTap: () {
                  Navigator.pop(ctx);
                  homeTab.value = 3;
                  removerKey.currentState?.startWithPath(song.path, song.name);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.restart_alt_rounded,
                  color: AppColors.purple,
                ),
                title: const Text('Reset key & tempo'),
                onTap: () {
                  Navigator.pop(ctx);
                  resetShift();
                },
              ),
              ListTile(
                leading: Icon(Icons.close_rounded, color: AppColors.purple),
                title: const Text('Close song'),
                onTap: () {
                  Navigator.pop(ctx);
                  _closeSong();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    final busy = _stage == _Stage.shifting;
    if (isVideo) {
      return GradientButton(
        label: busy
            ? 'Shifting…'
            : (_needsSave ? 'Shift pitch/tempo' : 'Save $currentNote version'),
        icon: _needsSave ? Icons.tune_rounded : Icons.save_rounded,
        onPressed: !_hasShift || busy
            ? null
            : (_needsSave ? _applyShift : _openDownloadSheet),
      );
    }
    final label = semitones == 0 && cents == 0
        ? 'Save original version'
        : 'Save $currentNote version';
    return GradientButton(
      label: busy ? 'Saving…' : label,
      icon: Icons.save_rounded,
      onPressed: busy ? null : (_needsSave ? _applyShift : _openDownloadSheet),
    );
  }

  String get _saveCaption {
    if (!_needsSave) return 'Already saved to your Library — tap to download.';
    if (isVideo) {
      return _hasShift
          ? 'Renders the shifted audio back into the video and adds it to your Library.'
          : 'Change the key or tempo to shift this video.';
    }
    return 'Renders a file at these settings and adds it to your Library.';
  }

  /// Video's equivalent of the audio transport: tapping opens the dedicated
  /// video player for whichever file matches the current settings.
  Widget _buildVideoPlayRow() {
    final song = _song!;
    final shifted = _showingShiftedVideo && _shiftedPath != null;
    final path = shifted ? _shiftedPath! : song.path;
    final label = shifted
        ? '$currentNote (${semitones > 0 ? '+' : ''}$semitones) · ${song.name}'
        : 'Original · ${song.name}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: path)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
    );
  }
}
