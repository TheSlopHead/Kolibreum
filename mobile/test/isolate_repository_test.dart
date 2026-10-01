import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/isolate_repository.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:mut_mobile/domain/library_repository.dart';

void main() {
  test(
    'worker transfers originals, serializes commits and clears its session',
    () async {
      final temp = await Directory.systemTemp.createTemp('mut-worker-test-');
      final root = Directory('${temp.path}/vault');
      final seed = VaultStore(root, kdfMemory: 64, kdfTime: 1, kdfLanes: 1);
      await seed.create('correct horse');
      seed.lock();
      final repository = await IsolateLibraryRepository.start(root.path);
      try {
        expect(await repository.exists(), true);
        await repository.unlock('correct horse');
        final id = await repository.importFile(
          'original.bin',
          Uint8List.fromList([0, 1, 255]),
        );
        await Future.wait([
          repository.update(id, {'title': 'Revised title'}),
          repository.savePreferences({'fontSize': 24}),
          repository.update(id, {
            'shelves': ['Custom shelf'],
          }),
        ]);
        expect((await repository.books()).single.title, 'Revised title');
        expect((await repository.books()).single.shelves, ['Custom shelf']);
        expect((await repository.preferences())['fontSize'], 24);
        expect(await repository.read(id), [0, 1, 255]);
        await repository.lock();
        await expectLater(repository.read(id), throwsA(isA<LibraryFailure>()));
        await repository.unlock('correct horse');
        expect((await repository.books()).single.title, 'Revised title');
        expect(await repository.backup(), isNotEmpty);
        await repository.remove(id);
        await repository.lock();
        await repository.unlock('correct horse');
        expect(await repository.books(), isEmpty);
      } finally {
        await repository.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
}
