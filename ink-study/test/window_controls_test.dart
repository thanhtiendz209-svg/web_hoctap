import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_study/window_controls.dart';

void main() {
  testWidgets(
    'Windows events update controls and close routes through the OS',
    (tester) async {
      const channel = MethodChannel('window_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final actions = <String>[];
      var maximized = false;
      var fullscreen = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'isMaximized':
            return maximized;
          case 'isFullScreen':
            return fullscreen;
          case 'setFullScreen':
            actions.add('${call.method}:${call.arguments['isFullScreen']}');
            return null;
          default:
            actions.add(call.method);
            return null;
        }
      });

      Future<void> sendNativeEvent(String event) async {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('onEvent', {'eventName': event}),
          ),
          null,
        );
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: InkWindowControls())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Phóng to cửa sổ'));
      await tester.pumpAndSettle();

      maximized = true;
      await sendNativeEvent('maximize');
      await tester.tap(find.byTooltip('Khôi phục cửa sổ'));
      await tester.pumpAndSettle();

      fullscreen = true;
      await sendNativeEvent('enter-full-screen');
      await tester.tap(find.byTooltip('Thoát toàn màn hình'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Thu nhỏ cửa sổ'));
      await tester.tap(find.byTooltip('Đóng cửa sổ'));
      await tester.pumpAndSettle();

      expect(actions, [
        'maximize',
        'unmaximize',
        'setFullScreen:false',
        'minimize',
        'close',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
}
