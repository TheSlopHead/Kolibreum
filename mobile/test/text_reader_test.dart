import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/domain/book.dart';
import 'package:mut_mobile/features/reader/text_pagination.dart';
import 'package:mut_mobile/features/reader/text_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final name in ['Onest', 'Literata']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
  });

  Future<List<TextReaderPage>> layout(
    ReaderDocument document, {
    double fontSize = 18,
    Size size = const Size(288, 450),
  }) => paginateText(
    document,
    size: size,
    fontSize: fontSize,
    lineHeight: 1.56,
    scaler: TextScaler.noScaling,
    direction: TextDirection.ltr,
    cancelled: () => false,
  );

  test(
    'pagination preserves every character of oversized paragraphs and chapter order',
    () async {
      final paragraph = List.generate(1400, (i) => 'Слово $i 🌙. ').join();
      final document = ReaderDocument('Book', '', [
        ReaderChapter('a', 'First chapter', [paragraph]),
        const ReaderChapter('b', 'Second chapter', ['The end.']),
      ]);
      final pages = await layout(document);
      expect(pages.length, greaterThan(10));
      expect(pages.first.chapter, 0);
      expect(pages.last.chapter, 1);
      final recovered = pages
          .where((page) => page.chapter == 0)
          .expand((page) => page.fragments)
          .where((fragment) => fragment.kind == FragmentKind.body)
          .map((fragment) => fragment.text)
          .join();
      expect(recovered, paragraph);
      expect(
        pages.where((page) => page.chapter == 0).map((page) => page.offset),
        orderedEquals(
          pages
              .where((page) => page.chapter == 0)
              .map((page) => page.offset)
              .toList()
            ..sort(),
        ),
      );
    },
  );

  test(
    'reflow keeps the text anchor and imports legacy chapter positions',
    () async {
      final document = ReaderDocument('Book', '', [
        ReaderChapter(
          'a',
          'First',
          List.generate(80, (i) => 'Paragraph $i. ${'Read quietly. ' * 15}'),
        ),
        const ReaderChapter('b', 'Second', ['End.']),
      ]);
      final small = await layout(document);
      final large = await layout(document, fontSize: 26);
      expect(large.length, greaterThan(small.length));
      final original = small[small.length ~/ 2];
      final index = pageForLocator(large, original.locator);
      expect(large[index].chapter, original.chapter);
      expect(large[index].offset, lessThanOrEqualTo(original.offset));
      expect(large[index + 1].offset, greaterThan(original.offset));
      expect(small[pageForLocator(small, 'text-v1:1:0.5')].chapter, 1);
      expect(pageForLocator(small, 'text-v1:0:NaN'), 0);
    },
  );

  test(
    'cancelled pagination stops without publishing a partial page map',
    () async {
      final document = ReaderDocument('Book', '', [
        ReaderChapter('a', 'Title', ['text ' * 10000]),
      ]);
      final pages = await paginateText(
        document,
        size: const Size(288, 450),
        fontSize: 18,
        lineHeight: 1.56,
        scaler: TextScaler.noScaling,
        direction: TextDirection.ltr,
        cancelled: () => true,
      );
      expect(pages, isEmpty);
    },
  );

  for (final size in [const Size(288, 420), const Size(358, 610)]) {
    testWidgets(
      'modes, resizing and lazy page rendering preserve reading position at $size',
      (tester) async {
        final document = ReaderDocument('Book', '', [
          ReaderChapter(
            'a',
            'The Silence That Has an Orbit',
            List.generate(
              150,
              (i) => 'Paragraph $i. ${'Words move slowly. ' * 18}',
            ),
          ),
          const ReaderChapter('b', 'Next chapter', ['The end.']),
        ]);
        final key = GlobalKey<TextReaderState>();
        (String, int, int)? position;
        Future<void> pump({
          bool paginated = true,
          double fontSize = 18,
          String locator = '',
        }) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: TextReader(
                    key: key,
                    document: document,
                    fontSize: fontSize,
                    lineHeight: 1.56,
                    ink: Colors.black,
                    paginated: paginated,
                    initialLocator: locator,
                    onPosition: (locator, page, total) =>
                        position = (locator, page, total),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pump();
        expect(position, isNotNull);
        expect(position!.$3, greaterThan(20));
        expect(find.byType(Text).evaluate().length, lessThan(30));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(PageView), Offset(-size.width * .7, 0));
        await tester.pumpAndSettle();
        expect(position!.$2, 2);
        key.currentState!.goToPage(8);
        await tester.pumpAndSettle();
        final anchor = position!.$1;
        await pump(paginated: false);
        expect(find.byType(ListView), findsOneWidget);
        expect(position!.$1, anchor);
        await tester.drag(find.byType(ListView), Offset(0, -size.height * 2));
        await tester.pumpAndSettle();
        expect(position!.$2, greaterThan(8));
        final scrolledPage = position!.$2;
        await pump();
        expect(position!.$2, scrolledPage);
        await pump(fontSize: 28);
        expect(tester.takeException(), isNull);
        final restored = position!.$1;
        await tester.pumpWidget(const SizedBox.shrink());
        await pump(fontSize: 28, locator: restored);
        expect(position!.$1, restored);
        key.currentState!.goToLocator('text-v2:1:0');
        await tester.pumpAndSettle();
        expect(find.text('Next chapter'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
