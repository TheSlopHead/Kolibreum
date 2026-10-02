import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../domain/library_repository.dart';

/// HKDF-SHA256 and nonce | ciphertext | tag. The v1 KDF is migration-only.
class CryptoCodec {
  final cipher = Xchacha20.poly1305Aead();
  static Uint8List randomBytes(int count) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
  }

  static String newId() {
    final b = randomBytes(16);
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static void requireId(String id) {
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(id)) {
      throw const LibraryFailure('corrupt', 'Invalid archive identifier.');
    }
  }

  Future<Uint8List> passwordKey(
    String password,
    Map<String, dynamic> kdf,
  ) async {
    final memory = kdf['memory'] as int;
    final iterations = kdf['time'] as int;
    final lanes = kdf['threads'] as int;
    final salt = base64Decode(kdf['salt'] as String);
    if (memory < 32 ||
        memory > 131072 ||
        iterations < 1 ||
        iterations > 6 ||
        lanes < 1 ||
        lanes > 8 ||
        salt.length != 32) {
      throw const LibraryFailure('kdf', 'Unsupported archive KDF parameters.');
    }
    final key = await Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: lanes,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<SecretKey> objectKey(List<int> master, String vaultId, String id) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(master),
        nonce: utf8.encode(vaultId),
        info: utf8.encode('mut:object$id'),
      );

  static String entityContext(String kind, String id) {
    if (kind != 'object' && kind != 'snapshot') {
      throw const LibraryFailure('corrupt', 'Invalid encryption domain.');
    }
    requireId(id);
    return '$kind:$id';
  }

  Future<SecretKey> entityKey(
    List<int> master,
    String vaultId,
    String kind,
    String id,
  ) => Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey(master),
    nonce: utf8.encode(vaultId),
    info: utf8.encode('mut:${entityContext(kind, id)}'),
  );
  Future<Uint8List> seal(List<int> data, SecretKey key, String aad) async {
    final box = await cipher.encrypt(
      data,
      secretKey: key,
      nonce: randomBytes(24),
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> open(List<int> payload, SecretKey key, String aad) async {
    if (payload.length < 40) {
      throw const LibraryFailure('corrupt', 'Truncated encrypted object.');
    }
    try {
      return Uint8List.fromList(
        await cipher.decrypt(
          SecretBox(
            payload.sublist(24, payload.length - 16),
            nonce: payload.sublist(0, 24),
            mac: Mac(payload.sublist(payload.length - 16)),
          ),
          secretKey: key,
          aad: utf8.encode(aad),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const LibraryFailure(
        'authentication',
        'Incorrect secret or damaged archive.',
      );
    }
  }
}
