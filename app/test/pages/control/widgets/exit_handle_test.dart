import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/exit_handle.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

void main() {
  test('initial remote control handle follows the design right edge', () {
    final bounds = ExitHandle.initialBoundsFor(
      const Size(402, 874),
      const MediaQueryData(
        padding: EdgeInsets.only(right: 12),
        systemGestureInsets: EdgeInsets.only(right: 12),
      ),
    );

    expect(bounds.left, 338);
    expect(bounds.right, 390);
    expect(bounds.top, closeTo(384.56, 0.01));
  });

  testWidgets('dragging inward docks without opening, tapping opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: ExitHandle(deviceLabel: '测试设备', onExit: () {}),
        ),
      ),
    );
    final handle = find.byKey(const ValueKey('remote-tool-handle'));
    final panel = find.byKey(const ValueKey('remote-tool-panel'));
    await tester.drag(handle, const Offset(-90, 36));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.getRect(handle).right, 800);

    await tester.drag(handle, const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.getRect(handle).left, 0);

    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
  });

  testWidgets(
    'remote tool panel uses glass with a grid and respects reduced transparency',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: GlassPreferences(
            reduceTransparency: true,
            child: Scaffold(
              body: ExitHandle(deviceLabel: '测试设备', onExit: () {}),
            ),
          ),
        ),
      );

      final control = find.byKey(const ValueKey('remote-tool-handle'));
      final surface = find.descendant(
        of: control,
        matching: find.byType(Glass),
      );
      expect(
        tester.getSize(surface),
        const Size(
          DesignTokens.componentRemoteExitPeekWidth,
          DesignTokens.componentRemoteExitHitHeight,
        ),
      );
      await tester.tap(control);
      await tester.pump();

      expect(find.byKey(const ValueKey('remote-tool-panel')), findsOneWidget);
      expect(control, findsNothing);
      final panel = find.byKey(const ValueKey('remote-tool-panel'));
      expect(tester.widget<Glass>(panel).variant, GlassVariant.regular);
      expect(tester.getSize(panel).width, 272);
      final sound = tester.getCenter(find.text('设备声音'));
      final sleep = tester.getCenter(find.text('熄屏'));
      final keyboard = tester.getCenter(find.text('键盘'));
      expect(sound.dy, sleep.dy);
      expect(sleep.dx, keyboard.dx);
      expect(keyboard.dy, greaterThan(sleep.dy));

      await tester.tap(find.byTooltip('收起画面工具'));
      await tester.pump();
      expect(panel, findsNothing);
      expect(control, findsOneWidget);
    },
  );
}
