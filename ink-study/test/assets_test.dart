import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/assets.dart';
import 'package:ink_study/model.dart';

void main() {
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
