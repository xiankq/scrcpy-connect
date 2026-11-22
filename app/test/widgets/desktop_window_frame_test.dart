import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/desktop_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(DesktopWindow.channel, (call) async {
      calls.add(call);
      return call.method == 'state' ? 'normal' : null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(DesktopWindow.channel, null),
  );

  Future<void> stateChanged(DesktopWindowState state) =>
      messenger.handlePlatformMessage(
        DesktopWindow.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('stateChanged', state.name),
        ),
        (_) {},
      );

  Finder button(String command) =>
      find.byKey(ValueKey('desktop-window-$command'));

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform integrates controls with the page row', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      var back = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => DesktopWindowFrame(child: child!),
          home: PageFrame(
            title: 'USB 连接',
            onBack: () => back++,
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(LucideIcons.info)),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mac = platform == TargetPlatform.macOS;
      final expand = mac ? 'toggleFullscreen' : 'toggleMaximized';
      final minimize = tester.getRect(button('minimize'));
      final close = tester.getRect(button('close'));
      final title = tester.getRect(find.text('USB 连接'));
      expect(close.height, 32);
      expect(close.center.dy, 28);
      expect(title.center.dy, close.center.dy);
      if (mac) {
        expect(close.left, 12);
        expect(close.right, minimize.left);
        expect(title.left, greaterThan(tester.getRect(button(expand)).right));
      } else {
        expect(close.right, 788);
        expect(tester.getRect(button(expand)).right, close.left);
        expect(
          tester.getRect(find.byIcon(LucideIcons.info)).right,
          lessThan(minimize.left),
        );
      }

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      expect(back, 1);
      await tester.drag(find.text('USB 连接'), const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.map((call) => call.method), ['state', 'move']);
      await tester.tap(button(expand));
      expect(calls.last.method, expand);
      await stateChanged(
        mac ? DesktopWindowState.fullscreen : DesktopWindowState.maximized,
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip && widget.message == (mac ? '退出全屏' : '还原窗口'),
        ),
        findsOneWidget,
      );
      if (mac) {
        expect(tester.widget<IconButton>(button('minimize')).onPressed, isNull);
        await stateChanged(DesktopWindowState.normal);
        await tester.pump();
      }
      await tester.tap(button('minimize'));
      await tester.tap(button('close'));
      expect(calls.map((call) => call.method), [
        'state',
        'move',
        expand,
        'minimize',
        'close',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
