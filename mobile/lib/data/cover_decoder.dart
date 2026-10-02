import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'book_xml.dart';
import 'safe_zip.dart';

const maxCoverSourceBytes = 4 * 1024 * 1024;
const maxCoverThumbnailBytes = 512 * 1024;
const coverThumbnailWidth = 512;
const coverThumbnailHeight = 768;

/// Optional derived data: a missing, damaged or unsupported cover never prevents
/// preserving the original. Called on the archive's worker isolate, without IO.
Uint8List? extractBookCover(Uint8List original, String format) {
  try {
    if (format == 'FB2') return _fb2Cover(original);
    if (format == 'EPUB') return _epubCover(original);
  } catch (_) {
    // A malformed book is still importable/exportable, just without a cover.
  }
  return null;
}

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);

Uint8List? _fb2Cover(Uint8List bytes) {
  final xml = parseBookXml(utf8.decode(bytes));
  final description = _elements(xml, 'description').firstOrNull;
  final titleInfo = description == null
      ? null
      : _elements(description, 'title-info').firstOrNull;
  final cover = titleInfo == null
      ? null
      : _elements(titleInfo, 'coverpage').firstOrNull;
  if (cover == null) return null;
  for (final element in _elements(cover, 'image')) {
    final href =
        element.getAttribute(
          'href',
          namespace: 'http://www.w3.org/1999/xlink',
        ) ??
        element.getAttribute('href');
    if (href == null || !href.startsWith('#') || href.length < 2) continue;
    final binary = _elements(
      xml,
      'binary',
    ).where((e) => e.getAttribute('id') == href.substring(1)).firstOrNull;
    if (binary == null) continue;
    final encoded = binary.innerText.replaceAll(RegExp(r'\s'), '');
    if (encoded.length > ((maxCoverSourceBytes + 2) ~/ 3) * 4) continue;
    try {
      final decoded = base64Decode(encoded);
      try {
        final thumbnail = makeCoverThumbnail(decoded);
        if (thumbnail != null) return thumbnail;
      } finally {
        decoded.fillRange(0, decoded.length, 0);
      }
    } catch (_) {
      // A second image in coverpage may still be usable.
    }
  }
  return null;
}

String? _localPath(String base, String href) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final path = Uri.decodeComponent(uri.path);
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) return null;
  final resolved = p.posix.normalize(p.posix.join(p.posix.dirname(base), path));
  if (resolved == '..' || resolved.startsWith('../')) return null;
  return resolved;
}

Uint8List? _epubCover(Uint8List bytes) {
  final entries = {
    for (final f in safeZip(
      bytes,
      maxBytes: 64 * 1024 * 1024,
      maxEntries: 4096,
    ))
      if (f.isFile) f.name: f,
  };
  XmlDocument xmlEntry(String path) {
    final entry = entries[path];
    if (entry == null || entry.size > 8 * 1024 * 1024) {
      throw const FormatException('Missing or oversized EPUB metadata.');
    }
    return parseBookXml(utf8.decode(entry.readBytes()!));
  }

  final container = xmlEntry('META-INF/container.xml');
  final opfPath = _elements(
    container,
    'rootfile',
  ).firstOrNull?.getAttribute('full-path');
  if (opfPath == null) return null;
  final package = xmlEntry(opfPath);
  final manifestNode = _elements(package, 'manifest').firstOrNull;
  if (manifestNode == null) return null;
  final manifest = {
    for (final e in _elements(manifestNode, 'item')) e.getAttribute('id'): e,
  };
  final paths = <String>{};
  void addItem(XmlElement? item) {
    final href = item?.getAttribute('href');
    if (href == null) return;
    final path = _localPath(opfPath, href);
    if (path != null) paths.add(path);
  }

  // EPUB 3 properties is a whitespace-separated set, not a single value.
  for (final item in manifest.values) {
    if ((item.getAttribute('properties') ?? '')
        .split(RegExp(r'\s+'))
        .contains('cover-image')) {
      addItem(item);
    }
  }
  // EPUB 2's conventional metadata points to a manifest ID, not a filename.
  for (final meta in _elements(package, 'meta')) {
    if (meta.getAttribute('name') == 'cover') {
      addItem(manifest[meta.getAttribute('content')]);
    }
  }
  // Older books may declare a cover XHTML page in the guide.
  for (final ref in _elements(package, 'reference')) {
    if (ref.getAttribute('type') != 'cover') continue;
    final path = _localPath(opfPath, ref.getAttribute('href') ?? '');
    if (path == null) continue;
    final file = entries[path];
    if (file == null) continue;
    if (path.toLowerCase().endsWith('.xhtml') ||
        path.toLowerCase().endsWith('.html')) {
      try {
        for (final img in _elements(xmlEntry(path), 'img')) {
          final imgPath = _localPath(path, img.getAttribute('src') ?? '');
          if (imgPath != null) paths.add(imgPath);
        }
      } catch (_) {
        // Keep any other declared cover candidates.
      }
    } else {
      paths.add(path);
    }
  }
  for (final path in paths) {
    final ArchiveFile? entry = entries[path];
    if (entry == null || entry.size > maxCoverSourceBytes) continue;
    final thumbnail = makeCoverThumbnail(entry.readBytes()!);
    if (thumbnail != null) return thumbnail;
  }
  return null;
}

bool _allowedSize(int width, int height) =>
    width > 0 &&
    height > 0 &&
    width <= 4096 &&
    height <= 4096 &&
    width * height <= 8 * 1024 * 1024;

/// Check JPEG dimensions *before* the image package allocates DCT blocks.
bool _boundedJpeg(Uint8List bytes) {
  int offset = 2;
  bool frame = false;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset++] != 0xff) return false;
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset + 3 > bytes.length) return false;
    final marker = bytes[offset++];
    if (marker == 0xda) return frame;
    final length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) return false;
    if (marker >= 0xc0 &&
        marker <= 0xcf &&
        marker != 0xc4 &&
        marker != 0xc8 &&
        marker != 0xcc) {
      if (frame || ![0xc0, 0xc1, 0xc2].contains(marker) || length < 8) {
        return false;
      }
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      final components = bytes[offset + 7];
      if (!_allowedSize(width, height) ||
          components < 1 ||
          components > 4 ||
          length != 8 + 3 * components) {
        return false;
      }
      int blocks = 0;
      for (int i = 0; i < components; i++) {
        final sampling = bytes[offset + 9 + i * 3];
        final horizontal = sampling >> 4, vertical = sampling & 15;
        if (horizontal < 1 || horizontal > 4 || vertical < 1 || vertical > 4) {
          return false;
        }
        blocks += horizontal * vertical;
      }
      if (blocks > 10) return false;
      frame = true;
    }
    offset += length;
  }
  return false;
}

/// Only bounded raster PNG/JPEG are decoded. SVG, animation and unknown types
/// fall back to the text card. Re-encoding strips source metadata.
Uint8List? makeCoverThumbnail(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > maxCoverSourceBytes) return null;
  try {
    image.Image? decoded;
    if (bytes.length >= 24 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      final header = ByteData.sublistView(bytes);
      if (!_allowedSize(header.getUint32(16), header.getUint32(20))) {
        return null;
      }
      final decoder = image.PngDecoder();
      final info = decoder.startDecode(bytes);
      if (info == null ||
          info.numFrames != 1 ||
          !_allowedSize(info.width, info.height)) {
        return null;
      }
      decoded = decoder.decodeFrame(0);
    } else if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      if (!_boundedJpeg(bytes)) return null;
      decoded = image.decodeJpg(bytes);
    }
    if (decoded == null) return null;
    final oriented = image.bakeOrientation(decoded);
    final scale = math.min(
      1.0,
      math.min(
        coverThumbnailWidth / oriented.width,
        coverThumbnailHeight / oriented.height,
      ),
    );
    final resized =
        image.copyResize(
            oriented,
            width: math.max(1, (oriented.width * scale).round()),
            height: math.max(1, (oriented.height * scale).round()),
            interpolation: image.Interpolation.average,
          )
          ..exif = image.ExifData()
          ..iccProfile = null
          ..textData = null;
    final encoded = image.encodeJpg(resized, quality: 85);
    return encoded.length <= maxCoverThumbnailBytes ? encoded : null;
  } catch (_) {
    return null;
  }
}
