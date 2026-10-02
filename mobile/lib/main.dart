import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app/library_controller.dart';
import 'app/mut_app.dart';
import 'data/isolate_repository.dart';
import 'data/vault_store.dart';
import 'platform/documents.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xff151718),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  final application = await getApplicationSupportDirectory();
  final root = Directory(p.join(application.path, 'vault'));
  // Recover an interrupted directory swap; never choose an unverified staging directory.
  await VaultStore.recoverInterruptedSwap(root);
  final repository = await IsolateLibraryRepository.start(root.path);
  final controller = LibraryController(repository);
  await controller.initialize();
  runApp(MutApp(controller: controller, documents: AndroidDocuments()));
}
