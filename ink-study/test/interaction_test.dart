import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/assets.dart';
import 'package:ink_study/canvas.dart';
import 'package:ink_study/model.dart';

void main() {
  testWidgets('mouse draws and partially erases through the canvas', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('ink-study-ui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = await tester.runAsync(
      () => InkStore.open(directory: directory),
    );
    var document = const InkDocument();
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
            width: tool == Tool.eraser ? 18 : 3,
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
      final canvas = GlobalKey<InkCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                undo = () => setState(() => document = history.removeLast());
                return InkCanvas(
                  key: canvas,
                  document: document,
                  store: store!,
                  onChange: (next) => setState(() {
                    history.add(document);
                    document = next;
                    edits++;
                  }),
                  tool: Tool.select,
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

      expect(canvas.currentState!.deleteSelection(), isTrue);
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
    },
  );
}
