import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/assets.dart';
import 'package:ink_study/model.dart';

void main() {
  test(
    'editable backups copy ink, shapes and attachments into a new entry',
    () async {
      final root = await Directory.systemTemp.createTemp('ink-study-backup-');
      addTearDown(() => root.delete(recursive: true));
      final original = await InkStore.open(
        directory: Directory('${root.path}/original'),
      );
      final restored = await InkStore.open(
        directory: Directory('${root.path}/restored'),
      );
      const note = InkNote(
        id: 'original',
        title: 'Bài tập',
        notebook: 'Toán',
        scroll: 300,
        zoom: 1.6,
        document: InkDocument(
          paper: PaperKind.ruled,
          pdfAsset: 'page.pdf',
          pdfPages: [PdfPageInfo(width: 600, height: 800)],
          pdfGaps: [PdfWritingGap(page: 0, sourceY: 70, height: 180)],
          pdfRegions: [
            PdfRegion(
              page: 0,
              source: Rect.fromLTWH(10, 20, 50, 60),
              bounds: Rect.fromLTWH(100, 200, 150, 160),
            ),
          ],
          images: [
            InkImage(
              asset: 'figure.png',
              bounds: Rect.fromLTWH(50, 60, 90, 160),
            ),
          ],
          shapes: [
            InkShape(
              kind: ShapeKind.circle,
              start: Offset(210, 120),
              end: Offset(260, 170),
              width: 3,
              color: Color(0xff253750),
            ),
          ],
          strokes: [
            InkStroke(
              kind: PenKind.fountain,
              points: [InkPoint(Offset(100, 120), 0.7)],
              width: 6,
              color: Color(0xff3474cf),
            ),
          ],
        ),
      );
      final imageBytes = [137, 80, 78, 71, 13, 10, 26, 10];
      final pdfBytes = '%PDF-1.7\n%%EOF'.codeUnits;
      await File(
        '${root.path}/original/assets/figure.png',
      ).writeAsBytes(imageBytes);
      await File(
        '${root.path}/original/assets/page.pdf',
      ).writeAsBytes(pdfBytes);

      final backup = '${root.path}/lesson.inkstudy';
      expect(await original.exportNote(note, path: backup), isTrue);
      final imported = (await restored.importNote(path: backup))!;
      expect(imported.id, isNot(note.id));
      expect(imported.title, note.title);
      expect(imported.notebook, note.notebook);
      expect(imported.zoom, note.zoom);
      expect(imported.scroll, note.scroll);
      expect(imported.document.paper, note.document.paper);
      expect(
        imported.document.shapes.single.toJson(),
        note.document.shapes.single.toJson(),
      );
      expect(
        imported.document.strokes.single.toJson(),
        note.document.strokes.single.toJson(),
      );
      expect(
        imported.document.pdfRegions.single.toJson(),
        note.document.pdfRegions.single.toJson(),
      );
      expect(
        imported.document.pdfGaps.single.toJson(),
        note.document.pdfGaps.single.toJson(),
      );
      final image = imported.document.images.single;
      expect(image.asset, isNot('figure.png'));
      expect(image.bounds, note.document.images.single.bounds);
      expect(
        await File('${root.path}/restored/assets/${image.asset}').readAsBytes(),
        imageBytes,
      );
      expect(
        await File(
          '${root.path}/restored/assets/${imported.document.pdfAsset}',
        ).readAsBytes(),
        pdfBytes,
      );

      final another = (await restored.importNote(path: backup))!;
      expect(another.id, isNot(imported.id));
      expect(another.document.pdfAsset, isNot(imported.document.pdfAsset));
      await restored.save([imported, another]);
      expect(await restored.load(), hasLength(2));

      // A missing source resource must leave the previously exported file usable.
      await File('${root.path}/original/assets/page.pdf').delete();
      await expectLater(
        original.exportNote(note, path: backup),
        throwsFormatException,
      );
      expect(await restored.importNote(path: backup), isNotNull);
    },
  );

  test('pen slots preserve independent settings and selected slot', () async {
    final root = await Directory.systemTemp.createTemp('ink-study-pens-');
    addTearDown(() => root.delete(recursive: true));
    final store = await InkStore.open(directory: root);
    expect(await store.loadPens(), isNull);
    const first = PenPreset(color: Color(0xff253750));
    const second = PenPreset(color: Color(0xffd54260), width: 8, dashed: true);
    await store.savePens([first, second], 1);
    final reopened = await InkStore.open(directory: root);
    final result = (await reopened.loadPens())!;
    expect(result.active, 1);
    expect(result.pens.map((pen) => pen.toJson()), [
      first.toJson(),
      second.toJson(),
    ]);
  });

  test(
    'saves notes in order and recovers the previous complete snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ink-study-test-',
      );
      addTearDown(() => directory.delete(recursive: true));

      final store = await InkStore.open(directory: directory);
      expect(await store.load(), isEmpty);
      final first = store.save(<InkNote>[
        InkNote(id: 'study-1', title: 'Bài đầu tiên', scroll: 210, zoom: 1.25),
      ]);
      final second = store.save(<InkNote>[
        InkNote(id: 'study-1', title: 'Bài tiếp theo', scroll: 450, zoom: 1.5),
      ]);
      await Future.wait(<Future<void>>[first, second]);

      final reopened = await InkStore.open(directory: directory);
      final latest = (await reopened.load()).single;
      expect(latest.title, 'Bài tiếp theo');
      expect(latest.scroll, 450);
      expect(latest.zoom, 1.5);

      final latestFile = File(
        '${directory.path}${Platform.pathSeparator}notes-0.json',
      );
      await latestFile.writeAsString('{"version":1,"revision":2,');
      final recovered = (await reopened.load()).single;
      expect(recovered.title, 'Bài đầu tiên');
      expect(recovered.scroll, 210);
      expect(recovered.zoom, 1.25);
    },
  );

  test('PDF slices cover the same region with shared page boundaries', () {
    const region = Rect.fromLTRB(32, 60, 832, 3500);
    final portrait = InkStore.pdfSlices(region, landscape: false);
    final landscape = InkStore.pdfSlices(region, landscape: true);

    expect(portrait.length, greaterThan(1));
    expect(landscape.length, greaterThan(portrait.length));

    for (final slices in <List<Rect>>[portrait, landscape]) {
      expect(slices.first.top, region.top);
      expect(slices.last.bottom, region.bottom);
      for (var index = 0; index < slices.length; index++) {
        final slice = slices[index];
        expect(slice.left, region.left);
        expect(slice.right, region.right);
        expect(slice.height, isPositive);
        if (index > 0) {
          expect(slice.top, closeTo(slices[index - 1].bottom, 1e-7));
        }
      }
    }
  });
}
