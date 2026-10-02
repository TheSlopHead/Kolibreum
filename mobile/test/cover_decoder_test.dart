import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mut_mobile/data/book_decoder.dart';
import 'package:mut_mobile/data/cover_decoder.dart';
import 'support/cover_fixtures.dart';

void main() {
  test('EPUB 3 cover extraction works without readable chapters', () {
    final original = coverEpub(properties: 'foo cover-image bar');
    expect(() => decodeBook(original, 'EPUB', 'title'), throwsException);
    final cover = extractBookCover(original, 'EPUB')!;
    final decoded = image.decodeJpg(cover)!;
    expect((decoded.width, decoded.height), (32, 48));
    expect(decoded.getPixel(0, 0).r, closeTo(180, 5));
  });
  test('EPUB 2 metadata and guide XHTML resolve their declared image', () {
    for (final original in [
      coverEpub(
        properties: '',
        metadata: '<meta name="cover" content="cover"/>',
      ),
      coverEpub(properties: '', guide: true),
    ]) {
      expect(extractBookCover(original, 'EPUB'), isNotNull);
    }
    final encodedPath = coverZip({
      'META-INF/container.xml': utf8.encode(
        '<container><rootfile full-path="OPS/book.opf"/></container>',
      ),
      'OPS/book.opf': utf8.encode(
        '<package><manifest><item id="cover" '
        'href="images/my%20cover.png" properties="cover-image"/></manifest></package>',
      ),
      'OPS/images/my cover.png': coverPng(),
    });
    expect(extractBookCover(encodedPath, 'EPUB'), isNotNull);
  });
  test('FB2 resolves namespaced cover references and whitespace in base64', () {
    final encoded = base64Encode(coverPng());
    final spaced = '${encoded.substring(0, 20)}\n ${encoded.substring(20)}';
    expect(extractBookCover(coverFb2(encoded: spaced), 'FB2'), isNotNull);
    expect(extractBookCover(coverFb2(href: '#missing'), 'FB2'), isNull);
  });
  test('missing, corrupt, external and escaping covers use the fallback', () {
    for (final href in [
      'https://example.com/cover.png',
      '//example.com/cover.png',
      '../../cover.png',
      '%2E%2E/%2E%2E/cover.png',
    ]) {
      expect(extractBookCover(coverEpub(href: href), 'EPUB'), isNull);
    }
    expect(extractBookCover(coverEpub(properties: ''), 'EPUB'), isNull);
    expect(
      extractBookCover(coverEpub(cover: Uint8List.fromList([1, 2, 3])), 'EPUB'),
      isNull,
    );
    expect(extractBookCover(coverFb2(encoded: 'bad base64!'), 'FB2'), isNull);
    expect(
      extractBookCover(coverFb2(href: 'https://example.com/cover'), 'FB2'),
      isNull,
    );
    expect(
      extractBookCover(
        Uint8List.fromList(
          utf8.encode(
            '<!DOCTYPE x [<!ENTITY a SYSTEM "file:///secret">]><FictionBook/>',
          ),
        ),
        'FB2',
      ),
      isNull,
    );
    expect(extractBookCover(coverPng(), 'FILE'), isNull);
  });
  test('PNG and JPEG are bounded and resized before thumbnail storage', () {
    final png = coverPng(width: 1024, height: 1536);
    final thumb = image.decodeJpg(makeCoverThumbnail(png)!)!;
    expect((thumb.width, thumb.height), (512, 768));
    final jpg = image.encodeJpg(image.decodePng(png)!);
    expect(makeCoverThumbnail(jpg), isNotNull);
    final hugePng = coverPng();
    ByteData.sublistView(hugePng).setUint32(16, 100000);
    expect(makeCoverThumbnail(hugePng), isNull);
    final hugeJpg = Uint8List.fromList(jpg);
    for (int i = 0; i + 9 < hugeJpg.length; i++) {
      if (hugeJpg[i] == 0xff && [0xc0, 0xc1, 0xc2].contains(hugeJpg[i + 1])) {
        ByteData.sublistView(hugeJpg).setUint16(i + 7, 65535);
        break;
      }
    }
    expect(makeCoverThumbnail(hugeJpg), isNull);
    expect(makeCoverThumbnail(Uint8List(maxCoverSourceBytes + 1)), isNull);
    expect(
      makeCoverThumbnail(Uint8List.fromList(utf8.encode('<svg/>'))),
      isNull,
    );
  });
}
