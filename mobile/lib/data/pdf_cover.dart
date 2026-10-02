import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';
import 'cover_decoder.dart';

/// Run from the main isolate, so previews and the reader share pdfrx's worker.
/// PDF bytes stay in memory; openData never writes an unencrypted original.
Future<Uint8List?> renderPdfCover(
  Uint8List bytes, {
  Future<void> Function()? initialize,
}) async {
  if (bytes.length < 5 ||
      bytes.length > 32 * 1024 * 1024 ||
      String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    return null;
  }
  PdfDocument? document;
  PdfImage? rendered;
  try {
    await (initialize ?? pdfrxFlutterInitialize)();
    document = await PdfDocument.openData(
      bytes,
      sourceName: 'mut-cover',
      useProgressiveLoading: true,
      maxSizeToCacheOnMemory: bytes.length,
    );
    if (document.pages.isEmpty) return null;
    final page = document.pages.first;
    if (!page.width.isFinite ||
        !page.height.isFinite ||
        page.width <= 0 ||
        page.height <= 0) {
      return null;
    }
    final scale = math.min(
      coverThumbnailWidth / page.width,
      coverThumbnailHeight / page.height,
    );
    final width = math.max(1, (page.width * scale).floor());
    final height = math.max(1, (page.height * scale).floor());
    rendered = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
    );
    if (rendered == null) return null;
    return await compute(_encodePdfCover, (rendered.pixels, width, height));
  } catch (_) {
    // Invalid/password-protected PDFs and unavailable engines use the text card.
    return null;
  } finally {
    if (rendered != null) {
      rendered.pixels.fillRange(0, rendered.pixels.length, 0);
      rendered.dispose();
    }
    try {
      await document?.dispose();
    } catch (_) {
      // Cleanup failures must not prevent preserving the user's original.
    }
  }
}

Uint8List? _encodePdfCover((Uint8List, int, int) input) {
  final (pixels, width, height) = input;
  try {
    final raster = image.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      bytesOffset: pixels.offsetInBytes,
      numChannels: 4,
      order: image.ChannelOrder.bgra,
    );
    final encoded = image.encodeJpg(raster, quality: 85);
    return encoded.length <= maxCoverThumbnailBytes ? encoded : null;
  } finally {
    pixels.fillRange(0, pixels.length, 0);
  }
}
