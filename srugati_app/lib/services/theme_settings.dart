import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

/// The user's chosen colour preset, remembered between launches.
class ThemeSettings {
  ThemeSettings._();

  static final ValueNotifier<ThemePreset> preset = ValueNotifier<ThemePreset>(
    kThemePresets.first,
  );

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'settings.json'));
  }

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final id = (jsonDecode(await file.readAsString()) as Map)['themePreset'];
      final found = kThemePresets.where((t) => t.id == id);
      if (found.isNotEmpty) _set(found.first);
    } catch (_) {
      // Unreadable settings just fall back to the default theme.
    }
  }

  static void _set(ThemePreset value) {
    AppColors.apply(value);
    preset.value = value;
  }

  static Future<void> select(ThemePreset value) async {
    _set(value);
    try {
      await (await _file()).writeAsString(
        jsonEncode({'themePreset': value.id}),
      );
    } catch (_) {}
  }
}
