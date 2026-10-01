import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

/// Full-featured video playback for both the original upload and a
/// pitch-shifted result (its shifted audio already muxed in server-side) —
/// play/pause, scrubbing with time readout, ±10s, volume, and a maximize
/// toggle that rotates into an immersive landscape view.
class VideoPlayerScreen extends StatefulWidget {
  final String path;
  const VideoPlayerScreen({super.key, required this.path});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _fullscreen = false;
  bool _muted = false;
  final double _volume = 1.0;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..addListener(() => setState(() {}))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    if (_fullscreen) _exitFullscreenChrome();
    _controller.dispose();
    super.dispose();
  }

  void _enterFullscreenChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreenChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      _enterFullscreenChrome();
    } else {
      _exitFullscreenChrome();
    }
  }

  void _seekBy(Duration delta) {
    final total = _controller.value.duration;
    final target = _controller.value.position + delta;
    _controller.seekTo(target < Duration.zero
        ? Duration.zero
        : (target > total ? total : target));
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _controller.setVolume(_muted ? 0 : _volume);
    });
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final initialized = _controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
      body: SafeArea(
        top: !_fullscreen,
        bottom: !_fullscreen,
        child: GestureDetector(
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: initialized
                    ? AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      )
                    : const CircularProgressIndicator(color: AppColors.teal),
              ),
              if (initialized && _controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildControls(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
              min: 0,
              max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
              activeColor: AppColors.teal,
              inactiveColor: Colors.white24,
              onChanged: (v) => _controller.seekTo(Duration(milliseconds: v.round())),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(_fmt(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _toggleMute,
                icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _seekBy(const Duration(seconds: -10)),
                    icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 28),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                    child: IconButton(
                      onPressed: () => setState(() {
                        _controller.value.isPlaying ? _controller.pause() : _controller.play();
                      }),
                      icon: Icon(
                        _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _seekBy(const Duration(seconds: 10)),
                    icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 28),
                  ),
                ],
              ),
              IconButton(
                onPressed: _toggleFullscreen,
                icon: Icon(
                  _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
