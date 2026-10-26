import 'package:scrcpy_connect/pages/devices/workspace/remote/widgets/exit_handle.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pointer cancellation clears press feedback without exiting', (
    tester,
  ) async {
    final harness = await _pumpHandle(tester);
    expect(find.byType(GlassPressFeedback), findsOneWidget);
    final pointer = await tester.startGesture(
      tester.getCenter(harness.control),
    );
    await tester.pump();
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(harness.exits, 0);
    expect(harness.remoteTouches, 0);
    expect(find.bySemanticsLabel(RegExp('(?:展开|收起)画面工具，手机')), findsOneWidget);

    final drag = await tester.startGesture(tester.getCenter(harness.control));
    await drag.moveBy(const Offset(100, 70));
    await tester.pump();
    await drag.cancel();
    await tester.pumpAndSettle();
    expect(harness.exits, 0);
    expect(harness.remoteTouches, 0);
    expect(find.bySemanticsLabel('展开画面工具，手机，连接状态待核对'), findsOneWidget);

    await tester.tap(harness.control);
    await tester.pumpAndSettle();
    expect(harness.exits, 0);
    await tester.ensureVisible(find.text('关闭画面'));
    await tester.tap(find.text('关闭画面'));
    await tester.pump();
    expect(harness.exits, 1);
  });

  testWidgets(
    'phone-width native drag path leaves a 44px hittable collapsed control that expands and exits',
    (tester) async {
      final harness = await _pumpHandle(tester);
      final semantics = tester.ensureSemantics();
      final handle = find.byKey(const ValueKey('remote-tool-handle'));
      await tester.drag(handle, const Offset(393 * .72, 100));
      await tester.pump(const Duration(milliseconds: 1200));
      final collapsed = find.bySemanticsLabel(RegExp('展开画面工具，'));
      expect(collapsed, findsOneWidget);
      expect(tester.getSize(handle).width, 44);
      expect(tester.getRect(collapsed), tester.getRect(handle));
      await tester.tap(collapsed);
      await tester.pump(const Duration(milliseconds: 300));
      final expanded = find.bySemanticsLabel(RegExp('收起画面工具，'));
      expect(expanded, findsOneWidget);
      expect(harness.exits, 0);
      expect(harness.remoteTouches, 0);
      await tester.ensureVisible(find.text('关闭画面'));
      await tester.tap(find.text('关闭画面'));
      await tester.pump();
      expect(harness.exits, 1);
      semantics.dispose();
    },
  );
  testWidgets(
    'expanding interrupts an unfinished snap and preserves the expanded position',
    (tester) async {
      await _pumpHandle(tester);
      final handle = find.byKey(const ValueKey('remote-tool-handle'));
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

  Finder get control => find.byKey(const ValueKey('remote-tool-handle'));
}

Future<_HandleHarness> _pumpHandle(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final controlHarness = _HandleHarness();
  await tester.pumpWidget(
    MaterialApp(
      theme: ConnectTokens.theme(Brightness.light),
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
