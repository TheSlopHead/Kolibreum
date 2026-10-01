import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/crypto_codec.dart';

void main() {
  test(
    'Dart reads independent Go Argon2id/HKDF/XChaCha20-Poly1305 vectors',
    () async {
      final v =
          jsonDecode(
                await File('test/fixtures/go-vault-v1.json').readAsString(),
              )
              as Map<String, dynamic>;
      final codec = CryptoCodec();
      final key = await codec.passwordKey(v['password'] as String, {
        'salt': v['salt'],
        'time': 1,
        'memory': 64,
        'threads': 1,
      });
      expect(base64Encode(key), v['password_key']);
      final object = await codec.objectKey(
        base64Decode(v['master'] as String),
        v['vault_id'] as String,
        v['object_id'] as String,
      );
      expect(base64Encode(await object.extractBytes()), v['object_key']);
      final plain = await codec.open(
        base64Decode(v['payload'] as String),
        object,
        v['object_id'] as String,
      );
      expect(base64Encode(plain), v['plaintext']);
      final master = await codec.open(
        [
          ...base64Decode(v['nonce'] as String),
          ...base64Decode(v['wrapped_master'] as String),
        ],
        SecretKey(key),
        v['vault_id'] as String,
      );
      expect(base64Encode(master), v['master']);
    },
  );
}
