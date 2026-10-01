import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:mut_mobile/domain/library_repository.dart';

void main() {
  late Directory temp;
  late VaultStore vault;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mut-vault-test-');
    vault = VaultStore(
      Directory('${temp.path}/vault'),
      kdfMemory: 64,
      kdfTime: 1,
      kdfLanes: 1,
    );
  });
  tearDown(() async {
    vault.lock();
    await temp.delete(recursive: true);
  });

  test(
    'create, arbitrary import, lock, reopen, byte-identical restore',
    () async {
      final recovery = await vault.create('correct horse');
      final original = Uint8List.fromList(
        utf8.encode('private arbitrary content'),
      );
      final id = await vault.importFile('Secret manuscript.xyz', original);
      await vault.update(id, {
        'title': 'Private title',
        'shelves': ['Private shelf'],
        'position': {
          'locator': 'text-v1:1:0.42',
          'progress': .42,
          'updateat': '2026-10-01T00:00:00Z',
        },
        'bookmarks': ['text-v1:1:0.2'],
      });
      await vault.savePreferences({
        'fontSize': 22,
        'lineHeight': 1.7,
        'pageColor': 2,
      });
      expect(vault.books().single.readable, false);
      expect(await vault.read(id), original);
      for (final file
          in await vault.root
              .list(recursive: true)
              .where((f) => f is File)
              .cast<File>()
              .toList()) {
        final content = latin1.decode(await file.readAsBytes());
        expect(content, isNot(contains('Private title')));
        expect(content, isNot(contains('private arbitrary content')));
        expect(content, isNot(contains('Secret manuscript')));
      }
      final backup = await vault.backup();
      vault.lock();
      await expectLater(vault.read(id), throwsA(isA<LibraryFailure>()));
      expect(() => vault.books(), throwsA(isA<LibraryFailure>()));
      await expectLater(
        vault.unlock('wrong password'),
        throwsA(isA<LibraryFailure>()),
      );
      await vault.unlock('correct horse');
      expect(vault.preferences()['fontSize'], 22);
      expect(vault.books().single.progress, .42);
      expect(vault.books().single.bookmarks, ['text-v1:1:0.2']);
      final restored = VaultStore(Directory('${temp.path}/restored'));
      await restored.restore(backup, recovery, recovery: true);
      expect(await restored.read(id), original);
      expect(restored.books().single.shelves, ['Private shelf']);
      expect(restored.preferences()['pageColor'], 2);
      restored.lock();
    },
  );
  test('duplicates skipped or explicitly kept as an edition', () async {
    await vault.create('correct horse');
    final data = Uint8List.fromList([1, 2, 3]);
    await vault.importFile('first.bin', data);
    await expectLater(
      vault.importFile('renamed.bin', data),
      throwsA(isA<LibraryFailure>().having((e) => e.code, 'code', 'duplicate')),
    );
    await vault.importFile('second.bin', data, keepDuplicate: true);
    expect(vault.books(), hasLength(2));
  });
  test('object corruption fails authentication', () async {
    await vault.create('correct horse');
    final id = await vault.importFile(
      'test.txt',
      Uint8List.fromList([1, 2, 3]),
    );
    final object = vault.books().single.objectId;
    final file = File(
      '${vault.root.path}/objects/${object.substring(0, 2)}/$object',
    );
    final payload = await file.readAsBytes();
    payload[24] ^= 1;
    await file.writeAsBytes(payload);
    await expectLater(
      vault.read(id),
      throwsA(
        isA<LibraryFailure>().having((e) => e.code, 'code', 'authentication'),
      ),
    );
  });
  test(
    'removal persists, excludes the book from backup and allows reimport',
    () async {
      await vault.create('correct horse');
      final bytes = Uint8List.fromList([3, 4, 5]);
      final removed = await vault.importFile('removed.fb2', bytes);
      final kept = await vault.importFile(
        'kept.bin',
        Uint8List.fromList([8, 9]),
      );
      await vault.remove(removed);
      expect(vault.books().map((book) => book.id), [kept]);
      await expectLater(vault.read(removed), throwsA(isA<LibraryFailure>()));
      vault.lock();
      await vault.unlock('correct horse');
      expect(vault.books().map((book) => book.id), [kept]);
      final restored = VaultStore(Directory('${temp.path}/removed-backup'));
      await restored.restore(await vault.backup(), 'correct horse');
      expect(restored.books().map((book) => book.id), [kept]);
      expect(await restored.read(kept), [8, 9]);
      restored.lock();
      await vault.importFile('reimported.fb2', bytes);
      expect(vault.books(), hasLength(2));
      await expectLater(
        vault.remove('missing'),
        throwsA(isA<LibraryFailure>()),
      );
      vault.lock();
      await expectLater(vault.remove(kept), throwsA(isA<LibraryFailure>()));
    },
  );
  test(
    'password change preserves recovery and does not change old backup password',
    () async {
      final code = await vault.create('old password');
      final id = await vault.importFile(
        'test.txt',
        Uint8List.fromList([1, 2, 3]),
      );
      final backup = await vault.backup();
      await vault.changePassword('new password');
      vault.lock();
      await expectLater(
        vault.unlock('old password'),
        throwsA(isA<LibraryFailure>()),
      );
      await vault.unlock('new password');
      expect(await vault.read(id), [1, 2, 3]);
      vault.lock();
      await vault.unlock(code, recovery: true);
      final old = VaultStore(Directory('${temp.path}/old'));
      await old.restore(backup, 'old password');
      expect(await old.read(id), [1, 2, 3]);
      old.lock();
    },
  );
  test(
    'tampered backup and wrong secret cannot replace existing library',
    () async {
      await vault.create('correct horse');
      final id = await vault.importFile(
        'test.bin',
        Uint8List.fromList([1, 2, 3]),
      );
      final backup = await vault.backup();
      final archive = ZipDecoder().decodeBytes(backup);
      final modified = Archive();
      for (final f in archive) {
        final data = f.name == 'HEAD'
            ? utf8.encode('tampered')
            : f.readBytes()!;
        modified.addFile(ArchiveFile(f.name, data.length, data));
      }
      await expectLater(
        vault.restore(
          Uint8List.fromList(ZipEncoder().encode(modified)),
          'correct horse',
        ),
        throwsA(isA<LibraryFailure>()),
      );
      await expectLater(
        vault.restore(backup, 'wrong password'),
        throwsA(isA<LibraryFailure>()),
      );
      expect(await vault.read(id), [1, 2, 3]);
      expect(await Directory('${vault.root.path}.previous').exists(), false);
    },
  );
  test('invalid object identifiers cannot escape the archive', () async {
    await vault.create('correct horse');
    final head = File('${vault.root.path}/HEAD');
    await head.writeAsString('../../outside');
    vault.lock();
    await expectLater(
      vault.unlock('correct horse'),
      throwsA(isA<LibraryFailure>()),
    );
    expect(vault.unlocked, false);
  });
}
