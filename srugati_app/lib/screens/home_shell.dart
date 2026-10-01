import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'studio_screen.dart';
import 'library_screen.dart';
import 'practice_screen.dart';

final GlobalKey<LibraryScreenState> libraryKey = GlobalKey<LibraryScreenState>();

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    const StudioScreen(),
    LibraryScreen(key: libraryKey),
    const PracticeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 68,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.purple,
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? Colors.white : AppColors.textSecondary,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? AppColors.purple : AppColors.textSecondary,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.graphic_eq_rounded), label: 'Studio'),
            NavigationDestination(icon: Icon(Icons.library_music_rounded), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.mic_rounded), label: 'Practice'),
          ],
        ),
      ),
    );
  }
}
