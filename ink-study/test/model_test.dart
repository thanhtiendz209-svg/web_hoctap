import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/model.dart';

void main() {
  const ink = Color(0xff146273);

  test('notebook round-trips editable PDF, images, geometry, and ink', () {
    const note = InkNote(
      id: 'chapter-1',
      title: 'Hình học không gian',
      notebook: 'Toán',
      zoom: 1.5,
      scroll: 720.5,
      document: InkDocument(
        paper: PaperKind.dots,
        paperColor: Color(0xfff7edd5),
        pdfAsset: 'chapter.pdf',
        pdfPages: [PdfPageInfo(width: 400, height: 600)],
        pdfRegions: [
          PdfRegion(
            page: 0,
            source: Rect.fromLTRB(10, 20, 42, 60),
            bounds: Rect.fromLTRB(25, 40, 220, 280),
          ),
        ],
        shapes: [
          InkShape(
            kind: ShapeKind.box,
            start: Offset(10, 50),
            end: Offset(26, 124),
            color: ink,
            width: 3,
            dashedEdges: {1, 6},
          ),
        ],
        images: [
          InkImage(
            asset: 'image.png',
            bounds: Rect.fromLTRB(22, 77, 184, 232),
            rotation: 0.15,
          ),
        ],
        strokes: [
          InkStroke(
            points: [InkPoint(Offset(22, 44), 0.4), InkPoint(Offset(124, 181))],
            color: ink,
            width: 7,
            kind: PenKind.pencil,
            dashed: true,
            phase: 15,
          ),
        ],
      ),
    );
    final encoded = jsonEncode(note.toJson());
    final decoded = InkNote.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );

    expect(decoded.toJson(), equals(note.toJson()));
    expect(decoded.document.copyWith().pdfAsset, 'chapter.pdf');
    expect(decoded.document.copyWith(pdfAsset: null).pdfAsset, isNull);
  });

  test('a sweep between sparse pointer events splits a stroke', () {
    const stroke = InkStroke(
      points: [InkPoint(Offset.zero, 0.2), InkPoint(Offset(100, 0), 0.8)],
      color: ink,
      width: 2,
      kind: PenKind.highlighter,
      dashed: true,
      phase: 3,
    );

    final result = eraseStrokes(
      [stroke],
      const Offset(50, -30),
      const Offset(50, 30),
      6,
    );

    expect(result, hasLength(2));
    expect(result[0].points.last.position.dx, closeTo(43, 1e-8));
    expect(result[1].points.first.position.dx, closeTo(57, 1e-8));
    expect(result[0].points.last.pressure, closeTo(0.458, 1e-8));
    expect(result[1].points.first.pressure, closeTo(0.542, 1e-8));
    expect(result[1].phase, closeTo(60, 1e-8));
    expect(result.every((piece) => piece.dashed && piece.color == ink), isTrue);
  });

  test('a sweep parallel to ink does not remove beyond its round ends', () {
    const stroke = InkStroke(
      points: [InkPoint(Offset.zero), InkPoint(Offset(120, 0))],
      color: ink,
      width: 4,
    );

    final result = eraseStrokes(
      [stroke],
      const Offset(30, 6),
      const Offset(90, 6),
      8,
    );

    expect(result, hasLength(2));
    expect(result[0].points.last.position.dx, closeTo(22, 1e-8));
    expect(result[1].points.first.position.dx, closeTo(98, 1e-8));
  });

  test('isolated tangent contact keeps the same unmodified stroke list', () {
    const stroke = InkStroke(
      points: [InkPoint(Offset.zero), InkPoint(Offset(100, 0))],
      color: ink,
      width: 2,
    );
    final strokes = [stroke];
    const touch = Offset(50, 7);

    expect(identical(eraseStrokes(strokes, touch, touch, 6), strokes), isTrue);
  });

  test('point erase removes a dot', () {
    const stroke = InkStroke(
      points: [InkPoint(Offset(12, 15))],
      color: ink,
      width: 4,
    );

    expect(
      eraseStrokes([stroke], const Offset(12, 0), const Offset(12, 40), 2),
      isEmpty,
    );
  });

  test('ink capture rounds a turn without changing settled samples', () {
    const first = InkPoint(Offset.zero, 0.3);
    const corner = InkPoint(Offset(20, 0), 0.6);
    const next = InkPoint(Offset(20, 20), 0.8);
    const last = InkPoint(Offset(40, 20), 1);
    final input = InkStrokeInput(first)..add(corner);
    expect(input.points, [first, corner]);

    input.add(next);
    expect(input.points.first, first);
    expect(input.points.last, next);
    expect(input.points, isNot(contains(corner)));
    expect(input.points.sublist(2, input.points.length - 2), isNotEmpty);
    expect(
      collectPressures(input.points),
      orderedEquals(collectPressures(input.points)..sort()),
    );
    final settled = input.points.sublist(0, input.points.length - 1);

    input.add(last);
    expect(input.points.take(settled.length), settled);
    expect(input.points.last, last);

    final stroke = InkStroke(points: input.points, color: ink, width: 2);
    final erase = eraseStrokes(
      [stroke],
      const Offset(20, 0),
      const Offset(20, 0),
      0.4,
    );
    expect(
      erase.single,
      same(stroke),
      reason: 'The rounded path leaves the sharp corner empty.',
    );
  });

  test('a shape is only erased by a sweep across a painted edge', () {
    const rectangle = InkShape(
      kind: ShapeKind.rectangle,
      start: Offset.zero,
      end: Offset(100, 70),
      color: ink,
      width: 2,
    );
    final shapes = [rectangle];
    expect(
      eraseShapes(shapes, const Offset(50, 20), const Offset(60, 20), 3),
      same(shapes),
    );
    expect(
      eraseShapes(shapes, const Offset(50, -20), const Offset(50, 20), 3),
      isEmpty,
    );

    final dashed = [rectangle.copyWith(width: 1, dashed: true)];
    const gap = Offset(6.5, 0);
    const painted = Offset(3, 0);
    expect(eraseShapes(dashed, gap, gap, 0.2), same(dashed));
    expect(eraseShapes(dashed, painted, painted, 0.2), isEmpty);

    const stroke = InkStroke(
      points: [InkPoint(Offset.zero), InkPoint(Offset(100, 0))],
      color: ink,
      width: 1,
      dashed: true,
    );
    final strokes = [stroke];
    expect(eraseStrokes(strokes, gap, gap, 0.2), same(strokes));
    expect(eraseStrokes(strokes, painted, painted, 0.2), hasLength(2));
  });

  test('hidden shape edges can be individually toggled', () {
    const box = InkShape(
      kind: ShapeKind.box,
      start: Offset.zero,
      end: Offset(100, 100),
      color: ink,
      width: 3,
    );

    expect(shapeEdges(box), hasLength(12));
    expect(shapeEdges(box)[6].hidden, isTrue);
    expect(isShapeEdgeDashed(box, 6), isTrue);
    expect(isShapeEdgeDashed(box, 0), isFalse);

    final edited = box.copyWith(dashedEdges: {0, 6});
    expect(isShapeEdgeDashed(edited, 6), isFalse);
    expect(isShapeEdgeDashed(edited, 0), isTrue);
  });
}

List<double> collectPressures(List<InkPoint> points) => [
  for (final point in points) point.pressure,
];
