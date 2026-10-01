import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/app/library_controller.dart';
import 'package:mut_mobile/platform/documents.dart';

import 'ui_test.dart' show TestDocuments, TestRepository;

class _SlowCancellation extends TestDocuments {
  final completed = Completer<void>();
  @override
  Future<void> cancel() => completed.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android cancellation reaches the channel while save is pending',
    () async {
      final result = Completer<bool>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidDocuments.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'save') return result.future;
        if (call.method == 'cancel') result.complete(false);
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(AndroidDocuments.channel, null),
      );
      final documents = AndroidDocuments();
      final saving = documents.save(
        'original.txt',
        Uint8List.fromList([1, 2, 3]),
      );
      await documents.cancel();
      expect(await saving, false);
      expect(calls, ['save', 'cancel']);
    },
  );

  test(
    'a slow platform cancellation does not delay hiding or locking',
    () async {
      final repository = TestRepository();
      final documents = _SlowCancellation();
      final controller = LibraryController(repository, documents: documents)
        ..hasArchive = true
        ..status = LibraryStatus.unlocked;
      await controller.refresh();
      final locking = controller.lock();
      expect(controller.status, LibraryStatus.locked);
      expect(controller.books, isEmpty);
      expect(repository.locked, true);
      documents.completed.complete();
      await locking;
      controller.dispose();
    },
  );

  test(
    'a failed platform cancellation cannot keep the repository unlocked',
    () async {
      final repository = TestRepository();
      final documents = _SlowCancellation();
      final controller = LibraryController(repository, documents: documents)
        ..hasArchive = true
        ..status = LibraryStatus.unlocked;
      final locking = controller.lock();
      documents.completed.completeError(PlatformException(code: 'closed'));
      await locking;
      expect(controller.status, LibraryStatus.locked);
      expect(repository.locked, true);
      controller.dispose();
    },
  );
}
