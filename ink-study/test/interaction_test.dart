import 'dart:io';
import 'dart:ui';
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/assets.dart';
import 'package:ink_study/canvas.dart';
import 'package:ink_study/model.dart';

void main() {
  testWidgets('PDF writing space shifts content and is kept in the export', (
    tester,
  ) async {
    const ink = Color(0xff343975);
    final recorder = PictureRecorder();
    Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 100, 50),
        Paint()..color = Colors.blue,
      )
      ..drawRect(
        const Rect.fromLTWH(0, 50, 100, 50),
        Paint()..color = Colors.red,
      );
    final picture = recorder.endRecording();
    final page = picture.toImageSync(100, 100);
    picture.dispose();
    addTearDown(page.dispose);
    const original = InkDocument(
      pdfAsset: 'page.pdf',
      pdfPages: [
        PdfPageInfo(width: 900, height: 900),
        PdfPageInfo(width: 900, height: 900),
      ],
      paper: PaperKind.blank,
      paperColor: Color(0xffffffff),
      strokes: [
        InkStroke(points: [InkPoint(Offset(220, 260))], color: ink, width: 3),
        InkStroke(points: [InkPoint(Offset(220, 480))], color: ink, width: 3),
      ],
    );
    var document = original;
    final canvas = GlobalKey<InkCanvasState>();
    final store = _PdfRasterStore(page);
    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InkCanvas(
            key: canvas,
            document: document,
            store: store,
            onChange: (next) => document = next,
            tool: Tool.pdfSpace,
            color: ink,
            width: 3,
            penKind: PenKind.ballpoint,
            dashed: false,
            shapeKind: ShapeKind.line,
            zoom: 0.5,
            scroll: 0,
            onViewportChanged: (_, _) {},
          ),
        ),
      ),
    );
    await mount();
    final before = canvas.currentState!.contentBounds;
    final gesture = await tester.startGesture(
      const Offset(400, 225),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 60));
    await gesture.up();
    expect(document.pdfGaps.single.sourceY, 450);
    expect(document.pdfGaps.single.height, 120);
    expect(document.strokes.first, same(original.strokes.first));
    expect(document.strokes.last.points.single.position.dy, 600);
    await mount();
    expect(canvas.currentState!.contentBounds.bottom, before.bottom + 120);

    final colors = await tester.runAsync(() async {
      final data = await canvas.currentState!.render(
        const Rect.fromLTWH(0, 0, 900, 1100),
        0.2,
      );
      final codec = await instantiateImageCodec(data);
      final frame = (await codec.getNextFrame()).image;
      try {
        final pixels = (await frame.toByteData())!;
        Color pixel(int y) {
          final offset = (y * frame.width + 70) * 4;
          return Color.fromARGB(
            255,
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2),
          );
        }

        return [pixel(82), pixel(100), pixel(122), pixel(209)];
      } finally {
        frame.dispose();
        codec.dispose();
      }
    });
    expect(colors, const [
      Color(0xff2196f3),
      Color(0xffffffff),
      Color(0xfff44336),
      Color(0xff2196f3),
    ]);

    final extend = await tester.startGesture(
      const Offset(400, 245),
      kind: PointerDeviceKind.mouse,
    );
    await extend.moveBy(const Offset(0, 20));
    await extend.up();
    await mount();
    expect(document.pdfGaps.last.sourceY, 450);
    expect(canvas.currentState!.contentBounds.bottom, before.bottom + 160);
    expect(document.strokes.last.points.single.position.dy, 640);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mouse draws and partially erases through the canvas', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('ink-study-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = await tester.runAsync(
      () => InkStore.open(directory: directory),
    );
    var document = const InkDocument(
      shapes: [
        InkShape(
          kind: ShapeKind.rectangle,
          start: Offset(300, 170),
          end: Offset(400, 220),
          color: Color(0xff08796e),
          width: 3,
        ),
      ],
    );
    var tool = Tool.pen;
    final canvas = GlobalKey<InkCanvasState>();
    var edits = 0;

    Future<void> mount() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InkCanvas(
            key: canvas,
            document: document,
            store: store!,
            onChange: (next) {
              document = next;
              edits++;
            },
            tool: tool,
            color: const Color(0xff08796e),
            width: 3,
            eraserWidth: 24,
            penKind: PenKind.ballpoint,
            dashed: false,
            shapeKind: ShapeKind.line,
            zoom: 1,
            scroll: 0,
            onViewportChanged: (_, _) {},
          ),
        ),
      ),
    );

    await mount();
    final pen = await tester.startGesture(
      const Offset(140, 200),
      kind: PointerDeviceKind.mouse,
    );
    await pen.moveTo(const Offset(530, 200));
    await pen.up();
    await tester.pump();
    expect(document.strokes, hasLength(1));
    expect(edits, 1);

    tool = Tool.eraser;
    await mount();
    final eraser = await tester.startGesture(
      const Offset(300, 150),
      kind: PointerDeviceKind.mouse,
    );
    await eraser.moveTo(const Offset(300, 250));
    await eraser.up();
    await tester.pump();
    expect(document.strokes, hasLength(2));
    expect(document.shapes, isEmpty);
    expect(edits, 2);
  });

  testWidgets(
    'rectangle selection moves and deletes ink and geometry together',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'ink-study-select-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = await tester.runAsync(
        () => InkStore.open(directory: directory),
      );
      const color = Color(0xff08796e);
      const first = InkStroke(
        points: [InkPoint(Offset(220, 180)), InkPoint(Offset(310, 185))],
        color: color,
        width: 3,
      );
      const second = InkStroke(
        points: [InkPoint(Offset(230, 220)), InkPoint(Offset(300, 232))],
        color: color,
        width: 4,
        dashed: true,
      );
      const outside = InkStroke(
        points: [InkPoint(Offset(500, 360)), InkPoint(Offset(580, 400))],
        color: color,
        width: 3,
      );
      const shape = InkShape(
        kind: ShapeKind.rectangle,
        start: Offset(335, 176),
        end: Offset(375, 234),
        color: color,
        width: 3,
      );
      const original = InkDocument(
        strokes: [first, second, outside],
        shapes: [shape],
      );
      var document = original;
      var edits = 0;
      final history = <InkDocument>[];
      late VoidCallback undo;
      late VoidCallback usePen;
      var tool = Tool.select;
      var quickSelections = 0;
      final canvas = GlobalKey<InkCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                undo = () => setState(() => document = history.removeLast());
                usePen = () => setState(() => tool = Tool.pen);
                return InkCanvas(
                  key: canvas,
                  document: document,
                  store: store!,
                  onChange: (next) => setState(() {
                    history.add(document);
                    document = next;
                    edits++;
                  }),
                  tool: tool,
                  onQuickSelect: () => setState(() {
                    tool = Tool.select;
                    quickSelections++;
                  }),
                  color: color,
                  width: 3,
                  penKind: PenKind.ballpoint,
                  dashed: false,
                  shapeKind: ShapeKind.rectangle,
                  zoom: 1,
                  scroll: 0,
                  onViewportChanged: (_, _) {},
                );
              },
            ),
          ),
        ),
      );

      Offset screen(Offset point) {
        const anchor = Offset(400, 200);
        final anchorInDocument = canvas.currentState!.documentPoint(anchor);
        return tester.getTopLeft(find.byKey(canvas)) +
            anchor +
            point -
            anchorInDocument;
      }

      Future<TestGesture> drag(Offset from, Offset to) async {
        final gesture = await tester.startGesture(
          screen(from),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveTo(screen(to));
        return gesture;
      }

      Future<TestGesture> select([Offset offset = Offset.zero]) => drag(
        const Offset(190, 145) + offset,
        const Offset(400, 260) + offset,
      );

      final canceledSelection = await select();
      await canceledSelection.cancel();
      await tester.pump();
      expect(canvas.currentState!.deleteSelection(), isFalse);
      expect(document, same(original));
      expect(edits, 0);

      final selection = await select();
      await selection.up();
      await tester.pump();
      expect(edits, 0);

      const from = Offset(262, 182);
      const delta = Offset(80, 72);
      final canceledMove = await drag(from, from + delta);
      await canceledMove.cancel();
      await tester.pump();
      expect(document, same(original));
      expect(edits, 0);

      final newSelection = await select();
      await newSelection.up();
      await tester.pump();
      final move = await drag(from, from + delta);
      await move.up();
      await tester.pump();
      expect(edits, 1);
      expect(document.strokes, hasLength(3));
      expect(
        document.strokes[0].points.map((point) => point.position),
        first.points.map((point) => point.position + delta),
      );
      expect(
        document.strokes[1].points.map((point) => point.position),
        second.points.map((point) => point.position + delta),
      );
      expect(document.strokes[1].dashed, isTrue);
      expect(document.strokes[2], same(outside));
      expect(document.shapes.single.start, shape.start + delta);
      expect(document.shapes.single.end, shape.end + delta);
      final moved = document;

      await tester.tap(find.text('Xóa'));
      await tester.pump();
      expect(edits, 2);
      expect(document.strokes.single, same(outside));
      expect(document.shapes, isEmpty);

      undo();
      await tester.pump();
      expect(document, same(moved));
      final beforeUndo = await select(delta);
      await beforeUndo.up();
      await tester.pump();
      undo();
      await tester.pump();
      expect(document, same(original));
      expect(canvas.currentState!.deleteSelection(), isFalse);
      expect(edits, 2);

      usePen();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final quickSelection = await select();
      await quickSelection.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(quickSelections, 1);
      expect(edits, 2);
      await tester.tap(find.text('Di chuyển'));
      await tester.pump();
      expect(find.text('Bấm vị trí mới'), findsOneWidget);
      await tester.tapAt(screen(const Offset(650, 450)));
      await tester.pump();
      expect(edits, 3);
      expect(document.shapes.single.start.dx, greaterThan(550));
      await tester.tap(find.text('Xóa'));
      await tester.pump();
      expect(document.strokes.single, same(outside));
      expect(document.shapes, isEmpty);
    },
  );
}

class _PdfRasterStore implements InkStore {
  _PdfRasterStore(this.page);

  final ui.Image page;

  @override
  Future<ui.Image> pdfPage(String asset, int index, int pixelWidth) async =>
      page.clone();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
