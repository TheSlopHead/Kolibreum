import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import '../domain/book.dart';
import '../domain/library_repository.dart';
import 'crypto_codec.dart';
import 'safe_zip.dart';

/// Owned by the worker isolate. No widgets, platform APIs, logs or global keys.
class VaultStore {
  VaultStore(
    this.root, {
    this.kdfMemory = 65536,
    this.kdfTime = 3,
    this.kdfLanes = 4,
  });
  final Directory root;
  final int kdfMemory, kdfTime, kdfLanes;
  final codec = CryptoCodec();
  Uint8List? _master;
  Map<String, dynamic> _header = {};
  Map<String, dynamic> _catalog = {};
  bool get unlocked => _master != null;
  Future<bool> exists() => File(p.join(root.path, 'vault.json')).exists();
  void _requireSession() {
    if (!unlocked) {
      throw const LibraryFailure('locked', 'Unlock your archive first.');
    }
  }

  Future<String> create(String password) async {
    if (utf8.encode(password).length < 8) {
      throw const LibraryFailure(
        'password',
        'Use at least 8 bytes for your password.',
      );
    }
    if (await exists()) {
      throw const LibraryFailure('exists', 'An archive already exists.');
    }
    await root.create(recursive: true);
    final vaultId = CryptoCodec.newId();
    final master = CryptoCodec.randomBytes(32);
    final kdf = {
      'salt': base64Encode(CryptoCodec.randomBytes(32)),
      'memory': kdfMemory,
      'time': kdfTime,
      'threads': kdfLanes,
    };
    final passwordKey = await codec.passwordKey(password, kdf);
    final wrapped = await codec.seal(master, SecretKey(passwordKey), vaultId);
    passwordKey.fillRange(0, passwordKey.length, 0);
    final recovery = CryptoCodec.randomBytes(32);
    final recoveryBox = await codec.seal(
      master,
      SecretKey(recovery),
      '$vaultId:recovery',
    );
    _header = {
      'version': 1,
      'vault_id': vaultId,
      'kdf': kdf,
      'key_nonce': base64Encode(wrapped.sublist(0, 24)),
      'wrapped_master_key': base64Encode(wrapped.sublist(24)),
      'mobile_recovery': base64Encode(recoveryBox),
    };
    _master = master;
    _catalog = {
      'version': 1,
      'createdat': DateTime.now().toUtc().toIso8601String(),
      'books': <String, dynamic>{},
      'shelves': ['Bedtime', 'Essays & notes', 'Travel'],
      'settings': <String, dynamic>{},
    };
    try {
      await _atomic(
        File(p.join(root.path, 'vault.json')),
        utf8.encode(jsonEncode(_header)),
      );
      await _commit(_catalog);
    } catch (_) {
      lock();
      rethrow;
    }
    final code = base64UrlEncode(recovery).replaceAll('=', '');
    recovery.fillRange(0, recovery.length, 0);
    return code;
  }

  Future<void> unlock(String secret, {bool recovery = false}) async {
    lock();
    try {
      final file = File(p.join(root.path, 'vault.json'));
      if (await file.length() > 16384) {
        throw const LibraryFailure('corrupt', 'Invalid archive header.');
      }
      _header = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      if (_header['version'] != 1) {
        throw const LibraryFailure('version', 'Unsupported archive version.');
      }
      final id = _header['vault_id'] as String;
      CryptoCodec.requireId(id);
      Uint8List wrapping;
      List<int> payload;
      if (recovery) {
        if (_header['mobile_recovery'] == null) {
          throw const LibraryFailure(
            'recovery',
            'This archive has no mobile recovery code.',
          );
        }
        wrapping = base64Url.decode(base64Url.normalize(secret.trim()));
        if (wrapping.length != 32) {
          throw const LibraryFailure('recovery', 'Invalid recovery code.');
        }
        payload = base64Decode(_header['mobile_recovery'] as String);
      } else {
        wrapping = await codec.passwordKey(
          secret,
          Map<String, dynamic>.from(_header['kdf'] as Map),
        );
        payload = [
          ...base64Decode(_header['key_nonce'] as String),
          ...base64Decode(_header['wrapped_master_key'] as String),
        ];
      }
      try {
        _master = await codec.open(
          payload,
          SecretKey(wrapping),
          recovery ? '$id:recovery' : id,
        );
      } finally {
        wrapping.fillRange(0, wrapping.length, 0);
      }
      if (_master!.length != 32) {
        throw const LibraryFailure('corrupt', 'Invalid archive key.');
      }
      final head = File(p.join(root.path, 'HEAD'));
      if (await head.length() > 128) {
        throw const LibraryFailure('corrupt', 'Invalid archive root.');
      }
      final snapshot = (await head.readAsString()).trim();
      CryptoCodec.requireId(snapshot);
      final data = await _get('snapshots', snapshot);
      try {
        _catalog = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(data)) as Map,
        );
      } finally {
        data.fillRange(0, data.length, 0);
      }
      if (_catalog['version'] != 1 || _catalog['books'] is! Map) {
        throw const LibraryFailure('corrupt', 'Invalid library catalog.');
      }
      for (final b in books()) {
        CryptoCodec.requireId(b.id);
        CryptoCodec.requireId(b.objectId);
      }
    } catch (_) {
      lock();
      rethrow;
    }
  }

  void lock() {
    _master?.fillRange(0, _master!.length, 0);
    _master = null;
    _catalog = {};
    _header = {};
  }

  List<Book> books() {
    _requireSession();
    return (_catalog['books'] as Map).values
        .map((b) => Book.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<String> importFile(
    String name,
    Uint8List data, {
    bool keepDuplicate = false,
  }) async {
    _requireSession();
    if (data.length > 32 * 1024 * 1024) {
      throw const LibraryFailure(
        'limit',
        'This prototype accepts files up to 32 MB.',
      );
    }
    final hash = hashes.sha256.convert(data).toString();
    if (!keepDuplicate && books().any((b) => b.hash == hash)) {
      throw const LibraryFailure(
        'duplicate',
        'This exact file is already in your library.',
      );
    }
    final format = p.extension(name).replaceFirst('.', '').toUpperCase();
    final id = CryptoCodec.newId();
    final object = await _put('objects', data);
    final book = Book(
      id: id,
      title: p.basenameWithoutExtension(name),
      author: '',
      format: format.isEmpty ? 'FILE' : format,
      objectId: object,
      size: data.length,
      hash: hash,
    );
    final next = _copyCatalog();
    (next['books'] as Map)[id] = book.toJson();
    await _commit(next);
    return id;
  }

  Future<Uint8List> read(String id) async {
    _requireSession();
    final b = (_catalog['books'] as Map)[id];
    if (b == null) {
      throw const LibraryFailure(
        'missing',
        'This book is not in your library.',
      );
    }
    return _get('objects', b['fileobjectid'] as String);
  }

  Future<void> update(String id, Map<String, dynamic> changes) async {
    _requireSession();
    final next = _copyCatalog();
    final b = (next['books'] as Map)[id] as Map?;
    if (b == null) throw const LibraryFailure('missing', 'Book not found.');
    for (final key in [
      'title',
      'author',
      'shelves',
      'bookmarks',
      'metadata_read',
    ]) {
      if (changes.containsKey(key)) b[key] = changes[key];
    }
    if (changes.containsKey('position')) b['position'] = changes['position'];
    if (changes.containsKey('settings')) next['settings'] = changes['settings'];
    await _commit(next);
  }

  Future<void> changePassword(String password) async {
    _requireSession();
    if (utf8.encode(password).length < 8) {
      throw const LibraryFailure(
        'password',
        'Use at least 8 bytes for your password.',
      );
    }
    final kdf = Map<String, dynamic>.from(_header['kdf'] as Map)
      ..['salt'] = base64Encode(CryptoCodec.randomBytes(32));
    final key = await codec.passwordKey(password, kdf);
    try {
      final box = await codec.seal(
        _master!,
        SecretKey(key),
        _header['vault_id'] as String,
      );
      final next = {
        ..._header,
        'kdf': kdf,
        'key_nonce': base64Encode(box.sublist(0, 24)),
        'wrapped_master_key': base64Encode(box.sublist(24)),
      };
      await _atomic(
        File(p.join(root.path, 'vault.json')),
        utf8.encode(jsonEncode(next)),
      );
      _header = next;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  Future<void> remove(String id) async {
    _requireSession();
    final next = _copyCatalog();
    if ((next['books'] as Map).remove(id) == null) {
      throw const LibraryFailure('missing', 'Book not found.');
    }
    // Commit the catalog first. Historical ciphertext is retained; backups
    // include only objects reachable from the current catalog.
    await _commit(next);
  }

  Future<Uint8List> backup() async {
    _requireSession();
    final snapshot = (await File(
      p.join(root.path, 'HEAD'),
    ).readAsString()).trim();
    final originals = {
      for (final book in books())
        'objects/${book.objectId.substring(0, 2)}/${book.objectId}': book,
    };
    final names = _reachableFiles(snapshot);
    final archive = Archive();
    final manifest = <String, String>{};
    int total = 0;
    for (final name in names) {
      final data = await File(p.join(root.path, name)).readAsBytes();
      total += data.length;
      if (total > 128 * 1024 * 1024) {
        throw const LibraryFailure(
          'limit',
          'Backup exceeds this prototype’s 128 MB limit.',
        );
      }
      // Authenticate the exact ciphertext going into the ZIP, rather than
      // rereading files after a separate dry run.
      if (name == 'vault.json') {
        if (jsonEncode(jsonDecode(utf8.decode(data))) != jsonEncode(_header)) {
          throw const LibraryFailure(
            'backup',
            'Archive header changed. Reopen your archive before backing it up.',
          );
        }
      } else if (name == 'HEAD') {
        if (utf8.decode(data).trim() != snapshot) {
          throw const LibraryFailure(
            'backup',
            'Archive root changed. Reopen your archive before backing it up.',
          );
        }
      } else {
        final book = originals[name];
        Uint8List? plaintext;
        try {
          plaintext = await _openPayload(
            book == null ? 'snapshots' : 'objects',
            book == null ? snapshot : book.objectId,
            data,
          );
          if (book != null) {
            _verifyOriginal(book, plaintext, 'backup');
          } else if (jsonEncode(jsonDecode(utf8.decode(plaintext))) !=
              jsonEncode(_catalog)) {
            throw const LibraryFailure(
              'backup',
              'Library catalog changed. Reopen your archive before backing it up.',
            );
          }
        } on LibraryFailure catch (e) {
          if (book == null) rethrow;
          throw LibraryFailure(
            e.code,
            'Cannot back up "${book.title}": its original failed integrity verification.',
          );
        } finally {
          plaintext?.fillRange(0, plaintext.length, 0);
        }
      }
      manifest[name] = hashes.sha256.convert(data).toString();
      archive.addFile(ArchiveFile(name, data.length, data));
    }
    final report = utf8.encode(jsonEncode({'version': 1, 'files': manifest}));
    archive.addFile(ArchiveFile('manifest.json', report.length, report));
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
    _verifyBackup(encoded);
    return encoded;
  }

  Map<String, dynamic> preferences() {
    _requireSession();
    return Map<String, dynamic>.from(_catalog['settings'] as Map? ?? {});
  }

  Future<void> savePreferences(Map<String, dynamic> values) async {
    _requireSession();
    final next = _copyCatalog()..['settings'] = values;
    await _commit(next);
  }

  Map<String, Uint8List> _verifyBackup(Uint8List bytes) {
    final zip = safeZip(bytes, maxBytes: 256 * 1024 * 1024, maxEntries: 10000);
    final files = <String, Uint8List>{};
    for (final entry in zip.where((f) => f.isFile)) {
      files[entry.name] = entry.readBytes()!;
    }
    final manifestBytes = files.remove('manifest.json');
    if (manifestBytes == null) {
      throw const LibraryFailure('backup', 'Backup manifest is missing.');
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
    if (manifest['version'] != 1) {
      throw const LibraryFailure('backup', 'Unsupported backup format.');
    }
    final expected = manifest['files'] as Map;
    if (expected.length != files.length ||
        !files.containsKey('vault.json') ||
        !files.containsKey('HEAD')) {
      throw const LibraryFailure('backup', 'Backup is incomplete.');
    }
    for (final e in files.entries) {
      if (e.key != 'vault.json' &&
          e.key != 'HEAD' &&
          !RegExp(
            r'^(snapshots/[a-f0-9-]{36}|objects/[a-f0-9]{2}/[a-f0-9-]{36})$',
          ).hasMatch(e.key)) {
        throw const LibraryFailure('backup', 'Unexpected file in backup.');
      }
      if (expected[e.key] != hashes.sha256.convert(e.value).toString()) {
        throw const LibraryFailure(
          'backup',
          'Backup checksum verification failed.',
        );
      }
    }
    return files;
  }

  Future<void> restore(
    Uint8List bytes,
    String secret, {
    bool recovery = false,
  }) async {
    // Validate in a fresh sibling directory before changing the current archive.
    final files = _verifyBackup(bytes);
    final stage = Directory('${root.path}.restore-${CryptoCodec.newId()}');
    final previous = Directory('${root.path}.previous');
    if (await previous.exists()) {
      throw const LibraryFailure(
        'restore',
        'A previous archive needs attention before another restore.',
      );
    }
    final verifier = VaultStore(stage);
    bool swapped = false;
    try {
      await stage.create(recursive: true);
      for (final e in files.entries) {
        await _atomic(File(p.join(stage.path, e.key)), e.value);
      }
      await verifier.unlock(secret, recovery: recovery);
      final snapshot = utf8.decode(files['HEAD']!).trim();
      final allowed = verifier._reachableFiles(snapshot);
      if (files.keys.any((name) => !allowed.contains(name))) {
        throw const LibraryFailure(
          'restore',
          'Backup contains extraneous unverified files.',
        );
      }
      if (!allowed.every(files.containsKey)) {
        throw const LibraryFailure(
          'restore',
          'Backup is missing a referenced object.',
        );
      }
      for (final b in verifier.books()) {
        final data = await verifier.read(b.id);
        try {
          _verifyOriginal(b, data, 'restore');
        } finally {
          data.fillRange(0, data.length, 0);
        }
      }
      verifier.lock();
      lock();
      if (await root.exists()) await root.rename(previous.path);
      try {
        await stage.rename(root.path);
        swapped = true;
      } catch (_) {
        if (await previous.exists()) await previous.rename(root.path);
        rethrow;
      }
      await unlock(secret, recovery: recovery);
      // Preserve previous ciphertext; no destructive cleanup during restoration.
    } finally {
      verifier.lock();
      if (!swapped && await stage.exists()) await stage.delete(recursive: true);
    }
  }

  Map<String, dynamic> _copyCatalog() =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_catalog)) as Map);
  Set<String> _reachableFiles(String snapshot) {
    CryptoCodec.requireId(snapshot);
    return {
      'vault.json',
      'HEAD',
      'snapshots/$snapshot',
      for (final book in books())
        'objects/${book.objectId.substring(0, 2)}/${book.objectId}',
    };
  }

  void _verifyOriginal(Book book, Uint8List data, String code) {
    if (data.length != book.size ||
        (book.hash.isNotEmpty &&
            hashes.sha256.convert(data).toString() != book.hash)) {
      throw LibraryFailure(
        code,
        'Original does not match its catalog size or checksum.',
      );
    }
  }

  Future<void> _commit(Map<String, dynamic> next) async {
    final id = await _put('snapshots', utf8.encode(jsonEncode(next)));
    await _atomic(File(p.join(root.path, 'HEAD')), utf8.encode('$id\n'));
    _catalog = next;
  }

  Future<String> _put(String kind, List<int> data) async {
    _requireSession();
    final id = CryptoCodec.newId();
    final key = await codec.objectKey(
      _master!,
      _header['vault_id'] as String,
      id,
    );
    final bytes = await codec.seal(data, key, id);
    await _atomic(_objectFile(kind, id), bytes);
    return id;
  }

  Future<Uint8List> _get(String kind, String id) async {
    _requireSession();
    CryptoCodec.requireId(id);
    final file = _objectFile(kind, id);
    if (await file.length() > 40 * 1024 * 1024) {
      throw const LibraryFailure(
        'limit',
        'Object is too large for this prototype.',
      );
    }
    final bytes = await file.readAsBytes();
    return _openPayload(kind, id, bytes);
  }

  Future<Uint8List> _openPayload(
    String kind,
    String id,
    Uint8List bytes,
  ) async {
    _requireSession();
    CryptoCodec.requireId(id);
    if (bytes.length > 40 * 1024 * 1024) {
      throw const LibraryFailure(
        'limit',
        'Object is too large for this prototype.',
      );
    }
    final key = await codec.objectKey(
      _master!,
      _header['vault_id'] as String,
      id,
    );
    return codec.open(bytes, key, id);
  }

  File _objectFile(String kind, String id) => File(
    kind == 'objects'
        ? p.join(root.path, kind, id.substring(0, 2), id)
        : p.join(root.path, kind, id),
  );
  Future<void> _atomic(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${CryptoCodec.newId()}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
