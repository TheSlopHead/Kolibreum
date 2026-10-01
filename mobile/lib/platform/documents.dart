import 'package:flutter/services.dart';

class PickedDocument {
  const PickedDocument(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract interface class Documents {
  Future<PickedDocument?> pick({bool backup = false});
  Future<bool> save(String name, Uint8List bytes, {bool verify = false});
  Future<void> cancel();
}

class AndroidDocuments implements Documents {
  static const channel = MethodChannel('dev.mut/documents');
  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
  @override
  Future<PickedDocument?> pick({bool backup = false}) async {
    final value = await channel.invokeMapMethod<String, dynamic>('pick', {
      'backup': backup,
    });
    if (value == null) return null;
    return PickedDocument(value['name'] as String, value['bytes'] as Uint8List);
  }

  @override
  Future<bool> save(
    String name,
    Uint8List bytes, {
    bool verify = false,
  }) async =>
      await channel.invokeMethod<bool>('save', {
        'name': name,
        'bytes': bytes,
        'verify': verify,
      }) ??
      false;
}
