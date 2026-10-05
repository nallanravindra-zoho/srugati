import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../theme/app_theme.dart';

/// Records from the microphone until stopped; pops with the file path
/// (or null if cancelled / no permission).
class RecordDialog extends StatefulWidget {
  const RecordDialog({super.key});

  static Future<String?> show(BuildContext context) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const RecordDialog(),
  );

  @override
  State<RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<RecordDialog> {
  final _recorder = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'Microphone permission is required to record.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  Future<void> _stop({required bool keep}) async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    Navigator.of(context).pop(keep ? path : null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_seconds ~/ 60).toString();
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    return AlertDialog(
      title: const Text('Recording'),
      content: _error != null
          ? Text(_error!)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_rounded, size: 46, color: AppColors.purple),
                const SizedBox(height: 10),
                Text(
                  '$mm:$ss',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () =>
              _error != null ? Navigator.of(context).pop() : _stop(keep: false),
          child: const Text('Cancel'),
        ),
        if (_error == null)
          FilledButton(
            onPressed: () => _stop(keep: true),
            child: const Text('Stop & use'),
          ),
      ],
    );
  }
}
