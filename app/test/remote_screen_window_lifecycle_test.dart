import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/app_state.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';

import 'support/remote_page_fixture.dart';
import 'support/router_test_app.dart';

void main() {
  testWidgets(
    'an unknown startup wake never submits or blindly replays application launch',
    (tester) async {
      final h = RemotePageFixture(
        onRequest: (command, params) {
          if (command == 'devices.wake') {
            throw const RequestFailure('result_unknown', '点亮回执未知');
          }
          return {};
        },
      );
      await h.show(tester, packageName: 'com.example.app');
      await tester.pumpAndSettle();
      expect(find.text('应用打开结果待核对'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(h.commands('devices.wake'), hasLength(1));
      expect(h.commands('session.start'), isEmpty);
    },
  );

  testWidgets(
    'closing while startup wake is pending cannot start a late window',
    (tester) async {
      final pending = Completer<Json>();
      final wakeRequested = Completer<void>();
      final h = RemotePageFixture(
        onRequest: (command, params) {
          if (command == 'devices.wake') {
            if (!wakeRequested.isCompleted) wakeRequested.complete();
            return pending.future;
          }
          return {};
        },
      );
      await h.show(tester, packageName: 'com.example.app');
      addTearDown(() {
        if (!pending.isCompleted) pending.complete({});
      });
      await tester.pump();
      await tester.pump();
      expect(wakeRequested.isCompleted, isTrue);
      expect(h.commands('devices.wake'), hasLength(1));
      // 首帧前直接关闭等待；不展示尚不可用的画面工具，也不提交迟到的窗口。
      expect(find.bySemanticsLabel(RegExp('展开画面工具，')), findsNothing);
      expect(find.byKey(const ValueKey('remote-tool-panel')), findsNothing);
      expect(find.text('取消打开'), findsNothing);
      await tester.tap(find.byTooltip('关闭等待'));
      await tester.pumpAndSettle();
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsNothing);
      expect(h.commands('session.start'), isEmpty);
      expect(h.commands('devices.wake'), hasLength(1));
    },
  );

  testWidgets(
    'each new phone or application window wakes even with another open window',
    (tester) async {
      var created = 0;
      final h = RemotePageFixture(
        onRequest: (command, params) {
          if (command == 'session.start') {
            return {
              'sessionId': 'screen-${++created}',
              'textureId': created,
              'width': 400,
              'height': 800,
            };
          }
          return {};
        },
        initialState: AppState(
          settings: const {
            'deviceSettings': {
              'phone': {'wakeOnConnect': true, 'stayAwake': true},
            },
          },
        ),
      );
      Widget windows() => Stack(
        children: [
          RemotePage(
            key: const ValueKey('phone'),
            controller: h.controller,
            device: const {'id': 'phone'},
          ),
          RemotePage(
            key: const ValueKey('app'),
            controller: h.controller,
            device: const {'id': 'phone'},
            packageName: 'com.example.app',
          ),
        ],
      );
      await h.show(tester, home: windows());
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      });
      await tester.pumpAndSettle();
      expect(h.commands('devices.wake'), hasLength(2));
      expect(h.commands('session.start').map((p) => p['keepActive']), [
        true,
        true,
      ]);
      await tester.pumpWidget(
        RouterTestApp(controller: h.controller, home: windows()),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(h.commands('devices.wake'), hasLength(2));
    },
  );
  for (final match in [true, false]) {
    testWidgets(
      'conversion requires a confirmed running foreground task: match=$match',
      (tester) async {
        const device = {
          'id': 'phone',
          'connectionId': 'connection',
          'apiLevel': 35,
          'status': 'connected',
        };
        final h = RemotePageFixture(
          onRequest: (command, params) {
            if (command == 'session.start') {
              return {
                'sessionId': params['packageName'] == null
                    ? 'phone-screen'
                    : 'app-screen',
                'textureId': 1,
                'width': 400,
                'height': 800,
              };
            }
            if (command == 'apps.foreground') {
              return {
                'deviceId': 'phone',
                'connectionId': 'connection',
                'packageName': 'com.example.app',
                'source': 'resumedActivity',
              };
            }
            if (command == 'apps.list') {
              return {
                'deviceId': 'phone',
                'source': 'runningTasks',
                'live': true,
                'apps': [
                  if (match) {'packageName': 'com.example.app', 'taskId': 42},
                ],
              };
            }
            return {};
          },
          initialState: AppState(devices: const [device]),
        );
        await h.show(
          tester,
          devices: const [device],
          home: RemotePage(controller: h.controller, device: device),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('转为独立窗口'));
        await tester.pumpAndSettle();
        final page = tester.widget<RemotePage>(find.byType(RemotePage));
        if (match) {
          expect(page.packageName, 'com.example.app');
          expect(
            h
                .commands('session.start')
                .where((p) => p['packageName'] == 'com.example.app'),
            hasLength(1),
          );
          expect(h.commands('session.stop').single, {
            'sessionId': 'phone-screen',
            'keepTask': true,
          });
          await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
          await tester.pumpAndSettle();
          expect(find.text('转为独立窗口'), findsNothing);
        } else {
          expect(page.packageName, isNull);
          expect(h.commands('session.start'), hasLength(1));
          expect(h.commands('session.stop'), isEmpty);
          expect(find.textContaining('没有可接续的应用任务'), findsOneWidget);
        }
        expect(
          h
              .commands('apps.foreground')
              .every((p) => p['connectionId'] == 'connection'),
          isTrue,
        );
      },
    );
  }
}
