import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:mut_mobile/domain/library_repository.dart';
import 'support/cover_fixtures.dart';
import 'support/legacy_vault.dart';

void main() {
  late Directory temp;
  late VaultStore vault;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mut-v2-migration-');
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
  Future<Map<String, dynamic>> header([String? root]) async =>
      jsonDecode(
            await File('${root ?? vault.root.path}/vault.json').readAsString(),
          )
          as Map<String, dynamic>;
  Future<void> expectFiles(String root, Map<String, Uint8List> files) async {
    for (final entry in files.entries) {
      expect(
        await File('$root/${entry.key}').readAsBytes(),
        entry.value,
        reason: entry.key,
      );
    }
  }

  Future<void> expectNoStaging() async {
    expect(
      await temp
          .list()
          .where(
            (f) =>
                f.path.contains('.migrate-') ||
                f.path.contains('.migration-old-') ||
                f.path.contains('.restore-'),
          )
          .isEmpty,
      true,
    );
    expect(await File('${vault.root.path}.migration').exists(), false);
  }

  for (final recoveryUnlock in [false, true]) {
    test(
      'v1 migrates originals, covers and metadata using ${recoveryUnlock ? 'recovery' : 'password'}',
      () async {
        final recovery = await vault.create('correct horse');
        expect((await header())['version'], 2);
        final originals = {
          'book.fb2': coverFb2(),
          'original.bin': Uint8List.fromList(utf8.encode('PRIVATE_ORIGINAL')),
        };
        final saved = <String, Uint8List>{};
        for (final entry in originals.entries) {
          final id = await vault.importFile(entry.key, entry.value);
          saved[id] = entry.value;
          await vault.update(id, {
            'title': 'Private title',
            'author': 'Custom author',
            'metadata_read': true,
            'shelves': ['Private shelf'],
            'bookmarks': ['text-v2:0:17'],
            'position': {'locator': 'text-v2:0:17', 'progress': .42},
          });
        }
        await vault.savePreferences({'fontSize': 24, 'paginated': false});
        final before = vault.books().map((b) => b.toJson()).toList();
        final covered = vault.books().firstWhere(
          (b) => b.coverObjectId.isNotEmpty,
        );
        final thumbnail = await vault.readCover(covered.id);
        final legacyFiles = await makeLegacyVault(vault, recovery);
        await vault.unlock(
          recoveryUnlock ? recovery : 'correct horse',
          recovery: recoveryUnlock,
        );
        expect((await header())['version'], 2);
        expect(vault.books().map((b) => b.toJson()).toList(), before);
        expect(vault.preferences(), {'fontSize': 24, 'paginated': false});
        expect(await vault.readCover(covered.id), thumbnail);
        for (final entry in saved.entries) {
          expect(await vault.read(entry.key), entry.value);
        }
        await expectFiles('${vault.root.path}.v1', legacyFiles);
        // Keep even unreachable history only in the source copy; the new graph
        // contains exactly the files authenticated by the current catalog.
        final backup = await vault.backup();
        final names =
            ZipDecoder()
                .decodeBytes(backup)
                .where((e) => e.isFile)
                .map((e) => e.name)
                .toSet()
              ..remove('manifest.json');
        final active = await vault.root
            .list(recursive: true)
            .where((e) => e is File)
            .map((e) => e.path.substring(vault.root.path.length + 1))
            .toList();
        expect(active.toSet(), names);
        for (final file
            in await vault.root
                .list(recursive: true)
                .where((e) => e is File)
                .cast<File>()
                .toList()) {
          final text = latin1.decode(await file.readAsBytes());
          expect(text, isNot(contains('PRIVATE_ORIGINAL')));
          expect(text, isNot(contains('Private title')));
        }
        final stableHead = await File('${vault.root.path}/HEAD').readAsBytes();
        vault.lock();
        await vault.unlock('correct horse');
        expect(await File('${vault.root.path}/HEAD').readAsBytes(), stableHead);
        final restored = VaultStore(Directory('${temp.path}/restored'));
        try {
          await restored.restore(backup, recovery, recovery: true);
          for (final entry in saved.entries) {
            expect(await restored.read(entry.key), entry.value);
          }
          expect(await restored.readCover(covered.id), thumbnail);
        } finally {
          restored.lock();
        }
        await expectNoStaging();
      },
    );
  }

  test(
    'a verified v1 backup is upgraded inside staging before replacement',
    () async {
      final recovery = await vault.create('correct horse');
      final original = coverFb2();
      final id = await vault.importFile('book.fb2', original);
      final cover = await vault.readCover(id);
      await makeLegacyVault(vault, recovery);
      await vault.unlock('correct horse', migrate: false);
      final backup = await vault.backup();
      final restored = VaultStore(Directory('${temp.path}/restored'));
      try {
        await restored.restore(backup, recovery, recovery: true);
        expect((await header(restored.root.path))['version'], 2);
        expect(await restored.read(id), original);
        expect(await restored.readCover(id), cover);
        expect(await Directory('${restored.root.path}.v1').exists(), false);
        await restored.backup();
      } finally {
        restored.lock();
      }
      expect((await header())['version'], 1);
      await expectNoStaging();
    },
  );

  test(
    'corrupt v1 originals abort migration without changing the source',
    () async {
      final recovery = await vault.create('correct horse');
      await vault.importFile('book.fb2', coverFb2());
      final object = vault.books().single.objectId;
      final files = await makeLegacyVault(vault, recovery);
      final path = 'objects/${object.substring(0, 2)}/$object';
      files[path]![24] ^= 1;
      await File('${vault.root.path}/$path').writeAsBytes(files[path]!);
      await expectLater(
        vault.unlock('correct horse'),
        throwsA(
          isA<LibraryFailure>().having((e) => e.code, 'code', 'authentication'),
        ),
      );
      expect(vault.unlocked, false);
      await expectFiles(vault.root.path, files);
      expect(await Directory('${vault.root.path}.v1').exists(), false);
      await expectNoStaging();
    },
  );

  test('wrong secret never starts a v1 migration', () async {
    final recovery = await vault.create('correct horse');
    final files = await makeLegacyVault(vault, recovery);
    await expectLater(
      vault.unlock('wrong password'),
      throwsA(isA<LibraryFailure>()),
    );
    await expectFiles(vault.root.path, files);
    expect(await Directory('${vault.root.path}.v1').exists(), false);
    await expectNoStaging();
  });

  test('an empty v1 vault migrates without an objects directory', () async {
    final recovery = await vault.create('correct horse');
    final files = await makeLegacyVault(vault, recovery);
    await vault.unlock('correct horse');
    expect((await header())['version'], 2);
    expect(vault.books(), isEmpty);
    await expectFiles('${vault.root.path}.v1', files);
    await vault.importFile('first.bin', Uint8List.fromList([1]));
    expect(await vault.read(vault.books().single.id), [1]);
    await expectNoStaging();
  });

  test(
    'corrupt v1 covers also abort migration without changing the source',
    () async {
      final recovery = await vault.create('correct horse');
      await vault.importFile('book.fb2', coverFb2());
      final object = vault.books().single.coverObjectId;
      final files = await makeLegacyVault(vault, recovery);
      final path = 'objects/${object.substring(0, 2)}/$object';
      files[path]![24] ^= 1;
      await File('${vault.root.path}/$path').writeAsBytes(files[path]!);
      await expectLater(
        vault.unlock('correct horse'),
        throwsA(
          isA<LibraryFailure>().having((e) => e.code, 'code', 'authentication'),
        ),
      );
      await expectFiles(vault.root.path, files);
      expect(await Directory('${vault.root.path}.v1').exists(), false);
      await expectNoStaging();
    },
  );

  for (final version in [1, 3]) {
    test(
      'editing a v2 header to version $version cannot enable a legacy fallback',
      () async {
        await vault.create('correct horse');
        await vault.importFile('file.bin', Uint8List.fromList([1, 2, 3]));
        final changed = await header()
          ..['version'] = version;
        await File(
          '${vault.root.path}/vault.json',
        ).writeAsString(jsonEncode(changed));
        vault.lock();
        await expectLater(
          vault.unlock('correct horse'),
          throwsA(
            isA<LibraryFailure>().having(
              (e) => e.code,
              'code',
              version == 1 ? 'authentication' : 'version',
            ),
          ),
        );
        expect(vault.unlocked, false);
        expect(await Directory('${vault.root.path}.v1').exists(), false);
        await expectNoStaging();
      },
    );
  }

  test(
    'an interrupted migration recovers v1 and ignores unverified staging',
    () async {
      final recovery = await vault.create('correct horse');
      final id = await vault.importFile(
        'file.bin',
        Uint8List.fromList([3, 2, 1]),
      );
      await makeLegacyVault(vault, recovery);
      await vault.root.rename('${vault.root.path}.v1');
      await File('${vault.root.path}.migration').writeAsString('v1\n');
      final unverified = Directory('${vault.root.path}.migrate-unverified');
      await unverified.create();
      await File('${unverified.path}/vault.json').writeAsString('NOT_VERIFIED');
      expect(await vault.exists(), true);
      expect((await header())['version'], 1);
      expect(await File('${vault.root.path}.migration').exists(), false);
      await vault.unlock('correct horse');
      expect((await header())['version'], 2);
      expect(await vault.read(id), [3, 2, 1]);
      expect(
        await File('${unverified.path}/vault.json').readAsString(),
        'NOT_VERIFIED',
      );
    },
  );

  test(
    'an interrupted restore selects previous v2 rather than a stale v1 copy',
    () async {
      final recovery = await vault.create('correct horse');
      final id = await vault.importFile(
        'file.bin',
        Uint8List.fromList([7, 8, 9]),
      );
      await makeLegacyVault(vault, recovery);
      await vault.unlock('correct horse');
      vault.lock();
      await vault.root.rename('${vault.root.path}.previous');
      expect(await vault.exists(), true);
      expect((await header())['version'], 2);
      expect((await header('${vault.root.path}.v1'))['version'], 1);
      await vault.unlock('correct horse');
      expect(await vault.read(id), [7, 8, 9]);
    },
  );
}
