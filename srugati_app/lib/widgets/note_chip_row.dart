import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const kNoteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// All 12 notes laid out in a wrap so every one is reachable at a glance —
/// tap one to jump the pitch shift straight to that target note.
class NoteChipRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const NoteChipRow({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kNoteNames.map((note) {
        final isSelected = note == selected;
        return GestureDetector(
          onTap: () => onSelect(note),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            width: 52,
            height: 44,
            decoration: BoxDecoration(
              gradient: isSelected ? AppColors.brandGradient : null,
              color: isSelected ? null : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              note,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
