import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player_row.dart';
import 'video_player_screen.dart';

const _videoExtensions = {'.mp4', '.mov', '.mkv', '.webm', '.avi'};
const _audioExtensions = {'.m4a', '.mp3', '.wav', '.aac', '.flac', '.ogg'};

bool _isVideoFile(String path) => _videoExtensions.contains(p.extension(path).toLowerCase());
bool _isMediaFile(String path) =>
    _isVideoFile(path) || _audioExtensions.contains(p.extension(path).toLowerCase());

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> {
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final dir = await getApplicationDocumentsDirectory();
    final entries = dir.listSync().where((f) => _isMediaFile(f.path)).toList();
    entries.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (mounted) setState(() => _files = entries);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: _files.isEmpty
          ? Center(
              child: Text('Nothing shifted yet', style: TextStyle(color: AppColors.textSecondary)),
            )
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final path = _files[index].path;
                  final name = p.basename(path);
                  if (_isVideoFile(path)) {
                    return Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        leading: const Icon(Icons.video_library_rounded, color: AppColors.purple),
                        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.play_circle_fill_rounded, color: AppColors.teal),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: path)),
                        ),
                      ),
                    );
                  }
                  return MiniPlayerRow(key: ValueKey(path), path: path, title: name);
                },
              ),
            ),
    );
  }
}
