import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/book.dart';

enum FragmentKind { label, title, divider, body }

TextStyle readerStyle(FragmentKind kind, double size, double height) =>
    switch (kind) {
      FragmentKind.label => const TextStyle(
        inherit: false,
        fontFamily: 'Onest',
        fontSize: 10,
        height: 1.5,
        letterSpacing: 1.8,
      ),
      FragmentKind.title => const TextStyle(
        inherit: false,
        fontFamily: 'Literata',
        fontSize: 26,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      _ => TextStyle(
        inherit: false,
        fontFamily: 'Literata',
        fontSize: size,
        height: height,
      ),
    };

class TextFragment {
  const TextFragment(this.text, this.kind, this.gap);
  final String text;
  final FragmentKind kind;
  final double gap;
}

class TextReaderPage {
  const TextReaderPage(this.chapter, this.offset, this.fragments);
  final int chapter, offset;
  final List<TextFragment> fragments;
  String get locator => 'text-v2:$chapter:$offset';
}

/// Measures bounded pieces and yields between batches. Only page descriptors
/// are retained: widgets and paragraphs are laid out lazily by the reader.
Future<List<TextReaderPage>> paginateText(
  ReaderDocument document, {
  required Size size,
  required double fontSize,
  required double lineHeight,
  required TextScaler scaler,
  required TextDirection direction,
  required bool Function() cancelled,
}) async {
  final pages = <TextReaderPage>[];
  final stopwatch = Stopwatch()..start();
  final width = math.max(1.0, size.width - 48);
  final pageHeight = math.max(1.0, size.height - 48);
  for (final (chapterIndex, chapter) in document.chapters.indexed) {
    var fragments = <TextFragment>[];
    var used = 0.0;
    var pageOffset = 0;
    void flush() {
      if (fragments.isEmpty) return;
      pages.add(TextReaderPage(chapterIndex, pageOffset, fragments));
      fragments = [];
      used = 0;
    }

    var paragraphOffset = 0;
    final blocks = <(String, FragmentKind, double)>[
      (
        'CHAPTER ${(chapterIndex + 1).toString().padLeft(2, '0')}',
        FragmentKind.label,
        14,
      ),
      (chapter.title, FragmentKind.title, 20),
      ('', FragmentKind.divider, 20),
      for (final paragraph in chapter.paragraphs)
        (paragraph, FragmentKind.body, 20),
    ];
    for (final (text, kind, gap) in blocks) {
      if (cancelled()) return [];
      if (kind == FragmentKind.divider) {
        if (used + 2 > pageHeight) flush();
        fragments.add(TextFragment('', kind, gap));
        used += 2 + gap;
        continue;
      }
      var start = 0;
      while (start < text.length) {
        if (cancelled()) return [];
        // Never shape a whole oversized paragraph in one frame.
        var end = math.min(start + 2048, text.length);
        if (end < text.length) {
          final space = text.substring(start, end).lastIndexOf(' ');
          if (space > 1024) end = start + space + 1;
          final unit = text.codeUnitAt(end - 1);
          if (unit >= 0xD800 && unit <= 0xDBFF) end--;
        }
        final piece = text.substring(start, end);
        final painter = TextPainter(
          text: TextSpan(
            text: piece,
            style: readerStyle(kind, fontSize, lineHeight),
          ),
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: width);
        final lines = painter.computeLineMetrics();
        final available = pageHeight - used;
        var fitting = 0;
        var fittingHeight = 0.0;
        for (final line in lines) {
          if (fittingHeight + line.height > available + .01) break;
          fittingHeight += line.height;
          fitting++;
        }
        if (fitting == 0 && fragments.isNotEmpty) {
          painter.dispose();
          flush();
          continue;
        }
        fitting = math.max(1, fitting);
        final last = lines[math.min(fitting, lines.length) - 1];
        final cut = fitting >= lines.length
            ? piece.length
            : painter
                  .getLineBoundary(
                    painter.getPositionForOffset(Offset(0, last.baseline)),
                  )
                  .end;
        final consumed = math.max(1, cut);
        if (fragments.isEmpty) {
          pageOffset =
              paragraphOffset + (kind == FragmentKind.body ? start : 0);
        }
        final complete = start + consumed == text.length;
        fragments.add(
          TextFragment(piece.substring(0, consumed), kind, complete ? gap : 0),
        );
        used +=
            (fittingHeight > 0 ? fittingHeight : last.height) +
            (complete ? gap : 0);
        start += consumed;
        painter.dispose();
        if (fitting < lines.length) flush();
        if (stopwatch.elapsedMilliseconds >= 4) {
          await Future<void>.delayed(Duration.zero);
          stopwatch.reset();
        }
      }
      if (kind == FragmentKind.body) paragraphOffset += text.length + 2;
    }
    flush();
  }
  return pages;
}

int pageForLocator(List<TextReaderPage> pages, String locator) {
  if (pages.isEmpty) return 0;
  final parts = locator.split(':');
  if (parts.length != 3) return 0;
  final chapter = int.tryParse(parts[1]) ?? 0;
  final first = pages.indexWhere((page) => page.chapter == chapter);
  if (first < 0) return 0;
  final count = pages.where((page) => page.chapter == chapter).length;
  if (parts[0] == 'text-v1') {
    final fraction = double.tryParse(parts[2]) ?? 0;
    return first +
        (fraction.isFinite ? (fraction.clamp(0, 1) * (count - 1)).round() : 0);
  }
  if (parts[0] != 'text-v2') return 0;
  final offset = int.tryParse(parts[2]) ?? 0;
  if (offset <= 0) return first;
  var index = first;
  for (var i = first; i < first + count; i++) {
    if (pages[i].offset > offset) break;
    index = i;
  }
  return index;
}
