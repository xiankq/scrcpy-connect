import 'package:scrcpy_connect/widgets/page_chrome.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/transfers_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
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
  for (final settingsTab in [true, false]) {
    testWidgets(
      'the embedded ${settingsTab ? 'settings' : 'transfers'} tab keeps recovery and cleanup reachable with large text',
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
        final retry = Completer<Json>();
        final requests = <(String, Json)>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          requests.add((command, params));
          if (command == 'state.reconcile') {
            events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
            return retry.future;
          }
          if (command == 'transfers.list') {
            return {
              'transfers': <Json>[],
              'batches': [
                {
                  'batchId': 'original-batch',
                  'direction': 'push',
                  'status': 'running',
                  'canCancel': true,
                },
              ],
            };
          }
          if (command == 'activities.list') {
            return {
              'activities': [
                {'id': 'original-activity', 'name': '原有连接', 'canStop': true},
              ],
            };
          }
          return <String, dynamic>{};
        }, events: events.stream)..loading = false;
        final router = createAppRouter(
          initialLocation: settingsTab
              ? const SettingsRoute().location
              : const TransfersRoute().location,
        );
        try {
          await tester.pumpWidget(
            TestProviderScope(
              controller: controller,
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            settingsTab
                ? find.byType(SettingsPage)
                : find.byType(TransfersPage),
            findsOneWidget,
          );
          events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
          await tester.pumpAndSettle();
          expect(controller.snapshot().reconciliationPending, isTrue);
          expect(find.text(_pendingMessage), findsOneWidget);
          events.add({
            'type': 'state.resync.failed',
            'data': {'reason': List.filled(12, '设备状态尚未确认。').join()},
          });
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(find.text('重新核验')),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(find.text('重新核验').hitTestable(), findsOneWidget);
          final action = find.text(settingsTab ? '当前活动' : '取消本批传输');
          final page = settingsTab
              ? find.byType(SettingsPage)
              : find.byType(TransfersPage);
          final list = find.descendant(
            of: page,
            matching: find.byType(ListView),
          );
          final scrollable = find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(action, 100, scrollable: scrollable);
          await Scrollable.ensureVisible(tester.element(action), alignment: .5);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          await tester.tap(action);
          await tester.pumpAndSettle();
          if (settingsTab) {
            await tester.tap(find.text('停止'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('停止活动'));
          } else {
            await tester.tap(find.text('取消传输'));
          }
          await tester.pumpAndSettle();
          final cleanup = requests.where(
            (r) =>
                r.$1 == (settingsTab ? 'activities.stop' : 'transfers.cancel'),
          );
          expect(
            cleanup.single.$2,
            settingsTab
                ? {'activityId': 'original-activity'}
                : {'batchId': 'original-batch'},
          );
          if (settingsTab) {
            router.pop();
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(
            find.text('重新核验'),
            -200,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(
            tester.element(find.text('重新核验')),
            alignment: .5,
          );
          await tester.pumpAndSettle();
          expect(find.text('重新核验').hitTestable(), findsOneWidget);
          await tester.tap(find.text('重新核验'));
          await tester.pumpAndSettle();
          expect(
            requests.where((r) => r.$1 == 'state.reconcile'),
            hasLength(1),
          );
          events.add({'type': 'state.resynced', 'data': _snapshot()});
          retry.complete(_snapshot());
          await tester.pumpAndSettle();
          expect(find.text('重新核验'), findsNothing);
          expect(find.text(_pendingMessage), findsNothing);
          expect(requests.where((r) => r.$1.endsWith('.start')), isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          if (!retry.isCompleted) retry.complete(_snapshot());
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          controller.dispose();
          await events.close();
        }
      },
    );
  }
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
              child: PageChromeBody(
                child: Center(
                  child: TextButton(
                    onPressed: () => stops++,
                    child: const Text('停止当前活动'),
                  ),
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
              child: PageChromeBody(
                child: Center(
                  child: TextButton(
                    onPressed: () => stops++,
                    child: const Text('停止活动'),
                  ),
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
