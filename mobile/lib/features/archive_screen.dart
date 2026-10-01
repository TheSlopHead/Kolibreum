import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'appearance_sheet.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({
    super.key,
    required this.controller,
    required this.onBackup,
    required this.onRestore,
    required this.onPassword,
  });
  final LibraryController controller;
  final VoidCallback onBackup, onRestore, onPassword;
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.32,
        color: MutColors.muted,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const ScreenHeading('Your archive', 'Local · unlocked'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Glass(
          radius: 20,
          child: Row(
            children: [
              const ArchiveMark(size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personal library',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${controller.books.length} books · ${sizeLabel(controller.books.fold(0, (sum, b) => sum + b.size))} on device',
                      style: const TextStyle(
                        fontSize: 13,
                        color: MutColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      _section('LIBRARY & READING'),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: const Icon(Icons.visibility_outlined, color: MutColors.accent),
        title: const Text('Look & feel'),
        subtitle: const Text(
          'Dark theme · glass surfaces',
          style: TextStyle(fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppearance(context, controller),
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: const Icon(Icons.menu_book_outlined, color: MutColors.accent),
        title: const Text('Reading'),
        subtitle: const Text(
          'Literata · progress saved locally',
          style: TextStyle(fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppearance(context, controller),
      ),
      _section('BACKUP & ACCESS'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Glass(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.dns_outlined, color: MutColors.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.backupReport == null
                          ? 'Keep a verified copy'
                          : 'Backup verified',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.backupReport ??
                          'Save an encrypted copy on another device.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: MutColors.accent,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: controller.busy ? null : onBackup,
                          child: const Text('Create a copy'),
                        ),
                        TextButton(
                          onPressed: controller.busy ? null : onRestore,
                          child: const Text('Restore'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: const Icon(Icons.lock_outline, color: MutColors.accent),
        title: const Text('Encryption & access'),
        subtitle: const Text(
          'Change password · auto-lock on background',
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: controller.busy ? null : onPassword,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: OutlinedButton.icon(
          onPressed: () => controller.lock(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('Lock library'),
        ),
      ),
      const SizedBox(height: 96),
    ],
  );
}
