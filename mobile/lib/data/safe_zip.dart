import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../domain/library_repository.dart';

/// Validate both directories, then inflate with an enforced output ceiling.
/// Never trust a ZIP's declared size or a decoder's optional CRC verification.
Archive safeZip(
  Uint8List bytes, {
  int maxBytes = 64 * 1024 * 1024,
  int maxEntries = 2048,
}) {
  if (bytes.length < 22 || bytes.length > maxBytes) {
    throw const LibraryFailure(
      'limit',
      'Archive is empty or exceeds the size limit.',
    );
  }
  final d = ByteData.sublistView(bytes);
  int end = -1;
  for (int i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
    if (d.getUint32(i, Endian.little) == 0x06054b50 &&
        i + 22 + d.getUint16(i + 20, Endian.little) == bytes.length) {
      end = i;
      break;
    }
  }
  if (end < 0) throw const LibraryFailure('zip', 'Invalid ZIP directory.');
  final count = d.getUint16(end + 10, Endian.little);
  final directorySize = d.getUint32(end + 12, Endian.little);
  var offset = d.getUint32(end + 16, Endian.little);
  final directoryStart = offset;
  if (count > maxEntries ||
      count == 0xffff ||
      d.getUint16(end + 8, Endian.little) != count ||
      d.getUint16(end + 4, Endian.little) != 0 ||
      d.getUint16(end + 6, Endian.little) != 0 ||
      offset + directorySize != end) {
    throw const LibraryFailure(
      'limit',
      'Unsupported ZIP64, split archive or too many entries.',
    );
  }
  int total = 0;
  final names = <String>{};
  final entries =
      <
        ({
          String name,
          int start,
          int data,
          int compressed,
          int size,
          int method,
          int crc,
        })
      >[];
  for (int n = 0; n < count; n++) {
    if (offset + 46 > end || d.getUint32(offset, Endian.little) != 0x02014b50) {
      throw const LibraryFailure('zip', 'Invalid ZIP entry.');
    }
    final size = d.getUint32(offset + 24, Endian.little);
    final compressed = d.getUint32(offset + 20, Endian.little);
    final flags = d.getUint16(offset + 8, Endian.little);
    final method = d.getUint16(offset + 10, Endian.little);
    final local = d.getUint32(offset + 42, Endian.little);
    final nameLen = d.getUint16(offset + 28, Endian.little);
    final next =
        offset +
        46 +
        nameLen +
        d.getUint16(offset + 30, Endian.little) +
        d.getUint16(offset + 32, Endian.little);
    if (next > end ||
        size == 0xffffffff ||
        compressed == 0xffffffff ||
        d.getUint16(offset + 34, Endian.little) != 0 ||
        (flags & 0x41) != 0 ||
        (method != 0 && method != 8) ||
        (d.getUint32(offset + 38, Endian.little) >> 16 & 0xf000) == 0xa000) {
      throw const LibraryFailure('zip', 'Encrypted or invalid ZIP entry.');
    }
    final name = utf8.decode(bytes.sublist(offset + 46, offset + 46 + nameLen));
    if (name.isEmpty ||
        name.contains(':') ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').contains('..') ||
        name.contains('\u0000') ||
        !names.add(name)) {
      throw const LibraryFailure('zip', 'Unsafe or duplicate archive path.');
    }
    total += size;
    if (total > maxBytes) {
      throw const LibraryFailure(
        'limit',
        'Expanded archive exceeds the size limit.',
      );
    }
    if (local + 30 > directoryStart ||
        d.getUint32(local, Endian.little) != 0x04034b50 ||
        d.getUint16(local + 6, Endian.little) != flags ||
        d.getUint16(local + 8, Endian.little) != method) {
      throw const LibraryFailure('zip', 'Invalid ZIP local header.');
    }
    final localNameLength = d.getUint16(local + 26, Endian.little);
    final data =
        local + 30 + localNameLength + d.getUint16(local + 28, Endian.little);
    if (data + compressed > directoryStart ||
        utf8.decode(bytes.sublist(local + 30, local + 30 + localNameLength)) !=
            name) {
      throw const LibraryFailure('zip', 'Invalid ZIP file bounds.');
    }
    entries.add((
      name: name,
      start: local,
      data: data,
      compressed: compressed,
      size: size,
      method: method,
      crc: d.getUint32(offset + 16, Endian.little),
    ));
    offset = next;
  }
  if (offset != end) {
    throw const LibraryFailure('zip', 'Invalid ZIP directory size.');
  }
  final sorted = [...entries]..sort((a, b) => a.start.compareTo(b.start));
  for (int i = 1; i < sorted.length; i++) {
    if (sorted[i].start < sorted[i - 1].data + sorted[i - 1].compressed) {
      throw const LibraryFailure('zip', 'Overlapping ZIP entries.');
    }
  }
  final result = Archive();
  for (final entry in entries) {
    final compressed = Uint8List.sublistView(
      bytes,
      entry.data,
      entry.data + entry.compressed,
    );
    final output = _BoundedSink(entry.size);
    try {
      if (entry.method == 0) {
        output.add(compressed);
      } else {
        final decoder = io.ZLibDecoder(
          raw: true,
        ).startChunkedConversion(output);
        for (int i = 0; i < compressed.length; i += 4096) {
          decoder.add(
            Uint8List.sublistView(
              compressed,
              i,
              (i + 4096).clamp(0, compressed.length),
            ),
          );
        }
        decoder.close();
      }
    } on LibraryFailure {
      rethrow;
    } catch (_) {
      throw const LibraryFailure('zip', 'Invalid compressed ZIP content.');
    }
    final content = output.bytes.takeBytes();
    if (content.length != entry.size || getCrc32(content) != entry.crc) {
      throw const LibraryFailure('zip', 'ZIP checksum or size mismatch.');
    }
    result.addFile(
      ArchiveFile(entry.name, entry.size, content)
        ..isFile = !entry.name.endsWith('/'),
    );
  }
  return result;
}

class _BoundedSink implements Sink<List<int>> {
  _BoundedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> data) {
    count += data.length;
    if (count > limit) {
      throw const LibraryFailure(
        'limit',
        'Expanded ZIP content exceeds its declared size.',
      );
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
