import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;

Uint8List coverPng({int width = 32, int height = 48}) => image.encodePng(
  image.fill(
    image.Image(width: width, height: height),
    color: image.ColorRgb8(180, 40, 120),
  ),
);

Uint8List coverZip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List coverEpub({
  String properties = 'cover-image',
  String metadata = '',
  String href = 'images/cover.png',
  Uint8List? cover,
  bool guide = false,
}) => coverZip({
  'META-INF/container.xml': utf8.encode(
    '<container><rootfiles>'
    '<rootfile full-path="OPS/package.opf"/></rootfiles></container>',
  ),
  'OPS/package.opf': utf8.encode(
    '<package><metadata>$metadata</metadata>'
    '<manifest><item id="cover" href="$href" properties="$properties" '
    'media-type="image/png"/></manifest>'
    '${guide ? '<guide><reference type="cover" href="cover.xhtml"/></guide>' : ''}'
    '</package>',
  ),
  'OPS/cover.xhtml': utf8.encode(
    '<html><body><img src="$href"/></body></html>',
  ),
  'OPS/images/cover.png': cover ?? coverPng(),
});

Uint8List coverFb2({
  Uint8List? cover,
  String href = '#cover',
  String? encoded,
}) => Uint8List.fromList(
  utf8.encode(
    '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" '
    'xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>'
    '<book-title>Embedded cover</book-title><coverpage><image l:href="$href"/>'
    '</coverpage></title-info></description>'
    '<binary id="cover" content-type="image/png">'
    '${encoded ?? base64Encode(cover ?? coverPng())}</binary></FictionBook>',
  ),
);

/// Minimal valid PDF with a colored first page; offsets are calculated, not
/// guessed, so it can also exercise the real PDFium renderer.
Uint8List coverPdf() {
  const drawing = '0.7 0.2 0.4 rg 0 0 200 300 re f\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
        '/Resources << >> /Contents 4 0 R >>',
    '<< /Length ${drawing.length} >>\nstream\n${drawing}endstream',
  ];
  var text = '%PDF-1.4\n';
  final offsets = <int>[0];
  for (final (i, object) in objects.indexed) {
    offsets.add(text.length);
    text += '${i + 1} 0 obj\n$object\nendobj\n';
  }
  final xref = text.length;
  text += 'xref\n0 ${offsets.length}\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    text += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  text +=
      'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n';
  return Uint8List.fromList(ascii.encode(text));
}
