import 'package:flutter/material.dart';

import '../services/live_pitch_service.dart';
import '../theme/app_theme.dart';
import 'live_player_modal.dart';

/// "Song name + play button" row backed by [LivePitchService] — unlike
/// [MiniPlayerRow] (which plays a static rendered file), this one plays the
/// original file live through the SoLoud engine, so the semitone/tempo
/// controls below it change the sound instantly while it plays. The
/// trailing chevron opens a full player (scrub bar, ±10s) the same way
/// MiniPlayerRow's does, so live playback isn't limited to a bare play button.
class LivePlayerRow extends StatelessWidget {
  final String title;

  const LivePlayerRow({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final service = LivePitchService.instance;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: service.togglePlay,
              child: AnimatedBuilder(
                animation: service,
                builder: (context, _) => Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    service.playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
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
            AnimatedBuilder(
              animation: service,
              builder: (context, _) => AnimatedOpacity(
                opacity: service.playing ? 1 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.teal,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => LivePlayerModal.show(context, title: title),
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
