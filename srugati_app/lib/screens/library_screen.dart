import 'dart:io';

import 'package:flutter/material.dart';

import '../services/player_service.dart';

import 'package:file_saver/file_saver.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/song_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_song_panel.dart';
import '../widgets/mini_player_row.dart';
import '../widgets/note_chip_row.dart';
import '../widgets/theme_picker_sheet.dart';
import 'home_shell.dart';
import 'video_player_screen.dart';

const _videoExtensions = {'.mp4', '.mov', '.mkv', '.webm', '.avi'};
const _audioExtensions = {'.m4a', '.mp3', '.wav', '.aac', '.flac', '.ogg'};

bool _isVideoFile(String path) =>
    _videoExtensions.contains(p.extension(path).toLowerCase());
bool _isMediaFile(String path) =>
    _isVideoFile(path) ||
    _audioExtensions.contains(p.extension(path).toLowerCase());

enum _Filter { all, practice, favorites }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> {
  List<FileSystemEntity> _versions = [];
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    SongStore.instance.load().then((_) => refresh());
  }

  /// Reloads the rendered "saved versions" (files produced by Save).
  Future<void> refresh() async {
    final dir = await getApplicationDocumentsDirectory();
    final entries = dir
        .listSync()
        .whereType<File>()
        .where((f) => _isMediaFile(f.path))
        .toList();
    entries.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    if (mounted) setState(() => _versions = entries);
  }

  Future<void> _addSong() async {
    final source = await AddSongPanel.showSheet(context);
    if (source == null) return;
    homeTab.value = 0;
    await studioKey.currentState?.importFrom(source);
  }

  void _open(SongRecord song) {
    homeTab.value = 0;
    studioKey.currentState?.openSong(song);
  }

  String _recipeLabel(SongRecord s) {
    final base = s.originalTonic ?? '—';
    if (!s.hasRecipe) {
      final bpm = s.originalBpm == null
          ? ''
          : ' · ${s.originalBpm!.round()} BPM';
      return '$base$bpm';
    }
    final idx = kNoteNames.indexOf(base);
    final now = idx < 0
        ? base
        : kNoteNames[((idx + s.semitones) % 12 + 12) % 12];
    final cents = s.cents == 0 ? '' : ' ${s.cents > 0 ? '+' : ''}${s.cents}¢';
    final bpm = s.originalBpm == null
        ? ''
        : ' · ${(s.originalBpm! * s.tempo).round()} BPM';
    return '$base → $now$cents$bpm';
  }

  List<SongRecord> _filtered(List<SongRecord> all) {
    final q = _query.trim().toLowerCase();
    return all.where((s) {
      if (q.isNotEmpty && !s.name.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.practice =>
          s.hasRecipe || s.loopA != null || s.markers.isNotEmpty,
        _Filter.favorites => s.favorite,
      };
    }).toList();
  }

  Widget _filterChip(String label, _Filter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.brandGradient : null,
            color: selected ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _songTile(SongRecord s) {
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
        ),
      ),
      confirmDismiss: (_) async =>
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Remove song?'),
              content: Text(
                '“${s.name}” and its saved settings will be removed from your Library.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ) ??
          false,
      onDismissed: (_) => SongStore.instance.remove(s),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _open(s),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    s.isVideo ? Icons.movie_rounded : Icons.music_note_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _recipeLabel(s),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () async {
                    if (await _confirmRemoveSong(s))
                      SongStore.instance.remove(s);
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
                IconButton(
                  tooltip: 'Save to my device',
                  onPressed: () => _saveToDevice(s),
                  icon: Icon(
                    Icons.download_rounded,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    s.favorite = !s.favorite;
                    SongStore.instance.update(s);
                  },
                  icon: Icon(
                    s.favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: s.favorite
                        ? AppColors.purple
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmRemoveSong(SongRecord s) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete song?'),
          content: Text(
            '“${s.name}” and its saved settings will be deleted from your Library.',
            style: const TextStyle(fontSize: 17),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _confirmDeleteVersion(FileSystemEntity f) async {
    final name = p.basename(f.path);
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete saved version?'),
            content: Text(
              '“$name” will be deleted.',
              style: const TextStyle(fontSize: 17),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final service = PlayerService.instance;
    if (service.isLoaded(f.path)) await service.pause();
    try {
      await File(f.path).delete();
    } catch (_) {}
    await refresh();
  }

  Future<void> _saveVersionToDevice(FileSystemEntity f) async {
    final ext = p.extension(f.path).replaceFirst('.', '');
    try {
      await FileSaver.instance.saveAs(
        name: p.basenameWithoutExtension(f.path),
        filePath: f.path,
        fileExtension: ext.isEmpty ? 'm4a' : ext,
        mimeType: MimeType.other,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save to that location")),
        );
      }
    }
  }

  Future<void> _saveToDevice(SongRecord s) async {
    final ext = p.extension(s.path).replaceFirst('.', '');
    try {
      await FileSaver.instance.saveAs(
        name: s.name,
        filePath: s.path,
        fileExtension: ext.isEmpty ? 'm4a' : ext,
        mimeType: MimeType.other,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save to that location")),
        );
      }
    }
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => homeTab.value = 0,
        ),
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Theme',
            onPressed: () => ThemePickerSheet.show(context),
            icon: Icon(Icons.palette_outlined, color: AppColors.purple),
          ),
          IconButton(
            onPressed: _addSong,
            icon: Icon(Icons.add_rounded, color: AppColors.purple),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: SongStore.instance,
        builder: (context, _) {
          final songs = _filtered(SongStore.instance.songs);
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search songs',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _filterChip('All Songs', _Filter.all),
                    _filterChip('My Practice', _Filter.practice),
                    _filterChip('Favorites', _Filter.favorites),
                  ],
                ),
                _sectionTitle(
                  _filter == _Filter.all && _query.isEmpty ? 'Recent' : 'Songs',
                ),
                if (songs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        SongStore.instance.songs.isEmpty
                            ? 'No songs yet — tap + to add one'
                            : 'No songs match',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  for (final s in songs) ...[
                    _songTile(s),
                    const SizedBox(height: 10),
                  ],
                if (_versions.isNotEmpty) ...[
                  _sectionTitle('Saved versions'),
                  for (final f in _versions) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              if (_isVideoFile(f.path)) {
                                return Material(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    leading: Icon(
                                      Icons.video_library_rounded,
                                      color: AppColors.purple,
                                    ),
                                    title: Text(
                                      p.basename(f.path),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: AppColors.teal,
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            VideoPlayerScreen(path: f.path),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return MiniPlayerRow(
                                key: ValueKey(f.path),
                                path: f.path,
                                title: p.basename(f.path),
                              );
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Save to my device',
                          onPressed: () => _saveVersionToDevice(f),
                          icon: Icon(
                            Icons.download_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          onPressed: () => _confirmDeleteVersion(f),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
