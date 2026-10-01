import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../app/library_controller.dart';
import '../domain/book.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'appearance_sheet.dart';

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
  late Book book;
  final scroll = ScrollController();
  int chapter = 0, page = 1, totalPages = 1;
  double fraction = 0;
  bool pdfReady = false;
  Timer? saveTimer;
  final pdfController = PdfViewerController();
  @override
  void initState() {
    super.initState();
    book = widget.controller.current!;
    final locator = book.locator.split(':');
    if (locator.length == 2 && locator[0] == 'pdf-v1') {
      page = int.tryParse(locator[1]) ?? 1;
    }
    if (locator.length == 3 && locator[0] == 'text-v1') {
      chapter = (int.tryParse(locator[1]) ?? 0).clamp(
        0,
        (widget.controller.document?.chapters.length ?? 1) - 1,
      );
      fraction = (double.tryParse(locator[2]) ?? 0).clamp(0, 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent * fraction);
        }
      });
    }
    scroll.addListener(_scroll);
    _stage();
  }

  void _scroll() {
    if (!scroll.hasClients) return;
    fraction = scroll.position.maxScrollExtent > 0
        ? (scroll.offset / scroll.position.maxScrollExtent).clamp(0, 1)
        : 0;
    _schedule();
  }

  String get locator => widget.controller.pdf != null
      ? 'pdf-v1:$page'
      : 'text-v1:$chapter:${fraction.toStringAsFixed(5)}';
  double get progress => widget.controller.pdf != null
      ? page / totalPages
      : (chapter + fraction) /
            (widget.controller.document?.chapters.length ?? 1);
  void _schedule() {
    _stage();
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _stage() {
    if (widget.controller.pdf != null && !pdfReady) return;
    widget.controller.stagePosition(book.id, locator, progress);
  }

  Future<void> _save() async {
    if (widget.controller.status != LibraryStatus.unlocked) return;
    if (widget.controller.pdf != null && !pdfReady) return;
    try {
      await widget.controller.position(book.id, locator, progress);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  void _changeChapter(int next) {
    setState(() {
      chapter = next;
      fraction = 0;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    _schedule();
  }

  Future<void> _contents() async {
    final chapters = widget.controller.document?.chapters;
    if (chapters == null) {
      final input = TextEditingController(text: '$page');
      final next = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Page 1–$totalPages'),
          content: TextField(
            controller: input,
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, int.tryParse(input.text)),
              child: const Text('Go'),
            ),
          ],
        ),
      );
      input.dispose();
      if (next != null && next >= 1 && next <= totalPages) {
        await pdfController.goToPage(pageNumber: next);
      }
      return;
    }
    await showModalBottomSheet<void>(
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
              for (final (i, c) in chapters.indexed)
                ListTile(
                  title: Text(c.title),
                  selected: i == chapter,
                  onTap: () {
                    Navigator.pop(context);
                    _changeChapter(i);
                  },
                ),
              for (final mark
                  in (widget.controller.current?.bookmarks ?? <String>[]))
                ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text('Bookmark · $mark'),
                  onTap: () {
                    Navigator.pop(context);
                    final pieces = mark.split(':');
                    if (pieces.length == 3) {
                      _changeChapter(
                        (int.tryParse(pieces[1]) ?? 0).clamp(
                          0,
                          chapters.length - 1,
                        ),
                      );
                      fraction = (double.tryParse(pieces[2]) ?? 0).clamp(0, 1);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (scroll.hasClients) {
                          scroll.jumpTo(
                            scroll.position.maxScrollExtent * fraction,
                          );
                        }
                      });
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    scroll.dispose();
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
                onPressed: () async {
                  await _save();
                  widget.onBack();
                },
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: MutColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SquareAction(
                current.bookmarks.contains(locator)
                    ? Icons.bookmark
                    : Icons.bookmark_outline,
                label: 'Toggle bookmark',
                onPressed: () async {
                  try {
                    await controller.bookmark(current, locator);
                  } catch (e) {
                    if (context.mounted) showFailure(context, e);
                  }
                },
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
                    ? PdfViewer.data(
                        controller.pdf!,
                        sourceName: 'local-encrypted-book',
                        controller: pdfController,
                        initialPageNumber:
                            int.tryParse(
                              book.locator.replaceFirst('pdf-v1:', ''),
                            ) ??
                            1,
                        params: PdfViewerParams(
                          maxImageBytesCachedOnMemory: 32 * 1024 * 1024,
                          linkHandlerParams: PdfLinkHandlerParams(
                            enableAutoLinkDetection: false,
                            onLinkTap: (_) {},
                          ),
                          onDocumentChanged: (document) {
                            if (mounted) {
                              setState(() {
                                totalPages = document?.pages.length ?? 1;
                                page = page.clamp(1, totalPages);
                                pdfReady = document != null;
                              });
                              _stage();
                            }
                          },
                          onPageChanged: (number) {
                            if (number != null && mounted) {
                              setState(() => page = number);
                              _schedule();
                            }
                          },
                        ),
                      )
                    : SingleChildScrollView(
                        controller: scroll,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CHAPTER ${(chapter + 1).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.8,
                                color: ink.withValues(alpha: .7),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              controller.document!.chapters[chapter].title,
                              style: TextStyle(
                                fontFamily: 'Literata',
                                fontSize: 26,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: 88,
                              height: 2,
                              color: ink.withValues(alpha: .2),
                            ),
                            const SizedBox(height: 20),
                            for (final paragraph
                                in controller
                                    .document!
                                    .chapters[chapter]
                                    .paragraphs)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Text(
                                  paragraph,
                                  style: TextStyle(
                                    fontFamily: 'Literata',
                                    fontSize: controller.fontSize,
                                    height: controller.lineHeight,
                                    color: ink,
                                  ),
                                ),
                              ),
                            if (chapter + 1 <
                                controller.document!.chapters.length)
                              TextButton(
                                onPressed: () => _changeChapter(chapter + 1),
                                child: const Text('Next chapter →'),
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SquareAction(
                Icons.format_list_bulleted,
                label: 'Contents and bookmarks',
                onPressed: _contents,
              ),
              Text(
                controller.pdf != null
                    ? '$page / $totalPages'
                    : 'Chapter ${chapter + 1} / ${controller.document!.chapters.length}',
                style: const TextStyle(fontSize: 13, color: MutColors.accent),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: MutColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: controller.pdf == null
                      ? () => showAppearance(context, controller)
                      : () => pdfController.zoomUp(),
                  child: Text(
                    controller.pdf == null ? 'Aa' : '+',
                    style: const TextStyle(fontSize: 18, color: MutColors.text),
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
