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
}
