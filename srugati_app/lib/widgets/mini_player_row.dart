import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/player_service.dart';
import '../theme/app_theme.dart';
import 'player_modal.dart';

/// A compact "song name + play button" row.
///
/// The play/pause icon only toggles playback on the single app-wide
/// [PlayerService] (loading this track first if nothing is loaded yet — but
/// never autoplaying just because a file was picked or shifted). The
/// trailing chevron is the only thing that opens the full player modal, and
/// it loads the track (paused) if needed rather than starting playback.
class MiniPlayerRow extends StatelessWidget {
  final String path;
  final String title;
  final VoidCallback? onDownload;
  final bool downloading;

  const MiniPlayerRow({
    super.key,
    required this.path,
    required this.title,
    this.onDownload,
    this.downloading = false,
  });

  void _togglePlayPause() {
    final service = PlayerService.instance;
    if (!service.isLoaded(path)) {
      service.load(path, title, autoPlay: true);
    } else if (service.player.playing) {
      service.pause();
    } else {
      service.play();
    }
  }

  void _openModal(BuildContext context) {
    final service = PlayerService.instance;
    if (!service.isLoaded(path)) {
      service.load(path, title);
    }
    PlayerModal.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final service = PlayerService.instance;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _togglePlayPause,
              child: AnimatedBuilder(
                animation: service,
                builder: (context, _) {
                  final isThis = service.isLoaded(path);
                  return StreamBuilder<PlayerState>(
                    stream: service.playerStateStream,
                    builder: (context, snapshot) {
                      final playing =
                          isThis && (snapshot.data?.playing ?? false);
                      return Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (onDownload != null)
              SizedBox(
                width: 36,
                height: 36,
                child: downloading
                    ? Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.purple,
                        ),
                      )
                    : InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: onDownload,
                        child: const Icon(
                          Icons.file_download_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openModal(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
