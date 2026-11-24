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

  for (final (platform, left, right) in [
    ('macOS', 78.0, 0.0),
    ('Windows', 0.0, 138.0),
    ('Linux with left-side buttons', 96.0, 0.0),
  ]) {
    testWidgets('$platform puts page actions below the native controls', (
      tester,
    ) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(DesktopWindow.channel, (call) async {
        calls.add(call.method);
        return call.method == 'layout'
            ? {'left': left, 'right': right, 'top': 32.0}
            : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(DesktopWindow.channel, null),
      );
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
      final first = find.byIcon(LucideIcons.chevronLeft);
      final last = find.byIcon(LucideIcons.info);
      final immersive = tester.getRect(first);
      expect(immersive.top, greaterThanOrEqualTo(32));
      expect(tester.getCenter(last).dy, immersive.center.dy);

      await tester.tap(first);
      expect(back, 1);
      await tester.drag(find.text('USB 连接'), const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, ['layout', 'move']);

      await messenger.handlePlatformMessage(
        DesktopWindow.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('layoutChanged', {'left': 0, 'right': 0, 'top': 0}),
        ),
        (_) {},
      );
      await tester.pump();
      expect(tester.getRect(first).top, immersive.top - 32);
      expect(tester.getRect(first).left, immersive.left);
    });
  }

  testWidgets('desktop stage paints beneath the native controls', (
    tester,
  ) async {
    const content = ValueKey('stage-content');
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWindowInsets(
          left: 78,
          right: 0,
          top: 32,
          child: DesktopStage(
            child: ColoredBox(key: content, color: Colors.black),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(content)),
      const Rect.fromLTWH(0, 0, 800, 600),
    );
  });
}
