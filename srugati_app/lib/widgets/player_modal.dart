import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

/// The one full-featured player UI for the app, shown as a modal sheet.
/// Bound entirely to [PlayerService.instance], so if the loaded track
/// changes (e.g. a fresh pitch/tempo shift lands) while this is open, it
/// updates in place instead of a second player appearing.
class PlayerModal extends StatefulWidget {
  const PlayerModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const PlayerModal(),
    );
  }

  @override
  State<PlayerModal> createState() => _PlayerModalState();
}

class _PlayerModalState extends State<PlayerModal> {
  final _service = PlayerService.instance;
  late double _volume = _service.player.volume;

  String _fmt(Duration? d) {
    if (d == null) return '0:00';
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Text(
                        _service.currentTitle,
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
                StreamBuilder<Duration>(
                  stream: _service.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final total = _service.duration ?? Duration.zero;
                    final totalMs = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
                    return Column(
                      children: [
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
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 34,
                      onPressed: () => _service.seekBy(const Duration(seconds: -10)),
                      icon: const Icon(Icons.replay_10_rounded, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 16),
                    StreamBuilder<PlayerState>(
                      stream: _service.playerStateStream,
                      builder: (context, snapshot) {
                        final playing = snapshot.data?.playing ?? false;
                        return InkWell(
                          borderRadius: BorderRadius.circular(36),
                          onTap: () => playing ? _service.pause() : _service.play(),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                            child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      iconSize: 34,
                      onPressed: () => _service.seekBy(const Duration(seconds: 10)),
                      icon: const Icon(Icons.forward_10_rounded, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      _volume == 0
                          ? Icons.volume_off_rounded
                          : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        ),
                        child: Slider(
                          value: _volume,
                          activeColor: AppColors.teal,
                          inactiveColor: AppColors.surfaceMuted,
                          onChanged: (v) {
                            setState(() => _volume = v);
                            _service.setVolume(v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
