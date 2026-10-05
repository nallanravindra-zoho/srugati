import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// One audio player for the whole app. Loading a new track always replaces
/// whatever is currently loaded — there is never more than one thing playing
/// at once, whether that's the original upload or a freshly-shifted result.
class PlayerService extends ChangeNotifier {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();

  String? currentPath;
  String currentTitle = '';

  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  Stream<Duration> get positionStream => player.positionStream;
  Duration? get duration => player.duration;

  bool isLoaded(String path) => currentPath == path;

  /// Loads [path] into the single shared player, replacing any current
  /// track, and optionally starts playback immediately.
  Future<void> load(String path, String title, {bool autoPlay = false}) async {
    if (currentPath == path) {
      if (autoPlay) await play();
      return;
    }
    await player.stop();
    currentPath = path;
    currentTitle = title;
    notifyListeners();
    await player.setFilePath(path);
    if (autoPlay) await play();
  }

  Future<void> play() => player.play();
  Future<void> pause() => player.pause();
  Future<void> seek(Duration position) => player.seek(position);
  Future<void> setVolume(double volume) => player.setVolume(volume);

  Future<void> seekBy(Duration delta) async {
    final total = player.duration ?? Duration.zero;
    final target = player.position + delta;
    await player.seek(
      target < Duration.zero
          ? Duration.zero
          : (target > total ? total : target),
    );
  }
}
