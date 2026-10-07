import 'package:flutter/material.dart';

import '../services/theme_settings.dart';
import '../theme/app_theme.dart';

/// Pick any colour for the app. The whole app recolours live while the
/// sliders move; "Apply" keeps it, closing the sheet any other way puts the
/// previous theme back.
class CustomColorSheet extends StatefulWidget {
  const CustomColorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CustomColorSheet(),
    );
  }

  @override
  State<CustomColorSheet> createState() => _CustomColorSheetState();
}

class _CustomColorSheetState extends State<CustomColorSheet> {
  late final ThemePreset _original = AppColors.preset;
  late double _hue;
  late double _sat;
  late double _light;
  late final TextEditingController _hex;
  bool _applied = false;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    final start = HSLColor.fromColor(
      ThemeSettings.customColor ?? AppColors.purple,
    );
    _hue = start.hue;
    _sat = start.saturation.clamp(0.35, 1.0);
    _light = start.lightness.clamp(0.5, 0.8);
    _hex = TextEditingController(text: _hexOf(_color));
    ThemeSettings.preview(_color);
  }

  Color get _color => HSLColor.fromAHSL(1, _hue, _sat, _light).toColor();

  static String _hexOf(Color c) =>
      c.toARGB32().toRadixString(16).substring(2).toUpperCase();

  void _changed() {
    setState(() => _hexError = null);
    _hex.text = _hexOf(_color);
    ThemeSettings.preview(_color);
  }

  void _typedHex(String text) {
    final clean = text.replaceAll('#', '').trim();
    final value = clean.length == 6 ? int.tryParse(clean, radix: 16) : null;
    if (value == null) {
      setState(
        () => _hexError = clean.isEmpty ? null : 'Use 6 digits, like 7C5CFF',
      );
      return;
    }
    final hsl = HSLColor.fromColor(Color(0xFF000000 | value));
    setState(() {
      _hexError = null;
      _hue = hsl.hue;
      _sat = hsl.saturation.clamp(0.35, 1.0);
      _light = hsl.lightness.clamp(0.5, 0.8);
    });
    ThemeSettings.preview(_color);
  }

  Future<void> _apply() async {
    _applied = true;
    await ThemeSettings.selectCustom(_color);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    if (!_applied) ThemeSettings.restore(_original);
    _hex.dispose();
    super.dispose();
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required List<Color> colors,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 14,
                    trackShape: const RoundedRectSliderTrackShape(),
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = ThemePreset.fromColor(_color);
    final hues = [
      for (var h = 0; h <= 360; h += 30)
        HSLColor.fromAHSL(1, h.toDouble() % 360, 1, 0.6).toColor(),
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Custom colour',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: preview.gradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '#${_hexOf(_color)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _slider(
                  label: 'Colour',
                  value: _hue,
                  min: 0,
                  max: 360,
                  colors: hues,
                  onChanged: (v) {
                    _hue = v;
                    _changed();
                  },
                ),
                _slider(
                  label: 'Vibrancy',
                  value: _sat,
                  min: 0.35,
                  max: 1.0,
                  colors: [
                    HSLColor.fromAHSL(1, _hue, 0.35, _light).toColor(),
                    HSLColor.fromAHSL(1, _hue, 1.0, _light).toColor(),
                  ],
                  onChanged: (v) {
                    _sat = v;
                    _changed();
                  },
                ),
                _slider(
                  label: 'Brightness',
                  value: _light,
                  min: 0.5,
                  max: 0.8,
                  colors: [
                    HSLColor.fromAHSL(1, _hue, _sat, 0.5).toColor(),
                    HSLColor.fromAHSL(1, _hue, _sat, 0.8).toColor(),
                  ],
                  onChanged: (v) {
                    _light = v;
                    _changed();
                  },
                ),
                TextField(
                  controller: _hex,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 7,
                  onChanged: _typedHex,
                  decoration: InputDecoration(
                    labelText: 'Hex code',
                    prefixText: '#',
                    counterText: '',
                    errorText: _hexError,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _apply,
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
