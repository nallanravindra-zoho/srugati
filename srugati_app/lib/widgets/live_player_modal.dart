import 'package:flutter/material.dart';
import '../services/live_pitch_service.dart';
import '../theme/app_theme.dart';

/// Full player UI for the local live-preview engine — same shape as
/// [PlayerModal] (title, scrub bar with time, play/pause, ±10s) but bound to
/// [LivePitchService] instead of the single shared just_audio player, since
/// live preview runs on a different engine (SoLoud) with its own transport.
class LivePlayerModal extends StatefulWidget {
  final String title;
  const LivePlayerModal({super.key, required this.title});

  static Future<void> show(BuildContext context, {required String title}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => LivePlayerModal(title: title),
    );
  }

  @override
  State<LivePlayerModal> createState() => _LivePlayerModalState();
}

class _LivePlayerModalState extends State<LivePlayerModal> {
  final _service = LivePitchService.instance;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: AnimatedBuilder(
          animation: _service,
          builder: (context, _) {
            final position = _service.position;
            final total = _service.length;
            final totalMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: position.inMilliseconds.clamp(0, totalMs.toInt()).toDouble(),
                    max: totalMs,
                    activeColor: AppColors.purple,
                    inactiveColor: AppColors.surfaceMuted,
                    onChanged: (v) => _service.seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text(_fmt(total), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 34,
                      onPressed: () {
                        final target = position - const Duration(seconds: 10);
                        _service.seek(target < Duration.zero ? Duration.zero : target);
                      },
                      icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(36),
                      onTap: _service.togglePlay,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                        child: Icon(_service.playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      iconSize: 34,
                      onPressed: () {
                        final target = position + const Duration(seconds: 10);
                        _service.seek(target > total ? total : target);
                      },
                      icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pitch and tempo follow the sliders on Studio while this is open.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
