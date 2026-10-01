import 'package:flutter/foundation.dart';
import '../data/book_decoder.dart';
import '../domain/book.dart';
import '../domain/library_repository.dart';

enum LibraryStatus { loading, absent, locked, unlocked }

class LibraryController extends ChangeNotifier {
  LibraryController(this.repository);
  final LibraryRepository repository;
  LibraryStatus status = LibraryStatus.loading;
  List<Book> books = [];
  Book? current;
  ReaderDocument? document;
  Uint8List? pdf;
  bool busy = false;
  int _generation = 0;
  bool hasArchive = false;
  (String, String, double)? _pendingPosition;
  double fontSize = 18;
  double lineHeight = 1.56;
  int pageColor = 0;
  String? backupReport;
  Future<void> initialize() async {
    hasArchive = await repository.exists();
    status = hasArchive ? LibraryStatus.locked : LibraryStatus.absent;
    notifyListeners();
  }

  Future<T> task<T>(Future<T> Function() operation) async {
    if (busy) {
      throw const LibraryFailure(
        'busy',
        'Wait for the current operation to finish.',
      );
    }
    busy = true;
    notifyListeners();
    try {
      return await operation();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String> create(String password) => task(() async {
    final generation = _generation;
    final code = await repository.create(password);
    hasArchive = true;
    if (generation != _generation) {
      status = LibraryStatus.locked;
      await repository.lock();
      throw const LibraryFailure(
        'locked',
        'Archive locked while creating. Unlock it again.',
      );
    }
    return code;
  });
  Future<void> finishCreation() async {
    if (status != LibraryStatus.absent) return;
    status = LibraryStatus.unlocked;
    await _loadPreferences();
    await refresh();
  }

  Future<void> restore(
    Uint8List bytes,
    String secret, {
    bool recovery = false,
  }) => task(() async {
    final generation = _generation;
    await repository.restore(bytes, secret, recovery: recovery);
    hasArchive = true;
    if (generation != _generation) {
      status = LibraryStatus.locked;
      await repository.lock();
      return;
    }
    closeReader();
    status = LibraryStatus.unlocked;
    await _loadPreferences();
    await refresh();
  });
  Future<void> unlock(String secret, {bool recovery = false}) => task(() async {
    final generation = _generation;
    await repository.unlock(secret, recovery: recovery);
    if (generation != _generation) {
      await repository.lock();
      return;
    }
    status = LibraryStatus.unlocked;
    await _loadPreferences();
    await refresh();
  });
  Future<void> refresh() async {
    final generation = _generation;
    final loaded = await repository.books();
    if (generation != _generation || status != LibraryStatus.unlocked) return;
    books = loaded;
    if (current != null) {
      current = books.where((b) => b.id == current!.id).firstOrNull;
    }
    notifyListeners();
  }

  Future<void> lock() async {
    _generation++;
    closeReader();
    books = [];
    backupReport = null;
    status = hasArchive ? LibraryStatus.locked : LibraryStatus.absent;
    notifyListeners();
    await repository.lock();
  }

  void closeReader() {
    pdf?.fillRange(0, pdf!.length, 0);
    pdf = null;
    document = null;
    current = null;
    _pendingPosition = null;
  }

  void stagePosition(String id, String locator, double progress) {
    _pendingPosition = (id, locator, progress);
  }

  Future<void> flushPosition() async {
    final pending = _pendingPosition;
    if (pending != null && status == LibraryStatus.unlocked) {
      await position(pending.$1, pending.$2, pending.$3);
    }
  }

  Future<void> open(Book book) => task(() async {
    final generation = _generation;
    final bytes = await repository.read(book.id);
    if (generation != _generation) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    closeReader();
    try {
      if (book.format == 'PDF') {
        if (bytes.length < 5 ||
            String.fromCharCodes(bytes.take(5)) != '%PDF-') {
          throw const LibraryFailure('pdf', 'This file is not a valid PDF.');
        }
        pdf = bytes;
      } else {
        final decoded = await compute(decodeBookPayload, (
          bytes,
          book.format,
          book.title,
        ));
        if (generation != _generation) return;
        document = decoded;
        if (!book.metadataRead) {
          await repository.update(book.id, {
            'title': decoded.title,
            'author': decoded.author,
            'metadata_read': true,
          });
        }
      }
      if (generation != _generation) {
        closeReader();
        return;
      }
      current = book;
      await refresh();
    } finally {
      if (pdf != bytes) bytes.fillRange(0, bytes.length, 0);
    }
  });
  Future<void> position(String id, String locator, double progress) async {
    if (status != LibraryStatus.unlocked) return;
    await repository.update(id, {
      'position': {
        'locator': locator,
        'progress': progress.clamp(0, 1),
        'updateat': DateTime.now().toUtc().toIso8601String(),
      },
    });
    await refresh();
  }

  Future<void> bookmark(Book book, String locator) async {
    final marks = [...book.bookmarks];
    marks.contains(locator) ? marks.remove(locator) : marks.add(locator);
    await repository.update(book.id, {'bookmarks': marks});
    await refresh();
  }

  void appearance({double? size, double? height, int? color}) {
    fontSize = (size ?? fontSize).clamp(14, 28);
    lineHeight = height ?? lineHeight;
    pageColor = color ?? pageColor;
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    final values = await repository.preferences();
    fontSize = (values['fontSize'] as num? ?? 18).toDouble().clamp(14, 28);
    lineHeight = (values['lineHeight'] as num? ?? 1.56).toDouble().clamp(
      1.35,
      1.8,
    );
    pageColor = (values['pageColor'] as int? ?? 0).clamp(0, 2);
  }

  Future<void> saveAppearance() async {
    if (status != LibraryStatus.unlocked) return;
    await repository.savePreferences({
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'pageColor': pageColor,
    });
  }
}
