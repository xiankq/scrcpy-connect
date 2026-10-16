import 'package:scrcpy_connect/pages/remote/widgets/exit_handle.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'phone-width native drag path leaves a 44px hittable collapsed control that expands and exits',
    (tester) async {
      tester.view.physicalSize = const Size(393, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();
      var exits = 0;
      var remoteTouches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerDown: (_) => remoteTouches++,
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox.expand(),
                  ),
                ),
                ExitHandle(deviceLabel: '手机', onExit: () => exits++),
              ],
            ),
          ),
        ),
      );
      final handle = find.descendant(
        of: find.byType(ExitHandle),
        matching: find.byType(GestureDetector),
      );
      await tester.drag(handle, const Offset(393 * .72, 100));
      await tester.pump(const Duration(milliseconds: 1200));
      final collapsed = find.bySemanticsLabel(RegExp('展开退出按钮，'));
      expect(collapsed, findsOneWidget);
      expect(tester.getSize(handle).width, 44);
      expect(tester.getRect(collapsed), tester.getRect(handle));
      await tester.tap(collapsed);
      await tester.pump(const Duration(milliseconds: 300));
      final expanded = find.bySemanticsLabel(RegExp('退出控制，返回'));
      expect(expanded, findsOneWidget);
      expect(exits, 0);
      expect(remoteTouches, 0);
      await tester.tap(expanded);
      await tester.pump();
      expect(exits, 1);
      semantics.dispose();
    },
  );
  testWidgets(
    'expanding interrupts an unfinished snap and preserves the expanded position',
    (tester) async {
      tester.view.physicalSize = const Size(393, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: ExitHandle(deviceLabel: '手机', onExit: () {}),
          ),
        ),
      );
      final handle = find.descendant(
        of: find.byType(ExitHandle),
        matching: find.byType(GestureDetector),
      );
      await tester.drag(handle, const Offset(393 * .72, 100));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(handle).left, closeTo(393 - 64, .1));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getRect(handle).left, closeTo(393 - 64, .1));
    },
  );
}
