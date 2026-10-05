import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/take_recorder.dart';
import 'services/theme_settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeSettings.load();
  await TakeRecorder.loadSettings();
  runApp(const SruGatiApp());
}

/// Disables Android's "stretch" overscroll effect app-wide — with the
/// tall, mostly-static content on Studio/Library, that effect visibly
/// distorted the whole screen on every small drag.
class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class SruGatiApp extends StatelessWidget {
  const SruGatiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemePreset>(
      valueListenable: ThemeSettings.preset,
      builder: (context, _, __) => MaterialApp(
        title: 'SruGati',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        scrollBehavior: _NoStretchScrollBehavior(),
        builder: (context, child) {
          // Larger text everywhere: never below 1.12x, but respect a bigger system setting.
          final mq = MediaQuery.of(context);
          final scale = mq.textScaler.scale(1.0) < 1.12
              ? 1.12
              : mq.textScaler.scale(1.0);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
