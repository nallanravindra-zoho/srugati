import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum DownloadKind { audio, video }

/// What the user picked in [DownloadFormatSheet]: which track to export and
/// which format to encode it as ("auto" for video = same container as the
/// upload).
class DownloadChoice {
  final DownloadKind kind;
  final String format;
  const DownloadChoice(this.kind, this.format);
}

/// Bottom sheet for the download action. A video result asks "audio or
/// video" first (a video upload has both to offer), then a format list for
/// whichever was picked; an audio-only result skips straight to the audio
/// format list.
class DownloadFormatSheet extends StatefulWidget {
  final bool isVideo;
  const DownloadFormatSheet({super.key, required this.isVideo});

  static Future<DownloadChoice?> show(BuildContext context, {required bool isVideo}) {
    return showModalBottomSheet<DownloadChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadFormatSheet(isVideo: isVideo),
    );
  }

  @override
  State<DownloadFormatSheet> createState() => _DownloadFormatSheetState();
}

class _DownloadFormatSheetState extends State<DownloadFormatSheet> {
  DownloadKind? _kind;

  @override
  void initState() {
    super.initState();
    if (!widget.isVideo) _kind = DownloadKind.audio;
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (kind != null && widget.isVideo)
                  IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _kind = null),
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textSecondary),
                  )
                else
                  const SizedBox(width: 40),
                Expanded(
                  child: Text(
                    kind == null ? 'Download' : 'Download as',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
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
            const SizedBox(height: 8),
            if (kind == null) ..._kindTiles() else ..._formatTiles(kind),
          ],
        ),
      ),
    );
  }

  List<Widget> _kindTiles() => [
        _Tile(
          icon: Icons.audiotrack_rounded,
          title: 'Audio',
          subtitle: 'Just the shifted sound track',
          onTap: () => setState(() => _kind = DownloadKind.audio),
        ),
        const SizedBox(height: 10),
        _Tile(
          icon: Icons.videocam_rounded,
          title: 'Video',
          subtitle: 'The shifted audio muxed back into the video',
          onTap: () => setState(() => _kind = DownloadKind.video),
        ),
      ];

  List<Widget> _formatTiles(DownloadKind kind) {
    if (kind == DownloadKind.audio) {
      return [
        _Tile(
          icon: Icons.music_note_rounded,
          title: 'MP3',
          subtitle: 'Smaller file, plays everywhere',
          onTap: () => Navigator.of(context).pop(const DownloadChoice(DownloadKind.audio, 'mp3')),
        ),
        const SizedBox(height: 10),
        _Tile(
          icon: Icons.graphic_eq_rounded,
          title: 'WAV',
          subtitle: 'Uncompressed — largest file, top quality',
          onTap: () => Navigator.of(context).pop(const DownloadChoice(DownloadKind.audio, 'wav')),
        ),
        const SizedBox(height: 10),
        _Tile(
          icon: Icons.high_quality_rounded,
          title: 'M4A',
          subtitle: 'Compressed, good quality (same as in-app playback)',
          onTap: () => Navigator.of(context).pop(const DownloadChoice(DownloadKind.audio, 'm4a')),
        ),
      ];
    }
    return [
      _Tile(
        icon: Icons.movie_rounded,
        title: 'Same as original',
        subtitle: 'Keep the upload\'s original video format',
        onTap: () => Navigator.of(context).pop(const DownloadChoice(DownloadKind.video, 'auto')),
      ),
      const SizedBox(height: 10),
      _Tile(
        icon: Icons.movie_rounded,
        title: 'MP4',
        subtitle: 'Most widely compatible',
        onTap: () => Navigator.of(context).pop(const DownloadChoice(DownloadKind.video, 'mp4')),
      ),
      const SizedBox(height: 10),
      _Tile(
        icon: Icons.movie_rounded,
        title: 'MOV',
        subtitle: 'Apple / QuickTime format',
        onTap: () => Navigator.of(context).pop(const DownloadChoice(DownloadKind.video, 'mov')),
      ),
    ];
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
