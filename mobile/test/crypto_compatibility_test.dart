import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/crypto_codec.dart';
import 'package:mut_mobile/domain/library_repository.dart';

void main() {
  test('Dart reads legacy Go v1 vectors for migration', () async {
    final v =
        jsonDecode(await File('test/fixtures/go-vault-v1.json').readAsString())
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
  });
  test(
    'Dart reads Go v2 entity vectors and rejects swapped domains and AAD',
    () async {
      final vector =
          jsonDecode(
                await File('test/fixtures/go-vault-v2.json').readAsString(),
              )
              as Map;
      final codec = CryptoCodec();
      final master = base64Decode(vector['master'] as String);
      final vaultId = vector['vault_id'] as String;
      final keys = <String>[];
      for (final raw in vector['entities'] as List) {
        final entity = raw as Map;
        final kind = entity['kind'] as String;
        final id = entity['id'] as String;
        final aad = CryptoCodec.entityContext(kind, id);
        expect(aad, entity['aad']);
        expect('mut:$aad', entity['hkdf_info']);
        final key = await codec.entityKey(master, vaultId, kind, id);
        keys.add(base64Encode(await key.extractBytes()));
        expect(keys.last, entity['key']);
        final payload = base64Decode(entity['payload'] as String);
        expect(
          base64Encode(await codec.open(payload, key, aad)),
          entity['plaintext'],
        );
        final otherKind = kind == 'object' ? 'snapshot' : 'object';
        final otherKey = await codec.entityKey(master, vaultId, otherKind, id);
        final failure = isA<LibraryFailure>().having(
          (e) => e.code,
          'code',
          'authentication',
        );
        // Independently test KDF separation and AAD binding.
        await expectLater(codec.open(payload, otherKey, aad), throwsA(failure));
        await expectLater(
          codec.open(payload, key, '$otherKind:$id'),
          throwsA(failure),
        );
        await expectLater(codec.open(payload, key, id), throwsA(failure));
      }
      expect(keys[0], isNot(keys[1]));
    },
  );
}
