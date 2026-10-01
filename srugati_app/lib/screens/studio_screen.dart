import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/live_pitch_service.dart';
import '../services/player_service.dart';
import '../services/srugati_api.dart';
import '../theme/app_theme.dart';
import '../widgets/centered_slider.dart';
import '../widgets/download_format_sheet.dart';
import '../widgets/gradient_button.dart';
import '../widgets/live_player_row.dart';
import '../widgets/mini_player_row.dart';
import '../widgets/note_chip_row.dart';
import 'home_shell.dart';
import 'video_player_screen.dart';

enum _TempoUnit { percent, bpm }

const _videoExtensions = {'mp4', 'mov', 'mkv', 'webm', 'avi'};
const _acceptedExtensions = [
  'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg',
  'mp4', 'mov', 'mkv', 'webm', 'avi',
];

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

enum _Stage { idle, analyzing, ready, shifting }

class _StudioScreenState extends State<StudioScreen> {
  _Stage _stage = _Stage.idle;
  String? _filePath;
  String? _fileName;
  PitchResult? _detected;
  String? _error;

  String _targetNote = 'C';
  int _semitones = 0;
  double _tempo = 1.0;
  String? _shiftedPath;
  String? _appliedLabel;

  bool _preserveFormants = false;
  bool _serverBusy = false;
  bool _downloading = false;
  http.Client? _activeClient;
  String? _lastSavedSignature;

  _TempoUnit _tempoUnit = _TempoUnit.percent;
  final _bpmController = TextEditingController(text: '120');
  double get _originalBpm => double.tryParse(_bpmController.text) ?? 120;

  bool get _isVideo =>
      _fileName != null && _videoExtensions.contains(_fileName!.split('.').last.toLowerCase());

  /// True only once there's an actual pitch shift to preserve — a formant
  /// toggle with no shift (still at the detected note) has nothing to send
  /// to the server, so it stays on the free instant local player.
  bool get _usingServerRender => _preserveFormants && _semitones != 0;

  bool get _hasShift => _semitones != 0 || (_tempo - 1.0).abs() > 1e-6;

  String _currentSaveSignature() =>
      '$_semitones|${_tempo.toStringAsFixed(3)}|${_isVideo ? true : _preserveFormants}';

  /// False once "Save"/"Shift" has already produced a Library file for
  /// exactly these settings — tapping it again then just re-opens the
  /// download sheet instead of rendering (and saving) the same thing twice.
  bool get _needsSave => _lastSavedSignature != _currentSaveSignature();

  /// True once the current sliders exactly match a shift that's already
  /// been rendered — i.e. there's a real shifted video file to play. Video
  /// has no live local preview, so unlike audio's LIVE row this can only
  /// ever reflect the last successful render, never an in-progress drag.
  bool get _showingShiftedVideo => _hasShift && !_needsSave;

  String get _videoRowLabel => _showingShiftedVideo
      ? '$_targetNote (${_semitones > 0 ? '+' : ''}$_semitones) · $_fileName'
      : 'Original · $_fileName';

  String get _videoRowPath => _showingShiftedVideo ? _shiftedPath! : _filePath!;

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _acceptedExtensions,
    );
    if (picked == null || picked.path == null) return;

    final path = picked.path!;
    final name = picked.name;

    setState(() {
      _filePath = path;
      _fileName = name;
      _detected = null;
      _shiftedPath = null;
      _error = null;
      _stage = _Stage.analyzing;
    });

    try {
      final result = await SrugatiApi.detectPitch(path);
      setState(() {
        _detected = result;
        _targetNote = result.note ?? 'C';
        _semitones = 0;
        _tempo = 1.0;
        _tempoUnit = _TempoUnit.percent;
        _bpmController.text = '120';
        _lastSavedSignature = null;
        _stage = _Stage.ready;
      });
      if (!_isVideo) {
        LivePitchService.instance.load(path);
      }
    } catch (e) {
      setState(() {
        _error = '$e';
        _stage = _Stage.idle;
      });
    }
  }

  void _onNoteChipSelected(String note) {
    final original = _detected?.note ?? 'C';
    final shift = kNoteNames.indexOf(note) - kNoteNames.indexOf(original);
    setState(() {
      _targetNote = note;
      _semitones = shift;
    });
    _afterPitchChange();
  }

  void _onSemitoneChanged(double value) {
    final original = _detected?.note ?? 'C';
    final shift = value.round();
    setState(() {
      _semitones = shift;
      _targetNote = kNoteNames[(kNoteNames.indexOf(original) + shift + 120) % 12];
    });
    if (!_preserveFormants) {
      LivePitchService.instance.setSemitones(shift.toDouble());
    }
  }

  /// Called after a note chip tap or a semitone drag ends. Only talks to the
  /// server when formants are being preserved *and* there's an actual shift
  /// to preserve — landing back on the original note drops straight back to
  /// the free instant local player instead of rendering a no-op shift.
  void _afterPitchChange() {
    if (_isVideo || !_preserveFormants) {
      if (!_isVideo && !_preserveFormants) {
        LivePitchService.instance.setSemitones(_semitones.toDouble());
      }
      return;
    }
    if (_semitones != 0) {
      _runServerPreview();
    } else {
      _switchToLocalPlayback();
    }
  }

  void _switchToLocalPlayback() {
    _activeClient?.close();
    _activeClient = null;
    setState(() => _serverBusy = false);
    if (!_isVideo && _filePath != null) {
      LivePitchService.instance.load(_filePath!);
      LivePitchService.instance.setTempo(_tempo);
    }
  }

  void _onFormantToggleChanged(bool value) {
    setState(() => _preserveFormants = value);
    if (value) {
      if (_semitones != 0) {
        LivePitchService.instance.stop();
        _runServerPreview();
      }
    } else {
      _activeClient?.close();
      setState(() => _serverBusy = false);
      if (!_isVideo && _filePath != null) {
        LivePitchService.instance.load(_filePath!);
        LivePitchService.instance.setTempo(_tempo);
        LivePitchService.instance.setSemitones(_semitones.toDouble());
      }
    }
  }

  /// Renders the current note/tempo settings on the server (real Rubber Band
  /// formant preservation — much better on full mixes than the free local
  /// engine) and plays the result through the single shared [PlayerService].
  /// While this is in flight the results panel shows a blocking overlay,
  /// since — unlike the local engine — there's nothing to preview until the
  /// render comes back.
  Future<void> _runServerPreview() async {
    if (_filePath == null || _isVideo) return;
    _activeClient?.close();
    final client = http.Client();
    _activeClient = client;
    setState(() {
      _serverBusy = true;
      _error = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/formant_preview_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final saved = await SrugatiApi.shift(
        filePath: _filePath!,
        semitones: _semitones.toDouble(),
        tempo: _tempo,
        label: _targetNote,
        outputPath: outPath,
        preserveFormant: true,
        client: client,
      );
      if (!mounted || _activeClient != client) return;

      final label = '$_targetNote · ${(_tempo * 100).round()}% · formant preserved';
      setState(() {
        _shiftedPath = saved;
        _appliedLabel = label;
        _serverBusy = false;
      });
      await PlayerService.instance.load(saved, label, autoPlay: true);
    } catch (e) {
      if (!mounted || _activeClient != client) return;
      setState(() {
        _serverBusy = false;
        if (e is! http.ClientException) {
          _error = '$e';
        }
      });
    } finally {
      if (_activeClient == client) _activeClient = null;
    }
  }

  void _cancelServerPreview() {
    _activeClient?.close();
    _activeClient = null;
    setState(() => _serverBusy = false);
  }

  String get _shiftedBaseName {
    final base = _fileName!.contains('.')
        ? _fileName!.substring(0, _fileName!.lastIndexOf('.'))
        : _fileName!;
    final ext = _isVideo ? '.${_fileName!.split('.').last}' : '.m4a';
    return '${_targetNote}_$base$ext';
  }

  Future<void> _applyShift() async {
    if (_filePath == null || _fileName == null) return;
    setState(() {
      _stage = _Stage.shifting;
      _error = null;
    });

    final preserveFormant = _isVideo ? true : _preserveFormants;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/$_shiftedBaseName';

      final saved = await SrugatiApi.shift(
        filePath: _filePath!,
        semitones: _semitones.toDouble(),
        tempo: _tempo,
        label: _targetNote,
        preserveFormant: preserveFormant,
        outputPath: outPath,
      );

      final label = preserveFormant
          ? '$_targetNote · ${(_tempo * 100).round()}% · formant preserved'
          : '$_targetNote · ${(_tempo * 100).round()}%';
      setState(() {
        _shiftedPath = saved;
        _appliedLabel = label;
        _lastSavedSignature = _currentSaveSignature();
        _stage = _Stage.ready;
      });
      libraryKey.currentState?.refresh();

      // Video's "Shift pitch/tempo" tap only renders — download options are
      // shown only when the (now relabelled) "Save ... version" button is
      // tapped explicitly. Audio keeps opening the sheet right away.
      if (mounted && !_isVideo) await _openDownloadSheet();
    } catch (e) {
      setState(() {
        _error = '$e';
        _stage = _Stage.ready;
      });
    }
  }

  Future<void> _openDownloadSheet() async {
    if (_shiftedPath == null || _downloading) return;
    final choice = await DownloadFormatSheet.show(context, isVideo: _isVideo);
    if (choice == null || !mounted) return;
    await _performDownload(choice);
  }

  /// Re-renders on the server in the requested track/format (a fresh call,
  /// since the already-saved result may be a different combination — e.g.
  /// the current save is a video but the user wants just the MP3 audio),
  /// then hands the result to the native "Save As" dialog.
  Future<void> _performDownload(DownloadChoice choice) async {
    setState(() => _downloading = true);
    try {
      final ext = choice.kind == DownloadKind.video
          ? (choice.format == 'auto' ? '.${_fileName!.split('.').last}' : '.${choice.format}')
          : '.${choice.format}';
      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/download_${DateTime.now().millisecondsSinceEpoch}$ext';

      final saved = await SrugatiApi.shift(
        filePath: _filePath!,
        semitones: _semitones.toDouble(),
        tempo: _tempo,
        label: _targetNote,
        outputPath: outPath,
        preserveFormant: _isVideo ? true : _preserveFormants,
        want: choice.kind == DownloadKind.video ? 'video' : 'audio',
        outputFormat: choice.format,
      );

      final base = _fileName!.contains('.')
          ? _fileName!.substring(0, _fileName!.lastIndexOf('.'))
          : _fileName!;
      await FileSaver.instance.saveAs(
        name: '${_targetNote}_$base',
        filePath: saved,
        fileExtension: ext.substring(1),
        mimeType: MimeType.other,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _reset() {
    LivePitchService.instance.stop();
    _activeClient?.close();
    _activeClient = null;
    setState(() {
      _stage = _Stage.idle;
      _filePath = null;
      _fileName = null;
      _detected = null;
      _shiftedPath = null;
      _appliedLabel = null;
      _preserveFormants = false;
      _serverBusy = false;
      _lastSavedSignature = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    LivePitchService.instance.stop();
    _activeClient?.close();
    _bpmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Studio')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_stage == _Stage.idle) _buildUploadCard(),
              if (_stage == _Stage.analyzing) _buildAnalyzing(),
              if (_stage == _Stage.ready || _stage == _Stage.shifting) _buildResults(),
              if (_error != null) _buildError(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: AppColors.purple.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
              child: const Icon(Icons.upload_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 20),
            const Text(
              'Upload a track',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'Audio or video — any common format',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzing() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: const [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 6, valueColor: AlwaysStoppedAnimation(AppColors.purple)),
          ),
          SizedBox(height: 20),
          Text('Listening for the pitch…', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final content = _buildResultsContent();
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
                  const CircularProgressIndicator(color: AppColors.purple),
                  const SizedBox(height: 16),
                  const Text(
                    'Preserving formants on the server…',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _cancelServerPreview,
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

  /// Compact "detected pitch" banner — a highlighted gradient strip with the
  /// note and frequency, replacing a big circular dial so every control
  /// below fits on screen with as little scrolling as possible.
  Widget _buildDetectedBanner(PitchResult detected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.teal, width: 1.4),
            ),
            child: Center(
              child: Text(
                detected.note ?? '—',
                style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DETECTED PITCH',
                  style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                ),
                Text(
                  detected.frequencyHz != null ? '${detected.frequencyHz!.toStringAsFixed(1)} Hz' : '—',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (detected.confidence > 0)
            Text(
              '${(detected.confidence * 100).round()}% confident',
              style: const TextStyle(color: AppColors.teal, fontSize: 11),
            ),
        ],
      ),
    );
  }

  String get _tempoLabel => _tempoUnit == _TempoUnit.percent
      ? '${(_tempo * 100).round()}%'
      : '${(_tempo * _originalBpm).round()} BPM';

  Widget _buildTempoUnitToggle() {
    Widget chip(String label, _TempoUnit unit) {
      final selected = _tempoUnit == unit;
      return GestureDetector(
        onTap: () => setState(() => _tempoUnit = unit),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [chip('%', _TempoUnit.percent), const SizedBox(width: 6), chip('BPM', _TempoUnit.bpm)],
    );
  }

  Widget _buildResultsContent() {
    final detected = _detected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _fileName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(onPressed: _reset, icon: const Icon(Icons.close), visualDensity: VisualDensity.compact),
          ],
        ),
        const SizedBox(height: 8),
        _buildDetectedBanner(detected),
        const SizedBox(height: 14),
        if (_isVideo) ...[
          _buildVideoPlayRow(),
        ] else if (_usingServerRender)
          MiniPlayerRow(
            key: ValueKey('server:${_shiftedPath ?? _filePath}'),
            path: _shiftedPath ?? _filePath!,
            title: _shiftedPath != null ? _appliedLabel! : '$_targetNote · $_fileName',
            onDownload: _shiftedPath != null ? _openDownloadSheet : null,
            downloading: _downloading,
          )
        else
          LivePlayerRow(
            key: ValueKey('live:$_filePath'),
            title: _semitones == 0
                ? 'Original · $_fileName'
                : '$_targetNote (${_semitones > 0 ? '+' : ''}$_semitones) · $_fileName',
          ),
        if (!_isVideo) ...[
          const SizedBox(height: 4),
          Text(
            _usingServerRender
                ? 'Server-rendered with formants preserved.'
                : 'Play, then move the controls below — pitch and tempo change instantly.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _preserveFormants,
            onChanged: _serverBusy ? null : _onFormantToggleChanged,
            activeThumbColor: AppColors.teal,
            title: const Text('Preserve formants', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: const Text(
              'On = server render for natural voice. Off = instant local preview.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: 6),
        const Text('Shift to', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        NoteChipRow(selected: _targetNote, onSelect: _onNoteChipSelected),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Semitones', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              _semitones == 0 ? '0' : (_semitones > 0 ? '+$_semitones' : '$_semitones'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.purple),
            ),
          ],
        ),
        CenteredSlider(
          value: _semitones.toDouble(),
          min: -12,
          max: 12,
          onChanged: (v) => _onSemitoneChanged(v.roundToDouble()),
          onChangeEnd: (_) => _afterPitchChange(),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('-12', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text('0', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text('+12', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Tempo (independent of pitch)', style: TextStyle(fontWeight: FontWeight.w700)),
            _buildTempoUnitToggle(),
          ],
        ),
        if (_tempoUnit == _TempoUnit.bpm) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Original tempo', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                height: 30,
                child: TextField(
                  controller: _bpmController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),
              const Text('BPM', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ),
        ],
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _tempo,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                label: _tempoLabel,
                onChanged: (v) {
                  final tempo = double.parse(v.toStringAsFixed(2));
                  setState(() => _tempo = tempo);
                  if (!_preserveFormants) {
                    LivePitchService.instance.setTempo(tempo);
                  }
                },
                onChangeEnd: (_) {
                  if (_usingServerRender) _runServerPreview();
                },
              ),
            ),
            SizedBox(width: 64, child: Text(_tempoLabel, textAlign: TextAlign.right)),
          ],
        ),
        const SizedBox(height: 12),
        _buildSaveButton(),
        const SizedBox(height: 4),
        Text(_saveCaption, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildSaveButton() {
    final busy = _stage == _Stage.shifting;
    if (_isVideo) {
      return GradientButton(
        label: busy ? 'Shifting…' : (_needsSave ? 'Shift pitch/tempo' : 'Save $_targetNote version'),
        icon: _needsSave ? Icons.tune_rounded : Icons.save_rounded,
        onPressed: !_hasShift || busy ? null : (_needsSave ? _applyShift : _openDownloadSheet),
      );
    }
    final label = _semitones == 0 ? 'Save original version' : 'Save $_targetNote version';
    return GradientButton(
      label: busy ? 'Saving…' : label,
      icon: Icons.save_rounded,
      onPressed: busy ? null : (_needsSave ? _applyShift : _openDownloadSheet),
    );
  }

  String get _saveCaption {
    if (!_needsSave) return 'Already saved to your Library — tap to download.';
    if (_isVideo) {
      return _hasShift
          ? 'Renders the shifted audio back into the video and adds it to your Library.'
          : 'Move a slider or pick a note above to shift this video.';
    }
    return 'Renders a file at these settings and adds it to your Library.';
  }

  /// Video's equivalent of the audio rows (LivePlayerRow / MiniPlayerRow):
  /// same look, but tapping opens the dedicated video player for whichever
  /// file matches the current sliders — original or last-rendered shift.
  Widget _buildVideoPlayRow() {
    final path = _videoRowPath;
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
                decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _videoRowLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
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
