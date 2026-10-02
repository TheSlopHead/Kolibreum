import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../domain/book.dart';
import '../domain/library_repository.dart';
import 'vault_store.dart';
import 'pdf_cover.dart';

class IsolateLibraryRepository implements LibraryRepository {
  IsolateLibraryRepository._(this._worker, this._send, this._receive);
  final Isolate _worker;
  final SendPort _send;
  final ReceivePort _receive;
  final _pending = <int, Completer<dynamic>>{};
  int _sequence = 0;
  int _session = 0;
  static Future<IsolateLibraryRepository> start(String path) async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    IsolateLibraryRepository? repository;
    receive.listen((dynamic message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      final m = message as List;
      final waiter = repository?._pending.remove(m[0]);
      if (m[1] == true) {
        waiter?.complete(m[2]);
      } else {
        waiter?.completeError(LibraryFailure(m[2] as String, m[3] as String));
      }
    });
    final worker = await Isolate.spawn(_entry, [receive.sendPort, path]);
    repository = IsolateLibraryRepository._(
      worker,
      await ready.future,
      receive,
    );
    return repository;
  }

  Future<dynamic> _call(
    String operation, [
    Map<String, dynamic> args = const {},
  ]) {
    final id = _sequence++;
    final result = Completer<dynamic>();
    _pending[id] = result;
    _send.send([id, operation, args]);
    return result.future;
  }

  @override
  Future<bool> exists() async => await _call('exists') as bool;
  @override
  Future<String> create(String password) async =>
      await _call('create', {'password': password}) as String;
  @override
  Future<void> unlock(String secret, {bool recovery = false}) async {
    await _call('unlock', {'secret': secret, 'recovery': recovery});
  }

  @override
  Future<void> lock() async {
    _session++;
    await _call('lock');
  }

  @override
  Future<List<Book>> books() async => (await _call('books') as List)
      .map((b) => Book.fromJson(Map<String, dynamic>.from(b as Map)))
      .toList();
  @override
  Future<String> importFile(
    String name,
    Uint8List bytes, {
    bool keepDuplicate = false,
  }) async {
    final session = _session;
    Uint8List? cover;
    try {
      if (p.extension(name).toUpperCase() == '.PDF') {
        cover = await renderPdfCover(bytes);
      }
      if (session != _session) {
        throw const LibraryFailure('locked', 'Archive locked during import.');
      }
      return await _call('import', {
            'name': name,
            'bytes': TransferableTypedData.fromList([bytes]),
            'keep': keepDuplicate,
            'pdfCover': cover == null
                ? null
                : TransferableTypedData.fromList([cover]),
          })
          as String;
    } finally {
      cover?.fillRange(0, cover.length, 0);
    }
  }

  @override
  Future<Uint8List> read(String id) async =>
      (await _call('read', {'id': id}) as TransferableTypedData)
          .materialize()
          .asUint8List();
  @override
  Future<Uint8List?> readCover(String id) async {
    final session = _session;
    final result = await _call('cover', {'id': id}) as List;
    final data = result[0] as TransferableTypedData?;
    if (data != null) return data.materialize().asUint8List();
    if (result[1] != true || session != _session) return null;
    final original = await read(id);
    Uint8List? cover;
    try {
      if (session != _session) return null;
      cover = await renderPdfCover(original);
      if (session != _session) return null;
      await _call('savePdfCover', {
        'id': id,
        'bytes': cover == null ? null : TransferableTypedData.fromList([cover]),
      });
      // Read back the normalized persisted thumbnail, just like EPUB and FB2.
      final saved = await _call('cover', {'id': id}) as List;
      return (saved[0] as TransferableTypedData?)?.materialize().asUint8List();
    } finally {
      original.fillRange(0, original.length, 0);
      cover?.fillRange(0, cover.length, 0);
    }
  }

  @override
  Future<void> update(String id, Map<String, dynamic> changes) async {
    await _call('update', {'id': id, 'changes': changes});
  }

  @override
  Future<void> remove(String id) async {
    await _call('remove', {'id': id});
  }

  @override
  Future<Uint8List> backup() async =>
      (await _call('backup') as TransferableTypedData)
          .materialize()
          .asUint8List();
  @override
  Future<void> restore(
    Uint8List bytes,
    String secret, {
    bool recovery = false,
  }) async {
    _session++;
    await _call('restore', {
      'bytes': TransferableTypedData.fromList([bytes]),
      'secret': secret,
      'recovery': recovery,
    });
  }

  @override
  Future<void> changePassword(String password) async {
    await _call('password', {'password': password});
  }

  @override
  Future<void> dispose() async {
    await lock();
    _worker.kill();
    _receive.close();
  }

  @override
  Future<Map<String, dynamic>> preferences() async =>
      Map<String, dynamic>.from(await _call('preferences') as Map);
  @override
  Future<void> savePreferences(Map<String, dynamic> values) async {
    await _call('savePreferences', values);
  }

  static void _entry(List<dynamic> startup) {
    final reply = startup[0] as SendPort;
    final store = VaultStore(Directory(startup[1] as String));
    final input = ReceivePort();
    reply.send(input.sendPort);
    // Serialize commands: no snapshot lost updates or concurrent key disposal.
    Future<void> queue = Future.value();
    input.listen((dynamic raw) {
      final command = raw as List;
      queue = queue.then((_) async {
        final id = command[0];
        final op = command[1];
        final a = command[2] as Map;
        try {
          dynamic value;
          switch (op) {
            case 'exists':
              value = await store.exists();
            case 'create':
              value = await store.create(a['password'] as String);
            case 'unlock':
              await store.unlock(
                a['secret'] as String,
                recovery: a['recovery'] as bool,
              );
            case 'lock':
              store.lock();
            case 'books':
              value = store.books().map((b) => b.toJson()).toList();
            case 'preferences':
              value = store.preferences();
            case 'savePreferences':
              await store.savePreferences(Map<String, dynamic>.from(a));
            case 'import':
              final bytes = (a['bytes'] as TransferableTypedData)
                  .materialize()
                  .asUint8List();
              final pdfCover = (a['pdfCover'] as TransferableTypedData?)
                  ?.materialize()
                  .asUint8List();
              try {
                value = await store.importFile(
                  a['name'] as String,
                  bytes,
                  keepDuplicate: a['keep'] as bool,
                  pdfCover: pdfCover,
                );
              } finally {
                bytes.fillRange(0, bytes.length, 0);
                pdfCover?.fillRange(0, pdfCover.length, 0);
              }
            case 'read':
              final bytes = await store.read(a['id'] as String);
              value = TransferableTypedData.fromList([bytes]);
              bytes.fillRange(0, bytes.length, 0);
            case 'cover':
              final bytes = await store.readCover(a['id'] as String);
              value = <dynamic>[null, store.needsPdfCover(a['id'] as String)];
              if (bytes != null) {
                value[0] = TransferableTypedData.fromList([bytes]);
                bytes.fillRange(0, bytes.length, 0);
              }
            case 'savePdfCover':
              final bytes = (a['bytes'] as TransferableTypedData?)
                  ?.materialize()
                  .asUint8List();
              try {
                await store.savePdfCover(a['id'] as String, bytes);
              } finally {
                bytes?.fillRange(0, bytes.length, 0);
              }
            case 'update':
              await store.update(
                a['id'] as String,
                Map<String, dynamic>.from(a['changes'] as Map),
              );
            case 'backup':
              value = TransferableTypedData.fromList([await store.backup()]);
            case 'remove':
              await store.remove(a['id'] as String);
            case 'restore':
              await store.restore(
                (a['bytes'] as TransferableTypedData)
                    .materialize()
                    .asUint8List(),
                a['secret'] as String,
                recovery: a['recovery'] as bool,
              );
            case 'password':
              await store.changePassword(a['password'] as String);
            default:
              throw const LibraryFailure(
                'operation',
                'Unknown archive operation.',
              );
          }
          reply.send([id, true, value]);
        } on LibraryFailure catch (e) {
          reply.send([id, false, e.code, e.message]);
        } catch (_) {
          reply.send([
            id,
            false,
            'archive',
            'Cannot complete this operation. The archive may be damaged or storage unavailable.',
          ]);
        }
      });
    });
  }
}
