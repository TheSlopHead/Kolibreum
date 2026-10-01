import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../domain/book.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class BookDetails extends StatelessWidget {
  const BookDetails({
    super.key,
    required this.book,
    required this.controller,
    required this.onBack,
    required this.onRead,
    required this.onExport,
  });
  final Book book;
  final LibraryController controller;
  final VoidCallback onBack, onRead, onExport;
  Future<void> _shelf(BuildContext context) async {
    final text = TextEditingController(text: book.shelves.firstOrNull ?? '');
    final shelf = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to shelf'),
        content: TextField(
          controller: text,
          decoration: const InputDecoration(
            hintText: 'Shelf name (empty to remove)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    text.dispose();
    if (shelf == null || !context.mounted) return;
    try {
      await controller.task(() async {
        await controller.repository.update(book.id, {
          'shelves': shelf.isEmpty ? <String>[] : [shelf],
        });
        await controller.refresh();
      });
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _edit(BuildContext context) async {
    final title = TextEditingController(text: book.title),
        author = TextEditingController(text: book.author);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Book details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: author,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final changes = <String, dynamic>{
      'title': title.text.trim(),
      'author': author.text.trim(),
      'metadata_read': true,
    };
    title.dispose();
    author.dispose();
    if (saved != true || !context.mounted || changes['title']!.isEmpty) return;
    try {
      await controller.task(() async {
        await controller.repository.update(book.id, changes);
        await controller.refresh();
      });
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    children: [
      Row(
        children: [
          SquareAction(Icons.arrow_back, label: 'All books', onPressed: onBack),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Book details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          SquareAction(
            Icons.more_horiz,
            label: 'Edit book details',
            onPressed: controller.busy ? null : () => _edit(context),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Center(child: SizedBox(width: 210, height: 268, child: BookCover(book))),
      const SizedBox(height: 24),
      Text(book.title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(
        book.author.isEmpty ? 'Unknown author' : book.author,
        style: const TextStyle(color: MutColors.accent, fontSize: 16),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in [
            book.format,
            sizeLabel(book.size),
            ...book.shelves,
          ])
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              radius: 10,
              child: Text(
                tag,
                style: const TextStyle(color: MutColors.accent, fontSize: 12),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Your reading',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            '${(book.progress * 100).round()}%',
            style: const TextStyle(color: MutColors.accent),
          ),
        ],
      ),
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: book.progress,
        minHeight: 4,
        borderRadius: BorderRadius.circular(4),
        backgroundColor: MutColors.raised,
        color: MutColors.accent,
      ),
      const SizedBox(height: 12),
      Text(
        book.locator.isEmpty
            ? 'Not started'
            : 'Last position saved on this device',
        style: const TextStyle(color: MutColors.muted, fontSize: 13),
      ),
      if (!book.readable) ...[
        const SizedBox(height: 24),
        const Text(
          'No built-in reading',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your original is preserved. Export it to open in another app.',
          style: TextStyle(color: MutColors.muted),
        ),
      ],
      const SizedBox(height: 40),
      if (book.readable)
        FilledButton.icon(
          onPressed: controller.busy ? null : onRead,
          icon: const Icon(Icons.arrow_forward),
          label: Text(
            book.progress == 0 ? 'Start reading' : 'Continue reading',
          ),
        ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: controller.busy ? null : () => _shelf(context),
            child: const Text('Move to shelf'),
          ),
          TextButton(
            onPressed: controller.busy ? null : onExport,
            child: const Text('Export original'),
          ),
        ],
      ),
    ],
  );
}
