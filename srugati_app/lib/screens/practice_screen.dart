import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../services/srugati_api.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import '../widgets/note_dial.dart';

/// A simple live-mic tuner: repeatedly records a short clip and sends it to
/// the same pitch-detection endpoint the Studio screen uses, refreshing the
/// note dial each cycle. Not continuous streaming pitch-tracking — that's a
/// bigger feature than the original ask.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _recorder = AudioRecorder();
  bool _listening = false;
  PitchResult? _result;
  String? _error;
  int _cycle = 0;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      setState(() => _listening = false);
      return;
    }

    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission is required.');
      return;
    }

    setState(() {
      _listening = true;
      _error = null;
    });
    _runCycle();
  }

  Future<void> _runCycle() async {
    if (!_listening) return;
    _cycle++;
    final cycleId = _cycle;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/practice_clip.wav';
      await _recorder.start(const RecordConfig(), path: path);
      await Future.delayed(const Duration(seconds: 3));
      final recordedPath = await _recorder.stop();

      if (!_listening || cycleId != _cycle) return;
      if (recordedPath != null) {
        final result = await SrugatiApi.detectPitch(recordedPath);
        if (mounted && _listening) setState(() => _result = result);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Practice error: $e');
    }

    if (_listening) _runCycle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoteDial(
                note: _result?.note,
                octave: _result?.octave,
                frequencyHz: _result?.frequencyHz,
                confidence: _result?.confidence ?? 0,
                size: 240,
              ),
              const SizedBox(height: 12),
              Text(
                _listening ? 'Listening…' : 'Sing or play a note',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 32),
              GradientButton(
                label: _listening ? 'Stop' : 'Start listening',
                icon: _listening ? Icons.stop_rounded : Icons.mic_rounded,
                onPressed: _toggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
