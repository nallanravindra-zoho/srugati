import 'package:flutter/material.dart';

import 'help_note.dart';

import '../services/song_store.dart';
import '../services/studio_controller.dart';
import '../theme/app_theme.dart';
import 'note_chip_row.dart';
import 'waveform_view.dart';

String formatSeconds(double seconds) {
  final total = seconds.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Shared chrome for the Studio bottom sheets: rounded dark panel, title
/// row with a close button, scrollable body that rebuilds on controller changes.
class StudioSheet extends StatelessWidget {
  final String title;
  final StudioController controller;
  final Widget Function(BuildContext) bodyBuilder;
  final Widget? trailing;

  const StudioSheet({
    super.key,
    required this.title,
    required this.controller,
    required this.bodyBuilder,
    this.trailing,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required StudioController controller,
    required Widget Function(BuildContext) bodyBuilder,
    Widget? trailing,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StudioSheet(
        title: title,
        controller: controller,
        bodyBuilder: bodyBuilder,
        trailing: trailing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: controller.changes,
                builder: (context, _) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  children: [bodyBuilder(context)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SheetCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SheetCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
}

class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const _Segmented({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                height: 40,
                decoration: BoxDecoration(
                  gradient: i == selected ? AppColors.brandGradient : null,
                  color: i == selected ? null : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: i == selected
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          if (i != labels.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.brandGradient : null,
          color: selected ? null : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Key & Tempo
// ---------------------------------------------------------------------------

class KeyTempoBody extends StatefulWidget {
  final StudioController c;
  const KeyTempoBody({super.key, required this.c});

  @override
  State<KeyTempoBody> createState() => _KeyTempoBodyState();
}

class _KeyTempoBodyState extends State<KeyTempoBody> {
  int _mode = 0; // 0 simple, 1 pro
  bool _bpmUnits = true;

  StudioController get c => widget.c;

  String _signed(int v) => v > 0 ? '+$v' : '$v';

  Future<double?> _askNumber(String title, double initial, String suffix) {
    final controller = TextEditingController(text: initial.round().toString());
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: suffix),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _keyBox(String label, String value, {bool highlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: highlight
              ? Border.all(color: AppColors.purple.withValues(alpha: 0.6))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: highlight ? AppColors.purple : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final centsLabel = c.cents == 0 ? '' : ' ${_signed(c.cents)}¢';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.music_note_rounded,
                    color: AppColors.purple,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Key',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: c.resetShift,
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _keyBox('Original', c.originalKey),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  _keyBox(
                    'Current',
                    '${c.currentKeyLabel}$centsLabel',
                    highlight: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Segmented(
                labels: const ['Simple', 'Pro'],
                selected: _mode,
                onChanged: (i) => setState(() => _mode = i),
              ),
              const SizedBox(height: 14),
              if (_mode == 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: c.semitones > -12
                          ? () => c.setSemitones(c.semitones - 1)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    SizedBox(
                      width: 150,
                      child: Column(
                        children: [
                          Text(
                            _signed(c.semitones),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'semitones',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: c.semitones < 12
                          ? () => c.setSemitones(c.semitones + 1)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final v in [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Chip(
                            label: _signed(v),
                            selected: c.semitones == v,
                            onTap: () => c.setSemitones(v),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Jump to note',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                c.analysed
                    ? NoteChipRow(
                        selected: c.currentNote,
                        onSelect: c.selectNote,
                      )
                    : const SizedBox.shrink(),
              ] else ...[
                Center(
                  child: Text(
                    c.cents == 0 ? 'In tune' : '${_signed(c.cents)} cents',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Center(
                  child: Text(
                    'fine adjustment on top of the semitone shift',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Slider(
                  value: c.cents.toDouble(),
                  min: -50,
                  max: 50,
                  divisions: 100,
                  onChanged: (v) => c.setCents(v.round()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final step in [-10, -1, 1, 10])
                      OutlinedButton(
                        onPressed: () =>
                            c.setCents((c.cents + step).clamp(-50, 50)),
                        child: Text(_signed(step)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SheetCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.speed_rounded, color: AppColors.purple, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Tempo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 130,
                    child: _Segmented(
                      labels: const ['BPM', '%'],
                      selected: _bpmUnits ? 0 : 1,
                      onChanged: (i) => setState(() => _bpmUnits = i == 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TempoBox(
                      label: 'Original (detected)',
                      value: _bpmUnits
                          ? '${c.originalBpm.round()} BPM'
                          : '100%',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        if (_bpmUnits) {
                          final v = await _askNumber(
                            'Target tempo',
                            c.currentBpm,
                            'BPM',
                          );
                          if (v != null && v > 0)
                            c.setTempo(
                              (v / c.originalBpm).clamp(0.5, 2.0).toDouble(),
                            );
                        } else {
                          final v = await _askNumber(
                            'Tempo',
                            c.tempo * 100,
                            '%',
                          );
                          if (v != null && v > 0)
                            c.setTempo((v / 100).clamp(0.5, 2.0).toDouble());
                        }
                      },
                      child: _TempoBox(
                        label: 'Current (tap to edit)',
                        value: _bpmUnits
                            ? '${c.currentBpm.round()} BPM'
                            : '${(c.tempo * 100).round()}%',
                        highlight: true,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: c.tempo.clamp(0.5, 2.0),
                min: 0.5,
                max: 2.0,
                divisions: 60,
                onChanged: (v) =>
                    c.setTempo(double.parse(v.toStringAsFixed(2))),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _bpmUnits ? '${(c.originalBpm * 0.5).round()}' : '50%',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    _bpmUnits ? '${(c.originalBpm * 2).round()}' : '200%',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Count-in before play',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final beats in [0, 1, 2, 4]) ...[
                    _Chip(
                      label: beats == 0
                          ? 'Off'
                          : '$beats beat${beats == 1 ? '' : 's'}',
                      selected: c.countInBeats == beats,
                      onTap: () => c.setCountIn(beats),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TempoBox extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _TempoBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: highlight
            ? Border.all(color: AppColors.purple.withValues(alpha: 0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.purple : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Natural Voice
// ---------------------------------------------------------------------------

class NaturalVoiceBody extends StatelessWidget {
  final StudioController c;
  const NaturalVoiceBody({super.key, required this.c});

  Widget _option({required bool on, required List<Widget> lines}) {
    final selected = c.naturalVoice == on;
    return GestureDetector(
      onTap: c.isVideo ? null : () => c.setNaturalVoice(on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppColors.purple : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: on ? AppColors.brandGradient : null,
                    color: on ? null : AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.record_voice_over_rounded,
                    color: on ? Colors.white : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Natural Voice',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        on ? 'ON' : 'OFF',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? AppColors.purple
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.purple : AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...lines,
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, Color color, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 14, color: color)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Preserve formants',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        HelpNote('Keeps vocals sounding natural when changing pitch.'),
        const SizedBox(height: 18),
        _option(
          on: true,
          lines: [
            _line(Icons.check_rounded, AppColors.teal, 'Natural vocal tone'),
            _line(Icons.check_rounded, AppColors.teal, 'No robotic effect'),
            _line(
              Icons.hourglass_bottom_rounded,
              AppColors.textSecondary,
              'Rendered on the server — a short wait after each change',
            ),
          ],
        ),
        _option(
          on: false,
          lines: [
            _line(
              Icons.warning_amber_rounded,
              AppColors.warning,
              'Voice may sound brighter / deeper',
            ),
            _line(
              Icons.bolt_rounded,
              AppColors.textSecondary,
              'Instant, on-device preview',
            ),
          ],
        ),
        if (c.isVideo)
          HelpNote('Videos are always processed with Natural Voice on.'),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 8),
                Text(
                  'What are formants?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            children: [
              HelpNote(
                'Formants are the resonances of the voice that give it its character. A plain pitch '
                'shift moves them along with the pitch, which is why shifted voices can sound like a '
                'different person. Preserving formants shifts the pitch while keeping that character '
                'in place.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loop & Markers
// ---------------------------------------------------------------------------

class LoopMarkersBody extends StatefulWidget {
  final StudioController c;
  const LoopMarkersBody({super.key, required this.c});

  @override
  State<LoopMarkersBody> createState() => _LoopMarkersBodyState();
}

class _LoopMarkersBodyState extends State<LoopMarkersBody> {
  int _tab = 0;
  static const _presets = ['Intro', 'Verse', 'Chorus', 'Bridge', 'Outro'];

  StudioController get c => widget.c;

  Future<void> _addCustomMarker() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marker name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) c.addMarker(name);
  }

  @override
  Widget build(BuildContext context) {
    final hasLoop = c.loopA != null && c.loopB != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetCard(
          child: Column(
            children: [
              WaveformView(
                peaks: c.peaks,
                durationSec: c.durationSec,
                positionSec: c.positionSec,
                loopA: c.loopA,
                loopB: c.loopB,
                markers: c.markers,
                editableLoop: true,
                height: 110,
                onSeek: c.seekTo,
                onLoopChanged: c.setLoop,
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: c.positionSec,
                builder: (_, pos, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatSeconds(pos),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (hasLoop)
                      Text(
                        'A ${formatSeconds(c.loopA!)}  →  B ${formatSeconds(c.loopB!)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.purple,
                        ),
                      ),
                    Text(
                      formatSeconds(c.durationSec),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Segmented(
          labels: const ['Loop', 'Markers'],
          selected: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 14),
        if (_tab == 0) ...[
          SheetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Repeat',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final entry in {
                      3: '3 times',
                      5: '5 times',
                      0: 'Until I stop',
                    }.entries) ...[
                      _Chip(
                        label: entry.value,
                        selected: c.loopRepeats == entry.key,
                        onTap: () => c.setLoopRepeats(entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: c.durationSec <= 0
                            ? null
                            : () {
                                final pos = c.positionSec.value;
                                final b = hasLoop
                                    ? c.loopB!
                                    : (pos + 15)
                                          .clamp(0, c.durationSec)
                                          .toDouble();
                                c.setLoop(pos.clamp(0, b - 0.5).toDouble(), b);
                              },
                        child: const Text('Set A here'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: c.durationSec <= 0
                            ? null
                            : () {
                                final pos = c.positionSec.value;
                                final a = hasLoop
                                    ? c.loopA!
                                    : (pos - 15)
                                          .clamp(0, c.durationSec)
                                          .toDouble();
                                c.setLoop(
                                  a.clamp(0, pos - 0.5).toDouble(),
                                  pos.clamp(a + 0.5, c.durationSec).toDouble(),
                                );
                              },
                        child: const Text('Set B here'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: hasLoop
                      ? FilledButton.tonal(
                          onPressed: c.clearLoop,
                          child: const Text('Clear loop'),
                        )
                      : FilledButton(
                          onPressed: c.durationSec <= 0
                              ? null
                              : () {
                                  final pos = c.positionSec.value;
                                  c.setLoop(
                                    pos,
                                    (pos + 15)
                                        .clamp(pos + 1, c.durationSec)
                                        .toDouble(),
                                  );
                                },
                          child: const Text('Add loop at playhead'),
                        ),
                ),
                if (hasLoop)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: HelpNote(
                      'Drag the A and B handles on the waveform to fine-tune the loop.',
                    ),
                  ),
              ],
            ),
          ),
        ] else ...[
          SheetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add marker at playhead',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in _presets)
                      _Chip(
                        label: name,
                        selected: false,
                        onTap: () => c.addMarker(name),
                      ),
                    _Chip(
                      label: '+ Custom',
                      selected: false,
                      onTap: _addCustomMarker,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (c.markers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: HelpNote(
                'No markers yet — play to a spot, then tap a name above.',
              ),
            )
          else
            for (var i = 0; i < c.markers.length; i++)
              _markerRow(
                c.markers[i],
                i < c.markers.length - 1 ? c.markers[i + 1] : null,
              ),
        ],
      ],
    );
  }

  Widget _markerRow(SongMarker marker, SongMarker? next) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        onTap: () => c.seekTo(marker.seconds),
        leading: Icon(Icons.flag_rounded, color: AppColors.teal),
        title: Text(
          marker.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          formatSeconds(marker.seconds),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Loop this section',
              icon: Icon(Icons.repeat_rounded, color: AppColors.purple),
              onPressed: () =>
                  c.setLoop(marker.seconds, next?.seconds ?? c.durationSec),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.textSecondary,
              ),
              onPressed: () => c.removeMarker(marker),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metronome + progressive tempo training
// ---------------------------------------------------------------------------

class MetronomeBody extends StatelessWidget {
  final StudioController c;
  const MetronomeBody({super.key, required this.c});

  Widget _label(String text, {String? trailing}) => Row(
    children: [
      Expanded(
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      if (trailing != null)
        Text(
          trailing,
          style: TextStyle(
            color: AppColors.purple,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );

  Widget _stepper(
    String title,
    String value,
    VoidCallback minus,
    VoidCallback plus,
  ) => Row(
    children: [
      Expanded(
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      IconButton(
        onPressed: minus,
        icon: const Icon(Icons.remove_circle_outline_rounded),
      ),
      SizedBox(
        width: 56,
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      IconButton(
        onPressed: plus,
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final rateIdx = c.metronomeRate == 0.5 ? 0 : (c.metronomeRate == 2 ? 2 : 1);
    final start = c.trainStartPct, step = c.trainStepPct, reps = c.trainRepeats;
    final steps = <int>[];
    for (var p = start; p < 100 + step && steps.length < 12; p += step) {
      steps.add(p > 100 ? 100 : p);
      if (p >= 100) break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: AppColors.purple),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Metronome',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Switch(value: c.metronomeOn, onChanged: c.setMetronomeOn),
                ],
              ),
              HelpNote(
                '${c.originalBpm.round()} BPM song · clicks stay locked to the song\'s beat at any tempo',
              ),
              const SizedBox(height: 14),
              _label(
                'Volume',
                trailing: '${(c.metronomeVolume * 100).round()}%',
              ),
              Slider(
                value: c.metronomeVolume,
                min: 0.1,
                max: 1,
                onChanged: c.setMetronomeVolume,
              ),
              _label('Click rate'),
              const SizedBox(height: 8),
              _Segmented(
                labels: const ['Half', 'Beat', 'Double'],
                selected: rateIdx,
                onChanged: (i) => c.setMetronomeRate(const [0.5, 1.0, 2.0][i]),
              ),
              const SizedBox(height: 14),
              _stepper(
                'Align clicks',
                '${c.beatNudgeMs >= 0 ? '+' : ''}${c.beatNudgeMs} ms',
                () => c.nudgeBeat(-10),
                () => c.nudgeBeat(10),
              ),
              Row(
                children: [
                  Expanded(
                    child: HelpNote(
                      'Clicks sound early or late? Nudge them until they sit on the beat.',
                    ),
                  ),
                  TextButton(
                    onPressed: c.tapClick,
                    child: const Text('Test click'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _label('Count-in before play'),
              const SizedBox(height: 8),
              _Segmented(
                labels: const ['Off', '1', '2', '4'],
                selected: const [
                  0,
                  1,
                  2,
                  4,
                ].indexOf(c.countInBeats).clamp(0, 3),
                onChanged: (i) => c.setCountIn(const [0, 1, 2, 4][i]),
              ),
            ],
          ),
        ),
        SheetCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded, color: AppColors.purple),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Progressive training',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              HelpNote(
                c.hasLoop
                    ? 'Plays your A–B loop, speeding up after every set of repeats.'
                    : 'No loop set — it will practise the whole song. Set A–B to drill one section.',
                title: 'Progressive training',
              ),
              const SizedBox(height: 10),
              _stepper(
                'Start at',
                '$start%',
                () => c.setTrainStart(start - 5),
                () => c.setTrainStart(start + 5),
              ),
              _stepper(
                'Speed up by',
                '+$step%',
                () => c.setTrainStep(step - 5),
                () => c.setTrainStep(step + 5),
              ),
              _stepper(
                'Repeats per step',
                '$reps×',
                () => c.setTrainRepeats(reps - 1),
                () => c.setTrainRepeats(reps + 1),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in steps)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: c.training && p == c.trainCurrentPct
                            ? AppColors.brandGradient
                            : null,
                        color: c.training && p == c.trainCurrentPct
                            ? null
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$p%',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: c.training && p == c.trainCurrentPct
                              ? Colors.white
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: c.training
                    ? OutlinedButton.icon(
                        onPressed: c.stopTraining,
                        icon: const Icon(Icons.stop_rounded),
                        label: Text(
                          'Stop training · ${c.trainCurrentPct}% · pass ${c.trainPass + 1}/$reps',
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          c.startTraining();
                          Navigator.of(context).maybePop();
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Start training'),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
