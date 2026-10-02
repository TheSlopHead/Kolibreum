import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:mut_mobile/domain/library_repository.dart';
import 'support/cover_fixtures.dart';

Future<void> legacyCatalog(
  VaultStore vault,
  String recovery, {
  String? coverObjectId,
}) async {
  vault.lock();
  final root = vault.root.path;
  final header =
      jsonDecode(await File('$root/vault.json').readAsString()) as Map;
  final master = await vault.codec.open(
    base64Decode(header['mobile_recovery'] as String),
    SecretKey(base64Url.decode(base64Url.normalize(recovery))),
    '${header['vault_id']}:recovery',
  );
  final snapshot = (await File('$root/HEAD').readAsString()).trim();
  final legacy = header['version'] == 1;
  final key = legacy
      ? await vault.codec.objectKey(
          master,
          header['vault_id'] as String,
          snapshot,
        )
      : await vault.codec.entityKey(
          master,
          header['vault_id'] as String,
          'snapshot',
          snapshot,
        );
  final aad = legacy ? snapshot : 'snapshot:$snapshot';
  final file = File('$root/snapshots/$snapshot');
  final plaintext = await vault.codec.open(await file.readAsBytes(), key, aad);
  final catalog = jsonDecode(utf8.decode(plaintext)) as Map;
  for (final raw in (catalog['books'] as Map).values) {
    final book = raw as Map;
    book.remove('coverobjectid');
    book.remove('cover_checked');
    if (coverObjectId != null) book['coverobjectid'] = coverObjectId;
    book['title'] = 'My custom title';
    book['author'] = 'My custom author';
    book['metadata_read'] = true;
  }
  await file.writeAsBytes(
    await vault.codec.seal(utf8.encode(jsonEncode(catalog)), key, aad),
  );
  master.fillRange(0, master.length, 0);
  plaintext.fillRange(0, plaintext.length, 0);
}

void main() {
  late Directory temp;
  late VaultStore vault;
  late String recovery;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mut-cover-test-');
    vault = VaultStore(
      Directory('${temp.path}/vault'),
      kdfMemory: 64,
      kdfTime: 1,
      kdfLanes: 1,
    );
    recovery = await vault.create('correct horse');
  });
  tearDown(() async {
    vault.lock();
    await temp.delete(recursive: true);
  });
  test(
    'covers are encrypted separately and survive reopen and backup restore',
    () async {
      final originals = {'book.epub': coverEpub(), 'book.fb2': coverFb2()};
      final covers = <String, Uint8List>{};
      for (final entry in originals.entries) {
        final id = await vault.importFile(entry.key, entry.value);
        final book = vault.books().firstWhere((b) => b.id == id);
        expect(book.coverChecked, true);
        expect(book.coverObjectId, isNotEmpty);
        expect(book.coverObjectId, isNot(book.objectId));
        expect(await vault.read(id), entry.value);
        final cover = (await vault.readCover(id))!;
        covers[id] = cover;
        final ciphertext = await File(
          '${vault.root.path}/objects/'
          '${book.coverObjectId.substring(0, 2)}/${book.coverObjectId}',
        ).readAsBytes();
        expect(ciphertext.length, cover.length + 40);
        expect(ciphertext.sublist(0, 16), isNot(cover.sublist(0, 16)));
      }
      final backup = await vault.backup();
      vault.lock();
      await expectLater(
        vault.readCover(covers.keys.first),
        throwsA(isA<LibraryFailure>()),
      );
      await vault.unlock('correct horse');
      for (final entry in covers.entries) {
        expect(await vault.readCover(entry.key), entry.value);
      }
      final restored = VaultStore(Directory('${temp.path}/restored'));
      try {
        await restored.restore(backup, recovery, recovery: true);
        for (final entry in covers.entries) {
          expect(await restored.readCover(entry.key), entry.value);
        }
      } finally {
        restored.lock();
      }
    },
  );
  test(
    'missing and corrupt covers preserve originals and record a completed check',
    () async {
      for (final original in [
        coverEpub(properties: ''),
        coverFb2(encoded: 'broken'),
      ]) {
        final id = await vault.importFile('book.epub', original);
        expect(await vault.read(id), original);
        final book = vault.books().firstWhere((b) => b.id == id);
        expect(book.coverChecked, true);
        expect(book.coverObjectId, isEmpty);
        final head = await File('${vault.root.path}/HEAD').readAsString();
        expect(await vault.readCover(id), isNull);
        expect(await vault.readCover(id), isNull);
        expect(await File('${vault.root.path}/HEAD').readAsString(), head);
      }
    },
  );
  test(
    'legacy catalogs extract covers once without overwriting edited metadata',
    () async {
      final id = await vault.importFile('old.fb2', coverFb2());
      final missing = await vault.importFile(
        'no-cover.epub',
        coverEpub(properties: ''),
      );
      await legacyCatalog(vault, recovery);
      await vault.unlock('correct horse');
      expect(vault.books().first.coverChecked, false);
      expect(await vault.readCover(id), isNotNull);
      expect(await vault.readCover(missing), isNull);
      final head = await File('${vault.root.path}/HEAD').readAsString();
      for (final book in vault.books()) {
        expect(book.title, 'My custom title');
        expect(book.author, 'My custom author');
        expect(book.metadataRead, true);
        expect(book.coverChecked, true);
        await vault.readCover(book.id);
      }
      expect(await File('${vault.root.path}/HEAD').readAsString(), head);
    },
  );
  test('invalid cover identifiers cannot escape the archive', () async {
    await vault.importFile('book.fb2', coverFb2());
    await legacyCatalog(vault, recovery, coverObjectId: '../../outside');
    await expectLater(
      vault.unlock('correct horse'),
      throwsA(isA<LibraryFailure>()),
    );
    expect(vault.unlocked, false);
  });
  test(
    'backup refuses a damaged encrypted cover before exporting it',
    () async {
      await vault.importFile('book.fb2', coverFb2());
      final book = vault.books().single;
      final file = File(
        '${vault.root.path}/objects/'
        '${book.coverObjectId.substring(0, 2)}/${book.coverObjectId}',
      );
      final ciphertext = await file.readAsBytes();
      ciphertext[24] ^= 1;
      await file.writeAsBytes(ciphertext);
      await expectLater(vault.backup(), throwsA(isA<LibraryFailure>()));
      expect(await vault.read(book.id), coverFb2());
    },
  );
  test(
    'restore authenticates covers even if an attacker updates backup checksums',
    () async {
      await vault.importFile('book.epub', coverEpub());
      final coverId = vault.books().single.coverObjectId;
      final entries = {
        for (final f in ZipDecoder().decodeBytes(await vault.backup()))
          if (f.isFile) f.name: Uint8List.fromList(f.readBytes()!),
      };
      final name = 'objects/${coverId.substring(0, 2)}/$coverId';
      entries[name]![24] ^= 1;
      final manifest =
          jsonDecode(utf8.decode(entries['manifest.json']!)) as Map;
      (manifest['files'] as Map)[name] = hashes.sha256
          .convert(entries[name]!)
          .toString();
      entries['manifest.json'] = Uint8List.fromList(
        utf8.encode(jsonEncode(manifest)),
      );
      final head = await File('${vault.root.path}/HEAD').readAsString();
      await expectLater(
        vault.restore(coverZip(entries), 'correct horse'),
        throwsA(isA<LibraryFailure>()),
      );
      expect(await File('${vault.root.path}/HEAD').readAsString(), head);
      expect(await vault.readCover(vault.books().single.id), isNotNull);
      expect(await Directory('${vault.root.path}.previous').exists(), false);
    },
  );
  test(
    'legacy PDF previews are optional derived objects and checked once',
    () async {
      final id = await vault.importFile('book.pdf', coverPdf());
      await legacyCatalog(vault, recovery);
      await vault.unlock('correct horse');
      expect(vault.needsPdfCover(id), true);
      expect(await vault.readCover(id), isNull);
      expect(vault.needsPdfCover(id), true);
      await vault.savePdfCover(id, coverPng());
      expect(vault.needsPdfCover(id), false);
      expect(await vault.readCover(id), isNotNull);
      final head = await File('${vault.root.path}/HEAD').readAsString();
      await vault.savePdfCover(id, null);
      expect(await File('${vault.root.path}/HEAD').readAsString(), head);
    },
  );
}
