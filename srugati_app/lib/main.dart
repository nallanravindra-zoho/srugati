import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SruGatiApp());
}

/// Disables Android's "stretch" overscroll effect app-wide — with the
/// tall, mostly-static content on Studio/Library, that effect visibly
/// distorted the whole screen on every small drag.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class SruGatiApp extends StatelessWidget {
  const SruGatiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SruGati',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: _NoStretchScrollBehavior(),
      home: const SplashScreen(),
    );
  }
}
