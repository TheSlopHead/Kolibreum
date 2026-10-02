// Security regressions for the mobile fixes and format v2.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/app/library_controller.dart';
import 'package:mut_mobile/app/mut_app.dart';
import 'package:mut_mobile/data/book_decoder.dart';
import 'package:mut_mobile/data/crypto_codec.dart';
import 'package:mut_mobile/data/safe_zip.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:mut_mobile/domain/library_repository.dart';
import 'package:mut_mobile/platform/documents.dart';

import 'ui_test.dart' show TestRepository;

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, List<int>> _backupFiles(Uint8List bytes) => {
  for (final entry in safeZip(bytes)) entry.name: entry.readBytes()!,
};

Uint8List _remanifest(Map<String, List<int>> files) {
  files.remove('manifest.json');
  final manifest = {
    for (final e in files.entries)
      e.key: hashes.sha256.convert(e.value).toString(),
  };
  return _zip({
    ...files,
    'manifest.json': utf8.encode(jsonEncode({'version': 1, 'files': manifest})),
  });
}

class _PendingDocuments implements Documents {
  final result = Completer<bool>();
  Uint8List? nativeCopy;
  Uint8List? written;
  @override
  Future<PickedDocument?> pick({bool backup = false}) async => null;
  @override
  Future<bool> save(String name, Uint8List bytes, {bool verify = false}) {
    // MethodChannel marshals a separate ByteArray in the native process heap.
    nativeCopy = Uint8List.fromList(bytes);
    return result.future;
  }

  @override
  Future<void> cancel() async {
    nativeCopy?.fillRange(0, nativeCopy!.length, 0);
    nativeCopy = null;
    if (!result.isCompleted) result.complete(false);
  }

  bool chooseDestination() {
    if (result.isCompleted || nativeCopy == null) return false;
    written = Uint8List.fromList(nativeCopy!);
    nativeCopy!.fillRange(0, nativeCopy!.length, 0);
    result.complete(true);
    return true;
  }
}

void main() {
  late Directory temp;
  late VaultStore vault;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mut-security-audit-');
    // Small KDF only for test speed; this is not the production setting.
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

  test('SEC-02: imported JSON ciphertext cannot replace a v2 catalog', () async {
    await vault.create('audit password');
    final privateId = await vault.importFile(
      'private.txt',
      Uint8List.fromList(utf8.encode('PRIVATE_ORIGINAL')),
    );
    final privateBook = vault.books().single;
    // The attacker can learn ciphertext IDs from a copy of the directory.
    // No password, master key, seal(), or private store fields are used in
    // constructing or replacing the catalog below.
    final forgedCatalog = utf8.encode(
      jsonEncode({
        'version': 1,
        'books': {
          privateId: {...privateBook.toJson(), 'title': 'ATTACKER_CONTROLLED'},
        },
        'settings': <String, dynamic>{},
      }),
    );
    final carrierId = await vault.importFile(
      'untrusted-catalog.json',
      Uint8List.fromList(forgedCatalog),
    );
    final carrier = vault.books().firstWhere((b) => b.id == carrierId);
    final object = File(
      '${vault.root.path}/objects/${carrier.objectId.substring(0, 2)}/${carrier.objectId}',
    );
    await object.copy('${vault.root.path}/snapshots/${carrier.objectId}');
    await File(
      '${vault.root.path}/HEAD',
    ).writeAsString('${carrier.objectId}\n');
    vault.lock();
    await expectLater(
      vault.unlock('audit password'),
      throwsA(
        isA<LibraryFailure>().having((e) => e.code, 'code', 'authentication'),
      ),
    );
    expect(vault.unlocked, false);
  });

  test('SEC-03: nested FB2 paragraphs do not amplify text', () {
    final xml =
        '<FictionBook><body><section>${'<p>' * 48}'
        '${'a' * (1024 * 1024)}${'</p>' * 48}'
        '</section></body></FictionBook>';
    final decoded = decodeBook(
      Uint8List.fromList(utf8.encode(xml)),
      'FB2',
      'audit',
    );
    final size = decoded.chapters.single.paragraphs.fold<int>(
      0,
      (total, paragraph) => total + paragraph.length,
    );
    expect(xml.length, lessThan(2 * 1024 * 1024));
    expect(decoded.chapters.single.paragraphs.length, 1);
    expect(size, 1024 * 1024);
  });

  for (final kind in [
    'objects',
    'snapshots',
    'wrong shard',
    'historical object',
  ]) {
    test(
      'SEC-04: restore rejects an extra $kind file and preserves the library',
      () async {
        await vault.create('audit password');
        final id = await vault.importFile(
          'ok.bin',
          Uint8List.fromList([1, 2, 3]),
        );
        final files = _backupFiles(await vault.backup());
        final extraId = CryptoCodec.newId();
        final object = vault.books().single.objectId;
        final name = switch (kind) {
          'snapshots' => 'snapshots/$extraId',
          'wrong shard' =>
            'objects/${object.startsWith('00') ? '01' : '00'}/$object',
          _ => 'objects/${extraId.substring(0, 2)}/$extraId',
        };
        files[name] = kind == 'historical object'
            ? files.keys
                  .where((n) => n.startsWith('objects/'))
                  .map((n) => files[n]!)
                  .first
            : utf8.encode('UNAUTHENTICATED_PLAINTEXT_SENTINEL');
        await expectLater(
          vault.restore(_remanifest(files), 'audit password'),
          throwsA(
            isA<LibraryFailure>().having((e) => e.code, 'code', 'restore'),
          ),
        );
        expect(await vault.read(id), [1, 2, 3]);
        expect(await Directory('${vault.root.path}.previous').exists(), false);
        expect(
          await temp.list().where((e) => e.path.contains('.restore-')).isEmpty,
          true,
        );
      },
    );
  }

  test('SEC-04: a backup missing a referenced object is rejected', () async {
    await vault.create('audit password');
    final id = await vault.importFile('ok.bin', Uint8List.fromList([1, 2, 3]));
    final files = _backupFiles(await vault.backup());
    files.remove(files.keys.firstWhere((name) => name.startsWith('objects/')));
    await expectLater(
      vault.restore(_remanifest(files), 'audit password'),
      throwsA(isA<LibraryFailure>().having((e) => e.code, 'code', 'restore')),
    );
    expect(await vault.read(id), [1, 2, 3]);
  });

  for (final kind in ['objects', 'snapshots']) {
    test(
      'SEC-05: backup refuses corrupted $kind before returning a ZIP',
      () async {
        await vault.create('audit password');
        await vault.importFile('ok.bin', Uint8List.fromList([1, 2, 3]));
        final object = vault.books().single.objectId;
        final head = (await File(
          '${vault.root.path}/HEAD',
        ).readAsString()).trim();
        final file = File(
          kind == 'objects'
              ? '${vault.root.path}/objects/${object.substring(0, 2)}/$object'
              : '${vault.root.path}/snapshots/$head',
        );
        final corrupted = await file.readAsBytes();
        corrupted[24] ^= 1;
        await file.writeAsBytes(corrupted);
        await expectLater(
          vault.backup(),
          throwsA(
            isA<LibraryFailure>().having(
              (e) => e.code,
              'code',
              'authentication',
            ),
          ),
        );
      },
    );
  }

  test(
    'LIMITATION: replacing only an old header restores the old password',
    () async {
      final recovery = await vault.create('old password');
      final header = File('${vault.root.path}/vault.json');
      final oldHeader = await header.readAsBytes();
      await vault.changePassword('new password');
      final id = await vault.importFile(
        'new-private.bin',
        Uint8List.fromList([7, 8, 9]),
      );
      vault.lock();
      await expectLater(
        vault.unlock('old password'),
        throwsA(isA<LibraryFailure>()),
      );
      await header.writeAsBytes(oldHeader);
      await vault.unlock('old password');
      expect(await vault.read(id), [7, 8, 9]);
      vault.lock();
      await vault.unlock(recovery, recovery: true);
      expect(await vault.read(id), [7, 8, 9]);
    },
  );

  test(
    'HARDENING: password change accepts only two Unicode characters',
    () async {
      await vault.create('audit password');
      const short = '😀😀';
      expect(short.runes.length, 2);
      await vault.changePassword(short);
      vault.lock();
      await vault.unlock(short);
      expect(vault.unlocked, true);
    },
  );

  test(
    'HARDENING: reader accepts an archive with 32 KiB Argon2 memory',
    () async {
      final codec = CryptoCodec();
      final result = await codec.passwordKey('audit password', {
        'memory': 32,
        'time': 1,
        'threads': 1,
        'salt': base64Encode(List.filled(32, 0)),
      });
      expect(result.length, 32);
      result.fillRange(0, result.length, 0);
    },
  );

  test(
    'CONTROL: KDF rejects costs outside allowed bounds before deriving',
    () async {
      final codec = CryptoCodec();
      for (final overrides in <Map<String, dynamic>>[
        {'memory': 31},
        {'memory': 131073},
        {'time': 0},
        {'time': 7},
        {'threads': 0},
        {'threads': 9},
        {
          'salt': base64Encode([1]),
        },
      ]) {
        await expectLater(
          codec.passwordKey('audit password', {
            'memory': 64,
            'time': 1,
            'threads': 1,
            'salt': base64Encode(List.filled(32, 0)),
            ...overrides,
          }),
          throwsA(isA<LibraryFailure>()),
        );
      }
    },
  );

  test(
    'CONTROL: ciphertext, nonce, tag, AAD and wrong key fail closed',
    () async {
      final codec = CryptoCodec();
      final key = SecretKey(CryptoCodec.randomBytes(32));
      final payload = await codec.seal([1, 2, 3], key, 'audit-object');
      for (final position in [0, 24, payload.length - 1]) {
        final modified = Uint8List.fromList(payload)..[position] ^= 1;
        await expectLater(
          codec.open(modified, key, 'audit-object'),
          throwsA(isA<LibraryFailure>()),
        );
      }
      await expectLater(
        codec.open(payload, key, 'different-object'),
        throwsA(isA<LibraryFailure>()),
      );
      await expectLater(
        codec.open(payload, SecretKey(List.filled(32, 0)), 'audit-object'),
        throwsA(isA<LibraryFailure>()),
      );
    },
  );

  test(
    'CONTROL: rechecksummed tampered backup still fails AEAD without replacing vault',
    () async {
      await vault.create('audit password');
      final id = await vault.importFile(
        'ok.bin',
        Uint8List.fromList([1, 2, 3]),
      );
      final files = _backupFiles(await vault.backup());
      final name = files.keys.firstWhere((n) => n.startsWith('objects/'));
      final bytes = Uint8List.fromList(files[name]!)..[24] ^= 1;
      files[name] = bytes;
      await expectLater(
        vault.restore(_remanifest(files), 'audit password'),
        throwsA(isA<LibraryFailure>()),
      );
      expect(await vault.read(id), [1, 2, 3]);
    },
  );

  test(
    'CONTROL: traversals, absolute paths and alternate separators are rejected',
    () {
      for (final name in [
        '../outside',
        '/outside',
        'a/../../outside',
        r'..\outside',
        'C:/outside',
        'a\u0000b',
      ]) {
        expect(
          () => safeZip(
            _zip({
              name: [1, 2, 3],
            }),
          ),
          throwsA(isA<LibraryFailure>()),
        );
      }
    },
  );

  test(
    'CONTROL: deterministic 2000 malformed ZIP mutations finish with safe errors',
    () {
      final seed = _zip({'book': utf8.encode('small audit fixture')});
      final rng = Random(715);
      for (var i = 0; i < 2000; i++) {
        final data = Uint8List.fromList(seed);
        for (var j = 0; j < 1 + rng.nextInt(4); j++) {
          data[rng.nextInt(data.length)] ^= 1 + rng.nextInt(255);
        }
        try {
          safeZip(data, maxBytes: 1024 * 1024, maxEntries: 64);
        } on LibraryFailure {
          // Expected safe rejection. Unhandled VM errors fail this test.
        } on FormatException {
          // Invalid UTF-8 is also fail closed; worker maps it to a safe error.
        }
      }
    },
  );

  test('CONTROL: deep XML and too many nodes are rejected', () {
    for (final xml in [
      '<FictionBook><body>${'<x>' * 80}<p>text</p>${'</x>' * 80}</body></FictionBook>',
      '<FictionBook><body>${'<p/>' * 100001}</body></FictionBook>',
    ]) {
      expect(
        () => decodeBook(Uint8List.fromList(utf8.encode(xml)), 'FB2', 'audit'),
        throwsA(isA<LibraryFailure>().having((e) => e.code, 'code', 'limit')),
      );
    }
  });

  testWidgets('SEC-01: old export read cannot resume in a new session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = TestRepository()..pendingRead = Completer<Uint8List>();
    final controller = LibraryController(repository)
      ..hasArchive = true
      ..status = LibraryStatus.unlocked;
    final documents = _PendingDocuments();
    await controller.refresh();
    await tester.pumpWidget(
      MutApp(controller: controller, documents: documents),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orbits of Silence').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export original'));
    await tester.tap(find.text('Export original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose location'));
    await tester.pump();
    await controller.lock();
    // Simulate a new unlocked session before the old read completes; busy UI
    // currently prevents this path, but generation checks must still protect it.
    controller.status = LibraryStatus.unlocked;
    repository.locked = false;
    final plaintext = TestRepository.readingBytes();
    repository.pendingRead!.complete(plaintext);
    await tester.pumpAndSettle();
    expect(documents.nativeCopy, isNull);
    expect(documents.written, isNull);
    expect(plaintext.every((byte) => byte == 0), true);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  for (final viaTimeout in [false, true]) {
    testWidgets(
      'SEC-01: pending native export is cancelled by ${viaTimeout ? 'inactivity timeout' : 'manual lock'}',
      (tester) async {
        tester.view.physicalSize = const Size(600, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = TestRepository();
        final controller = LibraryController(repository)
          ..hasArchive = true
          ..status = LibraryStatus.unlocked;
        await controller.refresh();
        final documents = _PendingDocuments();
        await tester.pumpWidget(
          MutApp(controller: controller, documents: documents),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Orbits of Silence').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Export original'));
        await tester.tap(find.text('Export original'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose location'));
        await tester.pump();
        await tester.pump();
        expect(documents.nativeCopy, isNotNull);
        if (viaTimeout) {
          await tester.pump(const Duration(minutes: 5, seconds: 1));
        } else {
          await controller.lock();
        }
        await tester.pump();
        expect(controller.status, LibraryStatus.locked);
        expect(repository.locked, true);
        expect(documents.nativeCopy, isNull);
        expect(documents.chooseDestination(), false);
        await tester.pumpAndSettle();
        expect(documents.written, isNull);
        expect(controller.status, LibraryStatus.locked);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
}
