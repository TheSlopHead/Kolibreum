import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/book_decoder.dart';
import 'package:mut_mobile/data/safe_zip.dart';
import 'package:mut_mobile/domain/library_repository.dart';

Uint8List zip(Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final data = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('FB2 metadata and chapters use text only', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '<FictionBook><description><title-info><book-title>Test</book-title><author><first-name>Mira</first-name><last-name>Holm</last-name></author></title-info></description><body><section id="one"><title><p>Chapter one</p></title><p>Calm <emphasis>words</emphasis>.</p><p><script>hidden()</script>Visible.</p></section></body></FictionBook>',
      ),
    );
    final d = decodeBook(bytes, 'FB2', 'fallback');
    expect(d.title, 'Test');
    expect(d.author, 'Mira Holm');
    expect(d.chapters.single.id, 'one');
    expect(d.chapters.single.paragraphs.join(), contains('Calm words.'));
    expect(d.chapters.single.paragraphs.join(), isNot(contains('hidden()')));
  });
  test('EPUB follows OPF spine and never executes HTML', () {
    final data = zip({
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
      'OPS/book.opf':
          '<package><metadata><title>Title</title><creator>Author</creator></metadata><manifest><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>',
      'OPS/one.xhtml':
          '<html><body><h1>First</h1><p>One<script>alert(1)</script></p><img src="https://example.com/track"/></body></html>',
      'OPS/two.xhtml': '<html><body><h1>Second</h1><p>Two</p></body></html>',
    });
    final d = decodeBook(data, 'EPUB', 'fallback');
    expect(d.chapters.map((c) => c.title), ['First', 'Second']);
    expect(d.chapters.first.paragraphs, ['One']);
  });
  test(
    'DTD, entities, path traversal, duplicate entries and expansion bombs rejected',
    () {
      expect(
        () => decodeBook(
          Uint8List.fromList(
            utf8.encode(
              '<!DOCTYPE x [<!ENTITY a SYSTEM "file:///secret">]><FictionBook/>',
            ),
          ),
          'FB2',
          'x',
        ),
        throwsA(isA<LibraryFailure>()),
      );
      expect(
        () => safeZip(zip({'../outside': 'secret'})),
        throwsA(isA<LibraryFailure>()),
      );
      expect(
        () => safeZip(zip({'book': 'a' * 4096}), maxBytes: 2048),
        throwsA(isA<LibraryFailure>()),
      );
      final duplicate = zip({'aaaa': 'first', 'bbbb': 'second'});
      final directory = ByteData.sublistView(duplicate);
      for (int i = 0; i + 50 < duplicate.length; i++) {
        if (directory.getUint32(i, Endian.little) == 0x02014b50 &&
            utf8.decode(duplicate.sublist(i + 46, i + 50)) == 'bbbb') {
          duplicate.setRange(i + 46, i + 50, utf8.encode('aaaa'));
          break;
        }
      }
      expect(() => safeZip(duplicate), throwsA(isA<LibraryFailure>()));
    },
  );
  test('dishonest expanded size and corrupt CRC are rejected', () {
    final bomb = zip({'book': 'a' * 65536});
    final corrupt = zip({'book': 'valid content'});
    for (final bytes in [bomb, corrupt]) {
      final data = ByteData.sublistView(bytes);
      for (int i = 0; i + 46 < bytes.length; i++) {
        if (data.getUint32(i, Endian.little) == 0x02014b50) {
          if (identical(bytes, bomb)) {
            data.setUint32(i + 24, 1, Endian.little);
          } else {
            data.setUint32(i + 16, 0, Endian.little);
          }
          break;
        }
      }
      expect(() => safeZip(bytes), throwsA(isA<LibraryFailure>()));
    }
  });
}
