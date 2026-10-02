// Run from mobile/: flutter test --no-pub tool/capture_screenshots.dart
// Captures Flutter widgets with a temporary demo vault; no device permissions
// or changes to Android FLAG_SECURE are required.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mut_mobile/app/library_controller.dart';
import 'package:mut_mobile/app/mut_app.dart';
import 'package:mut_mobile/data/isolate_repository.dart';
import 'package:mut_mobile/data/vault_store.dart';
import 'package:mut_mobile/platform/documents.dart';
import 'package:mut_mobile/ui/components.dart';

class _DemoDocuments implements Documents {
  @override
  Future<void> cancel() async {}
  @override
  Future<PickedDocument?> pick({bool backup = false}) async => null;
  @override
  Future<bool> save(
    String name,
    Uint8List bytes, {
    bool verify = false,
  }) async => false;
}

Future<Uint8List> _artwork(String title, String author, int variant) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final background = [
    const Color(0xff203737),
    const Color(0xff303348),
    const Color(0xff494335),
  ][variant];
  const paper = Color(0xffe6ded0);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 512, 768),
    Paint()..color = background,
  );
  canvas.drawRect(
    const Rect.fromLTWH(24, 24, 464, 720),
    Paint()
      ..color = paper.withValues(alpha: .25)
      ..style = PaintingStyle.stroke,
  );
  canvas.save();
  canvas.translate(256, 450);
  canvas.rotate(-.35 + variant * .2);
  for (var i = 0; i < 9; i++) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 100 + i * 30, height: 260),
      Paint()
        ..color = paper.withValues(alpha: .4 + i * .04)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
  canvas.drawCircle(
    Offset(120 * math.cos(variant + .5), 90 * math.sin(variant + .5)),
    13,
    Paint()..color = const Color(0xffc19d75),
  );
  canvas.restore();
  void text(String value, double y, double size, {String font = 'Onest'}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: font,
          fontSize: size,
          color: paper,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 404);
    painter.paint(canvas, Offset(54, y));
    painter.dispose();
  }

  text('MUT  /  DEMO COLLECTION', 54, 16);
  text(title, 116, 52, font: 'Literata');
  text(author, 654, 23);
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 768);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return Uint8List.fromList(data.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

const _paragraphs = [
  'At noon, light fell across the shelves in even bands. The room held the quiet of a place that had been waiting for someone to return.',
  'Mira opened the notebook by the window. Between its pages she found a map with no names, only small circles drawn around the places where she had once stopped to listen.',
  'Everything important moves slowly. A tide, a season, a thought that needs another day before it can become a sentence.',
  'Outside, the last rain was lifting from the pavement. She could hear a train beyond the garden, and somewhere nearer, the gentle turn of a page.',
];

Uint8List _book(
  String title,
  String author,
  Uint8List? artwork,
) => Uint8List.fromList(
  utf8.encode(
    '<FictionBook xmlns:l="http://www.w3.org/1999/xlink">'
    '<description><title-info><book-title>$title</book-title>'
    '<author><first-name>$author</first-name></author>'
    '${artwork == null ? '' : '<coverpage><image l:href="#cover"/></coverpage>'}'
    '</title-info></description><body><section><title>'
    '<p>The Silence That Has an Orbit</p></title>'
    '${List.generate(6, (_) => _paragraphs.map((p) => '<p>$p</p>').join()).join()}'
    '</section></body>'
    '${artwork == null ? '' : '<binary id="cover" content-type="image/png">${base64Encode(artwork)}</binary>'}'
    '</FictionBook>',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture the mobile documentation gallery', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final font in ['Onest', 'Literata']) {
        await (FontLoader(
          font,
        )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
      }
    });
    final temp = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('mut-gallery-'),
    ))!;
    final repository = (await tester.runAsync(() async {
      final root = Directory('${temp.path}/vault');
      final seed = VaultStore(root, kdfMemory: 64, kdfTime: 1, kdfLanes: 1);
      await seed.create('demo password');
      final titles = [
        'Orbits of Silence',
        'Map of Winds',
        'After the Rain',
        'Garden of Observations',
      ];
      final authors = ['Mira Holm', 'Anton Ray', 'Leya Snow', 'I. Polevoy'];
      for (var i = 0; i < titles.length; i++) {
        // Include a book with no embedded cover to show the text fallback.
        final artwork = i == 1
            ? null
            : await _artwork(titles[i], authors[i], i == 0 ? 0 : i - 1);
        final id = await seed.importFile(
          '${titles[i]}.fb2',
          _book(titles[i], authors[i], artwork),
        );
        await seed.update(id, {
          'title': titles[i],
          'author': authors[i],
          'metadata_read': true,
          'shelves': [i.isEven ? 'Bedtime' : 'Travel'],
          'position': {
            'locator': i == 0 ? 'text-v2:0:0' : '',
            'progress': i == 0 ? .42 : 0,
          },
        });
      }
      seed.lock();
      return IsolateLibraryRepository.start(root.path);
    }))!;
    final controller = LibraryController(repository);
    final boundary = GlobalKey();
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(controller.busy, false);
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(String name) async {
      await settle();
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final file = File('docs/screenshots/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        } finally {
          image.dispose();
        }
      });
    }

    try {
      await tester.runAsync(() async {
        await controller.initialize();
        await controller.unlock('demo password');
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MutApp(controller: controller, documents: _DemoDocuments()),
        ),
      );
      await capture('library');
      expect(
        find.descendant(
          of: find.byType(BookCover),
          matching: find.byType(RawImage),
        ),
        findsWidgets,
      );
      await tester.tap(find.text('Orbits of Silence').first);
      await capture('book-details');
      await tester.ensureVisible(find.text('Continue reading'));
      await tester.tap(find.text('Continue reading'));
      await capture('reader');
      await tester.tap(find.text('Aa'));
      await capture('appearance');
      await tester.runAsync(controller.lock);
      await capture('locked');
      expect(find.byType(BookCover), findsNothing);
      expect(find.text('Orbits of Silence'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(() async {
        await repository.dispose();
        await temp.delete(recursive: true);
      });
    }
  });
}
