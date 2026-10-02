import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mut_mobile/data/pdf_cover.dart';
import 'package:mut_mobile/data/isolate_repository.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:pdfrx/pdfrx.dart';
import 'support/cover_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'PDFium renders the first page to a bounded in-memory preview',
    () async {
      final temp = await Directory.systemTemp.createTemp('mut-pdf-cover-test-');
      Pdfrx.cacheDirectoryPath = temp.path;
      // Flutter test bundles native libraries under build/, rather than next
      // to an installed executable as the desktop PDFium loader expects.
      final libraryName = Platform.isWindows
          ? 'pdfium.dll'
          : Platform.isMacOS
          ? 'libpdfium.dylib'
          : 'libpdfium.so';
      Pdfrx.pdfiumModulePath = File(
        'build/native_assets/'
        '${Platform.operatingSystem}/$libraryName',
      ).absolute.path;
      bool initialized = false;
      try {
        final original = coverPdf();
        final unchanged = Uint8List.fromList(original);
        final cover = await renderPdfCover(
          original,
          initialize: () => PdfrxEntryFunctions.instance.init(),
        );
        expect(cover, isNotNull);
        initialized = true;
        final raster = image.decodeJpg(cover!)!;
        expect((raster.width, raster.height), (512, 768));
        expect(raster.getPixel(50, 50).r, closeTo(178, 5));
        expect(original, unchanged);
        expect(await temp.list(recursive: true).toList(), isEmpty);
        expect(await renderPdfCover(Uint8List.fromList([1, 2, 3])), isNull);
        final root = Directory('${temp.path}/vault');
        final seed = VaultStore(root, kdfMemory: 64, kdfTime: 1, kdfLanes: 1);
        await seed.create('correct horse');
        seed.lock();
        final repository = await IsolateLibraryRepository.start(root.path);
        try {
          await repository.unlock('correct horse');
          final id = await repository.importFile('book.pdf', original);
          expect((await repository.books()).single.coverObjectId, isNotEmpty);
          expect(await repository.readCover(id), isNotNull);
          expect(await repository.read(id), original);
          final invalid = Uint8List.fromList('%PDF-broken'.codeUnits);
          final invalidId = await repository.importFile('broken.pdf', invalid);
          expect(await repository.read(invalidId), invalid);
          expect(await repository.readCover(invalidId), isNull);
        } finally {
          await repository.dispose();
        }
      } finally {
        if (initialized) {
          await PdfrxEntryFunctions.instance.stopBackgroundWorker();
        }
        await temp.delete(recursive: true);
      }
    },
  );
}
