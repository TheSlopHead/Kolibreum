import 'dart:async';
import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../domain/book.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'appearance_sheet.dart';
import 'reader/pdf_reader.dart';
import 'reader/text_reader.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final LibraryController controller;
  final VoidCallback onBack;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final Book book = widget.controller.current!;
  final textReader = GlobalKey<TextReaderState>();
  final pdfReader = GlobalKey<PdfReaderState>();
  final position = ValueNotifier<(String, int, int)?>(null);
  Timer? saveTimer;
  bool saving = false;
  (String, int, int)? savedPosition;

  double get progress => position.value == null
      ? book.progress
      : position.value!.$2 / position.value!.$3;

  void _position(String locator, int page, int total) {
    final next = (locator, page, total);
    if (position.value == next) return;
    position.value = next;
    widget.controller.stagePosition(book.id, locator, progress);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    final current = position.value;
    if (saving ||
        current == null ||
        savedPosition == current ||
        widget.controller.status != LibraryStatus.unlocked) {
      return;
    }
    saving = true;
    try {
      await widget.controller.position(
        book.id,
        current.$1,
        current.$2 / current.$3,
      );
      savedPosition = current;
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      saving = false;
      if (mounted && position.value != current) {
        saveTimer?.cancel();
        saveTimer = Timer(const Duration(milliseconds: 600), _save);
      }
    }
  }

  Future<void> _goToPage() async {
    final current = position.value;
    if (current == null) return;
    final input = TextEditingController(text: '${current.$2}');
    final next = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Page 1–${current.$3}'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || next == null || next < 1 || next > current.$3) return;
    textReader.currentState?.goToPage(next);
    await pdfReader.currentState?.goToPage(next);
  }

  String _bookmarkLabel(String mark) {
    final parts = mark.split(':');
    if (parts.firstOrNull == 'pdf-v1') return 'Page ${parts.last}';
    return 'Chapter ${(int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0) + 1}';
  }

  Future<void> _contents() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .6,
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Contents & bookmarks',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.numbers),
              title: const Text('Go to page'),
              onTap: () {
                Navigator.pop(context);
                _goToPage();
              },
            ),
            for (final (i, chapter)
                in (widget.controller.document?.chapters ?? <ReaderChapter>[])
                    .indexed)
              ListTile(
                title: Text(chapter.title),
                onTap: () {
                  Navigator.pop(context);
                  textReader.currentState?.goToLocator('text-v2:$i:0');
                },
              ),
            for (final mark
                in widget.controller.current?.bookmarks ?? <String>[])
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text('Bookmark · ${_bookmarkLabel(mark)}'),
                onTap: () {
                  Navigator.pop(context);
                  textReader.currentState?.goToLocator(mark);
                  if (mark.startsWith('pdf-v1:')) {
                    pdfReader.currentState?.goToPage(
                      int.tryParse(mark.split(':').last) ?? 1,
                    );
                  }
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    saveTimer?.cancel();
    position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final paper = [
      MutColors.paper,
      Colors.white,
      MutColors.background,
    ][controller.pageColor];
    final ink = controller.pageColor == 2 ? MutColors.text : MutColors.ink;
    final current = controller.current ?? book;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              SquareAction(
                Icons.arrow_back,
                label: 'Back to book',
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      current.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      current.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MutColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder(
                valueListenable: position,
                builder: (context, value, _) => SquareAction(
                  current.bookmarks.contains(value?.$1)
                      ? Icons.bookmark
                      : Icons.bookmark_outline,
                  label: 'Toggle bookmark',
                  onPressed: value == null
                      ? null
                      : () async {
                          try {
                            await controller.bookmark(
                              controller.current ?? book,
                              value.$1,
                            );
                          } catch (e) {
                            if (context.mounted) showFailure(context, e);
                          }
                        },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ColoredBox(
                color: paper,
                child: controller.pdf != null
                    ? PdfReader(
                        key: pdfReader,
                        bytes: controller.pdf!,
                        bookId: book.id,
                        initialPage:
                            int.tryParse(
                              book.locator.replaceFirst('pdf-v1:', ''),
                            ) ??
                            1,
                        paginated: controller.paginated,
                        onPosition: _position,
                      )
                    : TextReader(
                        key: textReader,
                        document: controller.document!,
                        fontSize: controller.fontSize,
                        lineHeight: controller.lineHeight,
                        ink: ink,
                        paginated: controller.paginated,
                        initialLocator: book.locator,
                        onPosition: _position,
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            children: [
              SquareAction(
                Icons.format_list_bulleted,
                label: 'Contents and bookmarks',
                onPressed: _contents,
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: position,
                  builder: (context, value, _) => TextButton(
                    onPressed: value == null ? null : _goToPage,
                    child: Text(
                      value == null
                          ? 'Preparing pages…'
                          : '${value.$2} / ${value.$3} · ${(progress * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 13,
                        color: MutColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: MutColors.surface,
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: MutColors.edge),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => showAppearance(context, controller),
                  child: const Text(
                    'Aa',
                    style: TextStyle(fontSize: 18, color: MutColors.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
