import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ImportSource { files, deviceMusic, record }

/// "Add Song" entry points (Files / Device Music / Record) plus the list of
/// things SruGati works out automatically after import. Used on Studio's
/// empty state and in the Library's "+" sheet.
class AddSongPanel extends StatelessWidget {
  final ValueChanged<ImportSource> onPick;
  const AddSongPanel({super.key, required this.onPick});

  static Future<ImportSource?> showSheet(BuildContext context) {
    return showModalBottomSheet<ImportSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add Song',
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
              AddSongPanel(onPick: (source) => Navigator.pop(ctx, source)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, ImportSource source) {
    return Expanded(
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onPick(source),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Icon(icon, color: AppColors.purple, size: 26),
                const SizedBox(height: 8),
                Text(
                  label,
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

  Widget _check(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(Icons.check_rounded, size: 18, color: AppColors.teal),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.surfaceMuted, width: 1.5),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Add a song',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Audio or video — choose where from',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _tile(Icons.folder_rounded, 'Files', ImportSource.files),
                  const SizedBox(width: 10),
                  _tile(
                    Icons.library_music_rounded,
                    'Device Music',
                    ImportSource.deviceMusic,
                  ),
                  const SizedBox(width: 10),
                  _tile(Icons.mic_rounded, 'Record', ImportSource.record),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'After adding, you can choose to detect:',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _check('Key / Pitch'),
              _check('BPM (tempo)'),
              _check('Waveform'),
            ],
          ),
        ),
      ],
    );
  }
}
