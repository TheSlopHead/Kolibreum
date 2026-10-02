import 'dart:typed_data';
import 'book.dart';

class LibraryFailure implements Exception {
  const LibraryFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

abstract interface class LibraryRepository {
  Future<bool> exists();
  Future<String> create(String password);
  Future<void> unlock(String secret, {bool recovery = false});
  Future<void> lock();
  Future<List<Book>> books();
  Future<String> importFile(
    String name,
    Uint8List bytes, {
    bool keepDuplicate = false,
  });
  Future<Uint8List> read(String id);
  Future<Uint8List?> readCover(String id);
  Future<void> update(String id, Map<String, dynamic> changes);
  Future<void> remove(String id);
  Future<Uint8List> backup();
  Future<void> restore(Uint8List bytes, String secret, {bool recovery = false});
  Future<void> changePassword(String password);
  Future<Map<String, dynamic>> preferences();
  Future<void> savePreferences(Map<String, dynamic> values);
  Future<void> dispose();
}
