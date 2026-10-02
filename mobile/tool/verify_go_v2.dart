// Run from mobile/: flutter test --no-pub tool/verify_go_v2.dart
// Optional bilateral check: Go must be installed with the module dependencies.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/data/crypto_codec.dart';

void main() {
  test('Go authenticates ciphertext written by the mobile v2 codec', () async {
    final vector =
        jsonDecode(await File('test/fixtures/go-vault-v2.json').readAsString())
            as Map;
    final codec = CryptoCodec();
    final master = base64Decode(vector['master'] as String);
    final vaultId = vector['vault_id'] as String;
    final entities = <Map<String, dynamic>>[];
    for (final raw in vector['entities'] as List) {
      final entity = raw as Map;
      final kind = entity['kind'] as String;
      final id = entity['id'] as String;
      final plaintext = base64Decode(entity['plaintext'] as String);
      final key = await codec.entityKey(master, vaultId, kind, id);
      final payload = await codec.seal(
        plaintext,
        key,
        CryptoCodec.entityContext(kind, id),
      );
      entities.add({
        'kind': kind,
        'id': id,
        'payload': base64Encode(payload),
        'plaintext': base64Encode(plaintext),
      });
    }
    final temp = await Directory.systemTemp.createTemp('mut-go-v2-');
    try {
      final file = File('${temp.path}/interop.json');
      await file.writeAsString(
        jsonEncode({
          'vault_id': vaultId,
          'master': vector['master'],
          'entities': entities,
        }),
      );
      final result = await Process.run('go', [
        'run',
        'mobile/tool/go_vectors.go',
        '-verify',
        file.path,
      ], workingDirectory: '..');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('Go authenticated 2 mobile v2 payloads'));
    } finally {
      master.fillRange(0, master.length, 0);
      await temp.delete(recursive: true);
    }
  });
}
