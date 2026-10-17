import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/devices_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'support/test_controller.dart';

const _pendingMessage = '正在核验设备与活动状态，完成前暂缓新的操作。';

Json _snapshot() => {
  'devices': <Json>[],
  'settings': <String, dynamic>{},
  'sessions': <Json>[],
  'shares': <Json>[],
  'sequence': 7,
};

void main() {
  testWidgets(
    'PageFrame retains content and offers only reconciliation after a failed recovery',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final retry = Completer<Json>();
      final commands = <String>[];
      var stops = 0;
      final controller = createTestController((command, [params = const {}]) {
        commands.add(command);
        events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
        return retry.future;
      }, events: events.stream);
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp(
            home: PageFrame(
              title: '当前活动',
              child: Center(
                child: TextButton(
                  onPressed: () => stops++,
                  child: const Text('停止当前活动'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(_pendingMessage), findsNothing);
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      await tester.pumpAndSettle();
      expect(find.text(_pendingMessage), findsOneWidget);
      expect(find.text('停止当前活动'), findsOneWidget);
      await tester.tap(find.text('停止当前活动'));
      expect(stops, 1);
      events.add({
        'type': 'state.resync.failed',
        'data': {'reason': '设备状态检查超时'},
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('设备状态检查超时'), findsOneWidget);
      await tester.tap(find.text('重新核验'));
      await tester.pumpAndSettle();
      expect(commands, ['state.reconcile']);
      expect(find.text(_pendingMessage), findsOneWidget);
      expect(find.text('重新核验'), findsNothing);
      events.add({'type': 'state.resynced', 'data': _snapshot()});
      retry.complete(_snapshot());
      await tester.pumpAndSettle();
      expect(find.text(_pendingMessage), findsNothing);
      expect(find.text('重新核验'), findsNothing);
      expect(find.text('停止当前活动'), findsOneWidget);
      expect(commands, ['state.reconcile']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'the devices sliver exposes reconciliation without creating a session',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
        events.add({'type': 'state.resynced', 'data': _snapshot()});
        return _snapshot();
      }, events: events.stream)..loading = false;
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp(
            home: Scaffold(body: DevicesPage(controller: controller)),
          ),
        ),
      );
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      await tester.pumpAndSettle();
      expect(find.text(_pendingMessage), findsOneWidget);
      events.add({
        'type': 'state.resync.failed',
        'data': {'reason': '暂时无法核验'},
      });
      await tester.pumpAndSettle();
      expect(find.text('设备'), findsOneWidget);
      expect(find.text('添加你的第一台设备'), findsOneWidget);
      await tester.tap(find.text('重新核验'));
      await tester.pumpAndSettle();
      expect(find.text('重新核验'), findsNothing);
      expect(commands, ['state.reconcile']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'large text keeps both recovery retry and the page action reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <String>[];
      var stops = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return <String, dynamic>{};
      }, events: events.stream);
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp(
            home: PageFrame(
              title: '当前活动',
              child: Center(
                child: TextButton(
                  onPressed: () => stops++,
                  child: const Text('停止活动'),
                ),
              ),
            ),
          ),
        ),
      );
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resync.failed',
        'data': {'reason': List.filled(12, '设备状态尚未确认。').join()},
      });
      await tester.pumpAndSettle();
      expect(find.text('重新核验').hitTestable(), findsOneWidget);
      expect(find.text('停止活动').hitTestable(), findsOneWidget);
      await tester.tap(find.text('重新核验'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止活动'));
      expect(stops, 1);
      expect(commands, ['state.reconcile']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
