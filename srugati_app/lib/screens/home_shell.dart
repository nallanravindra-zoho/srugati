import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/theme_settings.dart';
import '../theme/app_theme.dart';
import 'studio_screen.dart';
import 'library_screen.dart';
import 'practice_screen.dart';
import 'remover_screen.dart';

final GlobalKey<LibraryScreenState> libraryKey =
    GlobalKey<LibraryScreenState>();
final GlobalKey<StudioScreenState> studioKey = GlobalKey<StudioScreenState>();
final GlobalKey<RemoverScreenState> removerKey =
    GlobalKey<RemoverScreenState>();

/// Lets any screen (e.g. the Library) jump to another bottom-nav tab.
final ValueNotifier<int> homeTab = ValueNotifier<int>(0);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Rebuilt on every theme change so the screens pick up the new colours
  // (the keys keep their state alive).
  List<Widget> get _pages => [
    StudioScreen(key: studioKey),
    LibraryScreen(key: libraryKey),
    PracticeScreen(),
    RemoverScreen(key: removerKey),
  ];

  void _onBack() {
    if (homeTab.value != 0) {
      homeTab.value = 0;
    } else if (!(studioKey.currentState?.handleBack() ?? false)) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemePreset>(
      valueListenable: ThemeSettings.preset,
      builder: (context, _, __) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: ValueListenableBuilder<int>(
          valueListenable: homeTab,
          builder: (context, index, _) => Scaffold(
            body: IndexedStack(index: index, children: _pages),
            bottomNavigationBar: NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 68,
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.purpleDeep,
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => TextStyle(
                    fontSize: 14,
                    fontWeight: states.contains(WidgetState.selected)
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: states.contains(WidgetState.selected)
                        ? AppColors.purple
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => homeTab.value = i,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.graphic_eq_rounded),
                    label: 'Studio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_rounded),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.mic_rounded),
                    label: 'Practice',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: 'Remover',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
