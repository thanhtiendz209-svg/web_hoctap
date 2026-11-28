import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/assets.dart';
import 'package:ink_study/canvas.dart';
import 'package:ink_study/main.dart';
import 'package:ink_study/model.dart';
import 'package:ink_study/tool_shelf.dart';

void main() {
  testWidgets(
    'one Windows ribbon and footer remain usable in full screen and at laptop width',
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
        expect(find.byTooltip('Đóng cửa sổ'), findsOneWidget);
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
      expect(find.text('Ink Study'), findsNothing);
      expect(
        tester.getTopLeft(find.byTooltip('Xuất PDF')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(canvasFinder).dy),
      );
      expect(find.text('Xuất PDF'), findsNothing);
      expect(canvas().penKind, PenKind.ballpoint);

      await tester.tap(find.byTooltip('Chỉnh bút'));
      await tester.pumpAndSettle();
      expect(find.text('Màu tùy chỉnh'), findsOneWidget);
      await tester.tap(find.byTooltip('Đỏ'));
      await tester.pumpAndSettle();
      expect(canvas().color, const Color(0xffd54260));
      await tester.tap(find.text('Nét đứt'));
      await tester.pumpAndSettle();
      expect(canvas().dashed, isTrue);
      await tester.tap(find.byType(Slider));
      await tester.pumpAndSettle();
      expect(canvas().width, greaterThan(2.8));

      await tester.tap(
        find.descendant(
          of: find.byType(PenOptionsPanel),
          matching: find.text('Bút mực'),
        ),
      );
      await tester.pumpAndSettle();
      expect(canvas().penKind, PenKind.fountain);
      expect(canvas().width, 6.0);
      await tester.tap(find.text('Bút chì'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chỉnh bút'));
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
      expect(find.byTooltip('Tẩy một phần nét'), findsOneWidget);
      expect(
        find.byTooltip('Chọn vùng · Shift + kéo để chọn nhanh'),
        findsOneWidget,
      );
      expect(find.byTooltip('Ẩn thư viện'), findsOneWidget);
      await tester.tap(find.byTooltip('Chỉnh bút'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bút bi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chỉnh bút'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.pen);
      expect(canvas().penKind, PenKind.ballpoint);
      expect(canvas().color, const Color(0xffd54260));
      expect(canvas().dashed, isTrue);

      await tester.tap(find.byTooltip('Độ rộng gôm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lớn'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.eraser);
      expect(canvas().eraserWidth, 48.0);
      expect(find.text('48 px').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Độ rộng gôm'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hình học'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mũi tên'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.shape);
      final dragArea = tester.getRect(
        find.byKey(const ValueKey('window-drag-area')),
      );
      expect(dragArea.width, greaterThanOrEqualTo(28));
      expect(
        tester.getRect(find.byTooltip('Làm lại · Ctrl+Y')).right,
        lessThanOrEqualTo(dragArea.left),
      );
      await tester.tap(find.byTooltip('Kiểu nét hình'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Xanh lam'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.shape);
      expect(canvas().color, const Color(0xff3474cf));

      await tester.tap(find.byTooltip('Trình bày với laser'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.laser);
      expect(find.byTooltip('Đóng cửa sổ'), findsNothing);
      expect(find.byTooltip('Tẩy một phần nét'), findsNothing);
      await tester.tap(find.byTooltip('Cuộn'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.hand);
      await tester.tap(find.byTooltip('Thoát trình bày (Esc)'));
      await tester.pumpAndSettle();
      expect(canvas().tool, Tool.shape);
      expect(find.byTooltip('Đóng cửa sổ'), findsOneWidget);
      expect(find.byTooltip('Xuất PDF'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
}
