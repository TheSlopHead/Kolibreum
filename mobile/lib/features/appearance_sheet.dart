import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../ui/theme.dart';
import '../ui/components.dart';

Future<void> showAppearance(
  BuildContext context,
  LibraryController controller,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Reading appearance',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Page color',
                  style: TextStyle(fontSize: 13, color: MutColors.accent),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (i, label) in ['Paper', 'White', 'Dark'].indexed)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 2 ? 0 : 12),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: [
                                MutColors.paper,
                                Colors.white,
                                MutColors.background,
                              ][i],
                              foregroundColor: i == 2
                                  ? MutColors.text
                                  : MutColors.ink,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => controller.appearance(color: i),
                            child: Text(
                              '$label${controller.pageColor == i ? ' ✓' : ''}',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Typeface'),
                    Text(
                      'Literata',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Text('Text size')),
                    IconButton(
                      tooltip: 'Smaller text',
                      onPressed: () =>
                          controller.appearance(size: controller.fontSize - 1),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('${controller.fontSize.round()} px'),
                    IconButton(
                      tooltip: 'Larger text',
                      onPressed: () =>
                          controller.appearance(size: controller.fontSize + 1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('Line spacing')),
                    for (final (value, label) in [
                      (1.35, 'Compact'),
                      (1.56, 'Relaxed'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: controller.lineHeight == value,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: controller.lineHeight == value
                                ? MutColors.background
                                : MutColors.accent,
                          ),
                          onSelected: (_) =>
                              controller.appearance(height: value),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Saved locally for all EPUB and FB2 books.',
                  style: TextStyle(fontSize: 13, color: MutColors.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() async {
      try {
        await controller.saveAppearance();
      } catch (e) {
        if (context.mounted) showFailure(context, e);
      }
    });
