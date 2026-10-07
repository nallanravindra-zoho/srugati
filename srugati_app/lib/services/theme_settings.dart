import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
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

  /// The colour the user picked for the "Custom" theme, if any.
  static Color? customColor;

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final map = jsonDecode(await file.readAsString()) as Map;
      final cc = map['customColor'];
      if (cc is int) customColor = Color(cc);
      final id = map['themePreset'];
      if (id == 'custom' && customColor != null) {
        _set(ThemePreset.fromColor(customColor!));
        return;
      }
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

  static Future<void> _save() async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({
          'themePreset': preset.value.id,
          'customColor': customColor?.toARGB32(),
        }),
      );
    } catch (_) {}
  }

  static Future<void> select(ThemePreset value) async {
    _set(value);
    await _save();
  }

  /// Applies the colour to the whole app without saving it (live preview while
  /// the user drags the sliders).
  static void preview(Color base) => _set(ThemePreset.fromColor(base));

  /// Puts back a theme after a cancelled preview.
  static void restore(ThemePreset value) => _set(value);

  static Future<void> selectCustom(Color base) async {
    customColor = base;
    _set(ThemePreset.fromColor(base));
    await _save();
  }
}
