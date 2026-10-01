import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/features/reader/pdf_reader.dart';
import 'package:pdfrx/pdfrx.dart';

Uint8List blankPdf() {
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
  ];
  var pdf = '%PDF-1.4\n';
  final offsets = <int>[0];
  for (final (index, object) in objects.indexed) {
    offsets.add(pdf.length);
    pdf += '${index + 1} 0 obj\n$object\nendobj\n';
  }
  final xref = pdf.length;
  pdf += 'xref\n0 6\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    pdf += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  pdf += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return Uint8List.fromList(pdf.codeUnits);
}

void main() {
  testWidgets(
    'PDFium renders both modes and preserves the native page number',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mut-pdf-test-'),
      ))!;
      Pdfrx.cacheDirectoryPath = temp.path;
      // Flutter's Linux test runner does not resolve PDFium's native asset
      // manifest from its engine directory. Use the binary built by the hook.
      if (Platform.isLinux) {
        Pdfrx.pdfiumModulePath = File(
          'build/native_assets/linux/libpdfium.so',
        ).absolute.path;
      }
      await tester.runAsync(pdfrxFlutterInitialize);
      final bytes = blankPdf();
      final key = GlobalKey<PdfReaderState>();
      (String, int, int)? position;
      Future<void> settleNative() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
      }

      Future<void> pump(bool paginated) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 358,
              height: 610,
              child: PdfReader(
                key: key,
                bytes: bytes,
                bookId: 'test-book',
                initialPage: 2,
                paginated: paginated,
                onPosition: (locator, page, total) =>
                    position = (locator, page, total),
              ),
            ),
          ),
        );
        await settleNative();
      }

      try {
        await pump(true);
        expect(find.byType(PdfPageView), findsWidgets);
        expect(position, ('pdf-v1:2', 2, 3));
        await tester.drag(find.byType(PageView), const Offset(-600, 0));
        await settleNative();
        expect(position, ('pdf-v1:3', 3, 3));
        await pump(false);
        expect(find.byType(PdfViewer), findsOneWidget);
        expect(position, ('pdf-v1:3', 3, 3));
        final navigation = key.currentState!.goToPage(1);
        await settleNative();
        await navigation;
        expect(position, ('pdf-v1:1', 1, 3));
        await pump(true);
        expect(position, ('pdf-v1:1', 1, 3));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.runAsync(() => temp.delete(recursive: true));
      }
    },
  );
}
