import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:mut_mobile/data/vault_store.dart';

/// Independent fixture conversion: seal every entity with the original v1
/// HKDF/AAD. Production code never writes v1 ciphertext.
Future<Map<String, Uint8List>> makeLegacyVault(
  VaultStore vault,
  String recovery,
) async {
  final root = vault.root.path;
  final headerFile = File('$root/vault.json');
  final header =
      jsonDecode(await headerFile.readAsString()) as Map<String, dynamic>;
  final master = await vault.codec.open(
    base64Decode(header['mobile_recovery'] as String),
    SecretKey(base64Url.decode(base64Url.normalize(recovery))),
    '${header['vault_id']}:recovery',
  );
  vault.lock();
  try {
    for (final kind in ['objects', 'snapshots']) {
      final directory = Directory('$root/$kind');
      if (!await directory.exists()) continue;
      for (final file
          in await directory
              .list(recursive: true)
              .where((f) => f is File)
              .cast<File>()
              .toList()) {
        final id = file.uri.pathSegments.last;
        final domain = kind == 'objects' ? 'object' : 'snapshot';
        final key = await vault.codec.entityKey(
          master,
          header['vault_id'] as String,
          domain,
          id,
        );
        final data = await vault.codec.open(
          await file.readAsBytes(),
          key,
          '$domain:$id',
        );
        try {
          final legacyKey = await vault.codec.objectKey(
            master,
            header['vault_id'] as String,
            id,
          );
          await file.writeAsBytes(await vault.codec.seal(data, legacyKey, id));
        } finally {
          data.fillRange(0, data.length, 0);
        }
      }
    }
    header['version'] = 1;
    await headerFile.writeAsString(jsonEncode(header));
    return {
      for (final file
          in await vault.root
              .list(recursive: true)
              .where((f) => f is File)
              .cast<File>()
              .toList())
        file.path.substring(root.length + 1): await file.readAsBytes(),
    };
  } finally {
    master.fillRange(0, master.length, 0);
  }
}
