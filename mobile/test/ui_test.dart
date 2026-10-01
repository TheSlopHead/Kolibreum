import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/app/library_controller.dart';
import 'package:mut_mobile/app/mut_app.dart';
import 'package:mut_mobile/domain/book.dart';
import 'package:mut_mobile/domain/library_repository.dart';
import 'package:mut_mobile/platform/documents.dart';

class TestRepository implements LibraryRepository {
  bool locked = false;
  Completer<Uint8List>? pendingRead;
  List<Book> items = List.generate(
    12,
    (i) => Book(
      id: 'book-$i',
      title: [
        'Orbits of Silence',
        'Map of Winds',
        'After the Rain',
        'Garden of Observations',
        'Northern Light',
        'Fields of Memory',
        'A Little Geology',
        'Letters to the Sea',
        'Winter Room',
        'Clocks Without Hands',
        'Inside Noon',
        'Thin Line',
      ][i],
      author: ['Mira Holm', 'Anton Ray', 'Leya Snow', 'I. Polevoy'][i % 4],
      format: 'FB2',
      objectId: 'object-$i',
      size: 2400000,
      progress: i == 0 ? .42 : 0,
      locator: i == 0 ? 'text-v1:0:0.42' : '',
      shelves: [i % 2 == 0 ? 'Bedtime' : 'Travel'],
    ),
  );
  @override
  Future<bool> exists() async => true;
  @override
  Future<List<Book>> books() async =>
      locked ? throw const LibraryFailure('locked', 'Locked') : items;
  @override
  Future<void> unlock(String secret, {bool recovery = false}) async {
    if (secret != 'password') {
      throw const LibraryFailure('password', 'Incorrect password');
    }
    locked = false;
  }

  @override
  Future<void> lock() async {
    locked = true;
  }

  static Uint8List readingBytes() => Uint8List.fromList(
    utf8.encode(
      '<FictionBook><description><title-info><book-title>Orbits of Silence</book-title></title-info></description><body><section><title><p>The Silence That Has an Orbit</p></title><p>At noon, light fell across the shelves in even bands.</p><p>Everything important moves slowly.</p></section></body></FictionBook>',
    ),
  );
  @override
  Future<Uint8List> read(String id) =>
      pendingRead?.future ?? Future.value(readingBytes());
  @override
  Future<void> update(String id, Map<String, dynamic> changes) async {
    final i = items.indexWhere((b) => b.id == id);
    if (i >= 0) items[i] = Book.fromJson({...items[i].toJson(), ...changes});
  }

  @override
  Future<String> create(String password) async => 'recovery-code';
  @override
  Future<String> importFile(
    String name,
    Uint8List bytes, {
    bool keepDuplicate = false,
  }) async => 'import';
  @override
  Future<Uint8List> backup() async => Uint8List(0);
  @override
  Future<void> restore(
    Uint8List bytes,
    String secret, {
    bool recovery = false,
  }) async {}
  @override
  Future<void> changePassword(String password) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<Map<String, dynamic>> preferences() async => {};
  @override
  Future<void> savePreferences(Map<String, dynamic> values) async {}
}

class TestDocuments implements Documents {
  @override
  Future<PickedDocument?> pick({bool backup = false}) async => null;
  @override
  Future<bool> save(
    String name,
    Uint8List bytes, {
    bool verify = false,
  }) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['Onest', 'Literata']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
  });
  for (final interrupt in [false, true]) {
    testWidgets(
      interrupt
          ? 'locking closes the one-time recovery dialog'
          : 'creation requires recovery confirmation before showing the library',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = TestRepository()..items = [];
        final controller = LibraryController(repository)
          ..status = LibraryStatus.absent;
        await tester.pumpWidget(
          MutApp(controller: controller, documents: TestDocuments()),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(0), 'password');
        await tester.enterText(find.byType(TextField).at(1), 'password');
        await tester.ensureVisible(find.text('Create library'));
        await tester.tap(find.text('Create library'));
        await tester.pumpAndSettle();
        expect(find.text('recovery-code'), findsOneWidget);
        expect(controller.status, LibraryStatus.absent);
        if (interrupt) {
          await controller.lock();
          await tester.pumpAndSettle();
          expect(find.text('recovery-code'), findsNothing);
          expect(controller.status, LibraryStatus.locked);
        } else {
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'I have saved the code'),
                )
                .onPressed,
            isNull,
          );
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            'y-code',
          );
          await tester.pump();
          await tester.tap(find.text('I have saved the code'));
          await tester.pumpAndSettle();
          expect(controller.status, LibraryStatus.unlocked);
          expect(find.text('recovery-code'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
  for (final dimensions in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(600, 960),
  ]) {
    testWidgets(
      'Paper screens fit ${dimensions.width}×${dimensions.height}, and lock removes book data',
      (tester) async {
        tester.view.physicalSize = dimensions;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = TestRepository();
        final controller = LibraryController(repository)
          ..hasArchive = true
          ..status = LibraryStatus.unlocked;
        await controller.refresh();
        await tester.pumpWidget(
          MutApp(controller: controller, documents: TestDocuments()),
        );
        await tester.pumpAndSettle();
        expect(find.text('All books'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (dimensions.width == 390) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/library.png'),
          );
        }
        await tester.tap(find.text('Search').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Mira');
        await tester.pumpAndSettle();
        expect(find.text('3 books found'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Archive').last);
        await tester.pumpAndSettle();
        expect(find.text('Your archive'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Library').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Orbits of Silence').first);
        await tester.pumpAndSettle();
        expect(find.text('Book details'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (dimensions.width == 390) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/book-details.png'),
          );
        }
        await tester.ensureVisible(find.text('Continue reading'));
        await tester.tap(find.text('Continue reading'));
        await tester.runAsync(() async {
          for (int i = 0; controller.busy && i < 200; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(
          find.text('At noon, light fell across the shelves in even bands.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Aa'));
        await tester.pumpAndSettle();
        expect(find.text('Reading appearance'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (dimensions.width == 390) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/appearance.png'),
          );
        }
        await controller.lock();
        await tester.pumpAndSettle();
        expect(find.text('Reading appearance'), findsNothing);
        expect(find.text('Orbits of Silence'), findsNothing);
        expect(find.text('Unlock library'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (dimensions.width == 390) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/locked.png'),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );
  }
  test('opening a book preserves manually edited catalog metadata', () async {
    final repository = TestRepository();
    final id = repository.items.first.id;
    await repository.update(id, {
      'title': 'My title',
      'author': 'My author',
      'metadata_read': true,
    });
    final controller = LibraryController(repository)
      ..status = LibraryStatus.unlocked;
    await controller.open(repository.items.first);
    expect(controller.current!.title, 'My title');
    expect(controller.current!.author, 'My author');
    expect(controller.document!.chapters, isNotEmpty);
    await controller.lock();
    controller.dispose();
  });
  test('a book read finishing after lock cannot reopen the reader', () async {
    final repository = TestRepository()..pendingRead = Completer<Uint8List>();
    final controller = LibraryController(repository)
      ..hasArchive = true
      ..status = LibraryStatus.unlocked;
    final opening = controller.open(repository.items.first);
    await controller.lock();
    repository.pendingRead!.complete(TestRepository.readingBytes());
    await opening;
    expect(controller.status, LibraryStatus.locked);
    expect(controller.current, isNull);
    expect(controller.document, isNull);
    expect(controller.pdf, isNull);
    expect(controller.books, isEmpty);
    controller.dispose();
  });
}
