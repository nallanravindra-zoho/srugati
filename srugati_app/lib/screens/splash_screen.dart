import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _transitionStarted = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _controller = VideoPlayerController.asset('assets/srugati1.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
        _controller.addListener(_checkVideoFinished);
      });
  }

  void _checkVideoFinished() {
    final v = _controller.value;
    if (v.isInitialized && v.position >= v.duration && !_transitionStarted) {
      _transitionStarted = true;
      _fadeController.forward().then((_) => _goToHome());
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_checkVideoFinished);
    _controller.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: _controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : const CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}
