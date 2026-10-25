import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';
import 'package:scrcpy_connect/pages/transfers/index/transfers_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';

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
        var transferStopped = false;
        var transferRemoved = false;
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
              'transfers': <Json>[
                if (!transferRemoved)
                  {
                    'id': 'original-task',
                    'batchId': 'original-batch',
                    'deviceId': 'phone',
                    'name': '原有文件.pdf',
                    'kind': 'file',
                    'direction': 'push',
                    'status': transferStopped ? 'cancelled' : 'running',
                    'canCancel': !transferStopped,
                    'totalBytes': 100,
                    'completedBytes': 20,
                  },
              ],
            };
          }
          if (command == 'transfers.cancel') {
            transferStopped = true;
          }
          if (command == 'transfers.remove') {
            expect(transferStopped, isTrue);
            transferRemoved = true;
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
          expect(find.text('当前活动'), findsNothing);
          final action = settingsTab ? find.text('外观') : find.byTooltip('传输操作');
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
            expect(find.text('浅色'), findsOneWidget);
            expect(controller.snapshot().reconciliationPending, isTrue);
            expect(
              requests.where(
                (r) => r.$1 == 'activities.list' || r.$1 == 'activities.stop',
              ),
              isEmpty,
            );
            router.pop();
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text('重新核验'),
              -200,
              scrollable: scrollable,
            );
          } else {
            final stop = find.text('停止并移除…');
            await Scrollable.ensureVisible(tester.element(stop), alignment: .5);
            await tester.pumpAndSettle();
            expect(stop.hitTestable(), findsOneWidget);
            await tester.tap(stop);
            await tester.pumpAndSettle();
            expect(
              requests.where(
                (r) => r.$1 == 'transfers.cancel' || r.$1 == 'transfers.remove',
              ),
              isEmpty,
            );
            final confirm = find.text('停止并移除');
            await Scrollable.ensureVisible(
              tester.element(confirm),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            expect(confirm.hitTestable(), findsOneWidget);
            await tester.tap(confirm);
            await tester.pumpAndSettle();
            final cleanup = requests
                .where(
                  (r) =>
                      r.$1 == 'transfers.cancel' || r.$1 == 'transfers.remove',
                )
                .toList();
            expect(cleanup.map((r) => r.$1), [
              'transfers.cancel',
              'transfers.remove',
            ]);
            expect(
              cleanup.every((r) => r.$2['batchId'] == 'original-batch'),
              isTrue,
            );
            final cancelIndex = requests.indexWhere(
              (r) => r.$1 == 'transfers.cancel',
            );
            final removeIndex = requests.indexWhere(
              (r) => r.$1 == 'transfers.remove',
            );
            expect(
              requests
                  .sublist(cancelIndex + 1, removeIndex)
                  .any((r) => r.$1 == 'transfers.list'),
              isTrue,
            );
            expect(transferRemoved, isTrue);
            expect(find.text('原有文件.pdf'), findsNothing);
          }
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
}
