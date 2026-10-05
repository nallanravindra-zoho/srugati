import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Replaces small grey explanatory text: a tappable "i" that opens a popup
/// with the explanation in a large, easy-to-read size.
class HelpNote extends StatelessWidget {
  final String text;
  final String title;
  final String? label;
  const HelpNote(this.text, {super.key, this.title = 'Help', this.label});

  static Future<void> show(
    BuildContext context,
    String text, {
    String title = 'Help',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        content: SingleChildScrollView(
          child: Text(text, style: const TextStyle(fontSize: 18, height: 1.4)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => show(context, text, title: title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 24,
                color: AppColors.purple,
              ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
