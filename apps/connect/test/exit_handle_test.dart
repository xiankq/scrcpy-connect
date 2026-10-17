import 'package:scrcpy_connect/pages/remote/widgets/exit_handle.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dragging the left handle inward keeps the exit button expanded',
    (tester) async {
      final harness = await _pumpHandle(tester);
      await tester.drag(harness.control, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('展开退出按钮，手机'), findsOneWidget);

      await tester.drag(harness.control, const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('退出控制，返回手机'), findsOneWidget);
      expect(tester.getRect(harness.control).left, greaterThan(44));
      expect(harness.exits, 0);
      expect(harness.remoteTouches, 0);
    },
  );

  testWidgets(
    'dragging the right handle inward keeps the exit button expanded',
    (tester) async {
      final harness = await _pumpHandle(tester);
      await tester.drag(harness.control, const Offset(280, 100));
      await tester.pumpAndSettle();
      expect(tester.getRect(harness.control).right, 393);

      await tester.drag(harness.control, const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('退出控制，返回手机'), findsOneWidget);
      expect(tester.getRect(harness.control).right, lessThan(349));
      expect(harness.exits, 0);
      expect(harness.remoteTouches, 0);
    },
  );

  testWidgets('release snaps to the nearest edge despite outward fling speed', (
    tester,
  ) async {
    final harness = await _pumpHandle(tester);
    await tester.fling(harness.control, const Offset(60, 0), 2000);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('展开退出按钮，手机'), findsOneWidget);
    expect(tester.getRect(harness.control).left, closeTo(0, .1));
    expect(harness.exits, 0);
    expect(harness.remoteTouches, 0);
  });

  testWidgets(
    'rotation keeps the handle outside safe and system gesture areas',
    (tester) async {
      final harness = await _pumpHandle(tester);
      await tester.drag(harness.control, const Offset(280, 800));
      await tester.pumpAndSettle();

      await _pumpHandle(
        tester,
        harness: harness,
        size: const Size(874, 393),
        padding: const EdgeInsets.fromLTRB(32, 20, 36, 24),
        systemGestureInsets: const EdgeInsets.fromLTRB(40, 0, 48, 30),
      );

      final collapsed = tester.getRect(harness.control);
      expect(collapsed.right, lessThanOrEqualTo(826));
      expect(collapsed.bottom, lessThanOrEqualTo(351));
      expect(collapsed.top, greaterThanOrEqualTo(32));
      await tester.tap(harness.control);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('退出控制，返回手机'), findsOneWidget);
      expect(tester.getRect(harness.control).right, lessThanOrEqualTo(826));
      expect(harness.exits, 0);
      expect(harness.remoteTouches, 0);
    },
  );

  testWidgets(
    'reduced motion snaps immediately and still allows inward expansion',
    (tester) async {
      final harness = await _pumpHandle(tester, disableAnimations: true);
      await tester.drag(harness.control, const Offset(80, 100));
      await tester.pump();
      expect(find.bySemanticsLabel('展开退出按钮，手机'), findsOneWidget);
      expect(tester.getRect(harness.control).left, 0);

      await tester.drag(harness.control, const Offset(100, 0));
      await tester.pump();
      final expanded = tester.getRect(harness.control);
      expect(find.bySemanticsLabel('退出控制，返回手机'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.getRect(harness.control), expanded);
      expect(harness.exits, 0);
      expect(harness.remoteTouches, 0);
    },
  );

  testWidgets(
    'keyboard and split viewport changes keep the exit button reachable',
    (tester) async {
      final harness = await _pumpHandle(tester);
      await tester.drag(harness.control, const Offset(0, 800));
      await tester.pumpAndSettle();
      await tester.tap(harness.control);
      await tester.pumpAndSettle();

      await _pumpHandle(
        tester,
        harness: harness,
        size: const Size(393, 600),
        viewInsets: const EdgeInsets.only(bottom: 260),
      );
      expect(find.bySemanticsLabel('退出控制，返回手机'), findsOneWidget);
      expect(tester.getRect(harness.control).bottom, lessThanOrEqualTo(328));
      await tester.tap(harness.control);
      await tester.pump();
      expect(harness.exits, 1);
      expect(harness.remoteTouches, 0);
    },
  );

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

class _HandleHarness {
  var exits = 0;
  var remoteTouches = 0;

  Finder get control => find.descendant(
    of: find.byType(ExitHandle),
    matching: find.byType(GestureDetector),
  );
}

Future<_HandleHarness> _pumpHandle(
  WidgetTester tester, {
  _HandleHarness? harness,
  Size size = const Size(393, 874),
  EdgeInsets padding = EdgeInsets.zero,
  EdgeInsets systemGestureInsets = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final controlHarness = harness ?? _HandleHarness();
  await tester.pumpWidget(
    MaterialApp(
      theme: ConnectTokens.theme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: padding,
          systemGestureInsets: systemGestureInsets,
          viewInsets: viewInsets,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) => controlHarness.remoteTouches++,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            ExitHandle(deviceLabel: '手机', onExit: () => controlHarness.exits++),
          ],
        ),
      ),
    ),
  );
  return controlHarness;
}
