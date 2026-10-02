import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../domain/book.dart';
import '../domain/library_repository.dart';
import 'safe_zip.dart';
import 'book_xml.dart';

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
const _maxBookText = 16 * 1024 * 1024;

String _text(XmlNode node, {int maximum = _maxBookText}) {
  final buffer = StringBuffer();
  int length = 0;
  void visit(XmlNode node) {
    if (node is XmlText) {
      length += node.value.length;
      if (length > maximum) {
        throw const LibraryFailure(
          'limit',
          'Book text exceeds supported limits.',
        );
      }
      buffer.write(node.value);
      return;
    }
    if (node is XmlElement &&
        const [
          'script',
          'style',
          'iframe',
          'object',
          'binary',
        ].contains(node.name.local)) {
      return;
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(node);
  return buffer.toString();
}

class _TextBudget {
  int remaining = _maxBookText;

  List<String> paragraphs(Iterable<XmlElement> elements) {
    final result = <String>[];
    for (final element in elements) {
      final text = _text(element, maximum: remaining).trim();
      remaining -= text.length;
      if (text.isNotEmpty) result.add(text);
    }
    return result;
  }
}

String _first(XmlNode node, String tag) =>
    _elements(node, tag).firstOrNull?.innerText.trim() ?? '';

ReaderDocument decodeBookPayload((Uint8List, String, String) input) =>
    decodeBook(input.$1, input.$2, input.$3);

ReaderDocument decodeBook(Uint8List bytes, String format, String fallback) {
  try {
    return _decodeBook(bytes, format, fallback);
  } on LibraryFailure {
    rethrow;
  } catch (_) {
    throw const LibraryFailure(
      'reader',
      'Cannot decode this book. Its original is preserved and can still be exported.',
    );
  }
}

ReaderDocument _decodeBook(Uint8List bytes, String format, String fallback) {
  final budget = _TextBudget();
  if (format == 'FB2') {
    final xml = parseBookXml(utf8.decode(bytes));
    final body = _elements(xml, 'body').firstOrNull;
    if (body == null) {
      throw const LibraryFailure('reader', 'FB2 body is missing.');
    }
    final chapters = <ReaderChapter>[];
    final sections = body.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'section')
        .toList();
    for (final (i, section) in (sections.isEmpty ? [body] : sections).indexed) {
      final title = _first(section, 'title');
      final paragraphs = budget.paragraphs(
        _elements(section, 'p')
            .where(
              (e) => !e.ancestors.whereType<XmlElement>().any(
                (a) => a.name.local == 'title',
              ),
            )
            .where(
              (e) => !e.ancestors
                  .takeWhile((a) => a != section)
                  .whereType<XmlElement>()
                  .any((a) => a.name.local == 'p'),
            ),
      );
      if (paragraphs.isNotEmpty) {
        chapters.add(
          ReaderChapter(
            section.getAttribute('id') ?? 'section-$i',
            title.isEmpty ? 'Chapter ${i + 1}' : title,
            paragraphs,
          ),
        );
      }
    }
    final title = _first(xml, 'book-title');
    final authorNode = _elements(xml, 'author').firstOrNull;
    final author = authorNode == null
        ? ''
        : ['first-name', 'middle-name', 'last-name']
              .map((n) => _first(authorNode, n))
              .where((n) => n.isNotEmpty)
              .join(' ');
    if (chapters.isEmpty) {
      throw const LibraryFailure('reader', 'No readable text in this FB2.');
    }
    return ReaderDocument(title.isEmpty ? fallback : title, author, chapters);
  }
  if (format != 'EPUB') {
    throw const LibraryFailure(
      'reader',
      'No built-in text reader for this format.',
    );
  }
  final archive = safeZip(bytes);
  final entries = {for (final f in archive.where((f) => f.isFile)) f.name: f};
  String entryText(String name) {
    final file = entries[name];
    if (file == null || file.size > 8 * 1024 * 1024) {
      throw const LibraryFailure('epub', 'Missing or oversized EPUB resource.');
    }
    return utf8.decode(file.readBytes()!);
  }

  final container = parseBookXml(entryText('META-INF/container.xml'));
  final opfPath = _elements(
    container,
    'rootfile',
  ).firstOrNull?.getAttribute('full-path');
  if (opfPath == null) {
    throw const LibraryFailure('epub', 'EPUB package is missing.');
  }
  final package = parseBookXml(entryText(opfPath));
  final manifest = {
    for (final e in _elements(package, 'item')) e.getAttribute('id'): e,
  };
  final chapters = <ReaderChapter>[];
  final visited = <String>{};
  int resources = 0;
  for (final ref in _elements(package, 'itemref')) {
    final item = manifest[ref.getAttribute('idref')];
    if (item == null ||
        item.getAttribute('media-type') != 'application/xhtml+xml') {
      continue;
    }
    final href = Uri.decodeComponent(
      (item.getAttribute('href') ?? '').split('#').first,
    );
    if (Uri.tryParse(href)?.hasScheme == true || href.startsWith('/')) {
      throw const LibraryFailure(
        'epub',
        'External EPUB resources are not allowed.',
      );
    }
    final path = p.posix.normalize(
      p.posix.join(p.posix.dirname(opfPath), href),
    );
    if (path.startsWith('../')) {
      throw const LibraryFailure('epub', 'Unsafe EPUB resource path.');
    }
    if (!visited.add(path)) continue;
    final text = entryText(path);
    resources += text.length;
    if (resources > 32 * 1024 * 1024) {
      throw const LibraryFailure(
        'limit',
        'Reader text exceeds the supported limit.',
      );
    }
    final chapter = parseBookXml(text);
    final body = _elements(chapter, 'body').firstOrNull;
    if (body == null) continue;
    final paragraphs = budget.paragraphs(
      body.descendants
          .whereType<XmlElement>()
          .where((e) => const ['p', 'blockquote', 'li'].contains(e.name.local))
          .where(
            (e) => !e.ancestors
                .takeWhile((a) => a != body)
                .whereType<XmlElement>()
                .any(
                  (a) => const ['p', 'blockquote', 'li'].contains(a.name.local),
                ),
          ),
    );
    final title = [
      'h1',
      'h2',
      'h3',
    ].map((tag) => _first(body, tag)).where((s) => s.isNotEmpty).firstOrNull;
    if (paragraphs.isNotEmpty) {
      chapters.add(
        ReaderChapter(
          path,
          title ?? 'Chapter ${chapters.length + 1}',
          paragraphs,
        ),
      );
    }
  }
  if (chapters.isEmpty) {
    throw const LibraryFailure(
      'reader',
      'This EPUB contains no supported text. DRM and fixed-layout image books are not supported.',
    );
  }
  final title = _first(package, 'title');
  return ReaderDocument(
    title.isEmpty ? fallback : title,
    _first(package, 'creator'),
    chapters,
  );
}
