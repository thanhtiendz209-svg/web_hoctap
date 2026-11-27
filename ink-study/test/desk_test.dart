import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/assets.dart';
import 'package:ink_study/canvas.dart';
import 'package:ink_study/main.dart';
import 'package:ink_study/model.dart';

void main() {
  testWidgets(
    'editing tools remain usable in full screen and at laptop width',
    (tester) async {
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      const windowManager = MethodChannel('window_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final directory = Directory.systemTemp.createTempSync('ink-study-desk-');
      addTearDown(() {
        messenger.setMockMethodCallHandler(pathProvider, null);
        messenger.setMockMethodCallHandler(windowManager, null);
        directory.deleteSync(recursive: true);
      });

      messenger.setMockMethodCallHandler(pathProvider, (call) async {
        expect(call.method, 'getApplicationSupportDirectory');
        return directory.path;
      });
      messenger.setMockMethodCallHandler(windowManager, (call) async {
        return switch (call.method) {
          'isMaximized' || 'isFullScreen' => false,
          _ => null,
        };
      });

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1320, 780);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final canvasFinder = find.byType(InkCanvas);
      await tester.runAsync(() async {
        final library = await InkStore.open(
          directory: Directory(
            '${directory.path}${Platform.pathSeparator}Ink Study',
          ),
        );
        await library.save([
          const InkNote(id: 'desk-fixture', title: 'Bài ghi chú kiểm thử'),
        ]);
        await tester.pumpWidget(const InkStudyApp());
        final timeout = DateTime.now().add(const Duration(seconds: 5));
        while (canvasFinder.evaluate().isEmpty &&
            DateTime.now().isBefore(timeout)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();

      InkCanvas canvas() => tester.widget<InkCanvas>(canvasFinder);
      expect(find.text('Thư viện'), findsOneWidget);
      expect(canvas().penKind, PenKind.ballpoint);

      await tester.tap(find.byTooltip('Bút bi · màu và độ dày'));
      await tester.pumpAndSettle();
      expect(find.text('Màu tùy chỉnh'), findsOneWidget);
      await tester.tap(find.text('Đỏ'));
      await tester.pumpAndSettle();
      expect(canvas().color, const Color(0xffd54260));

      await tester.tap(find.text('Bút chì'));
      await tester.pumpAndSettle();
      expect(canvas().penKind, PenKind.pencil);
      expect(find.text('Màu tùy chỉnh'), findsNothing);

      await tester.tap(find.text('Chọn vùng'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.select);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(find.text('Thư viện'), findsNothing);
      expect(find.text('Chọn vùng'), findsOneWidget);
      expect(find.text('Bút chì'), findsOneWidget);
      expect(canvas().tool, Tool.select);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Thư viện'), findsOneWidget);
      expect(canvas().tool, Tool.select);

      tester.view.physicalSize = const Size(690, 470);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Bút bi'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.pen);
      expect(canvas().penKind, PenKind.ballpoint);
      expect(canvas().color, const Color(0xffd54260));

      await tester.pumpWidget(const SizedBox());
    },
  );
}
