import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/models/app_state.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'an unknown startup wake never submits or blindly replays application launch',
    (tester) async {
      final calls = <String>[];
      final controller = createTestController(
        (command, [params = const {}]) async {
          calls.add(command);
          if (command == 'devices.wake') {
            throw const RequestFailure('result_unknown', '点亮回执未知');
          }
          return {};
        },
        initialState: AppState(
          settings: const {
            'deviceSettings': {
              'phone': {'wakeOnConnect': true},
            },
          },
        ),
      );
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
              packageName: 'com.example.app',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('应用打开结果待核对'), findsNothing);
        await tester.tap(find.text('重新检查'));
        await tester.pumpAndSettle();
        expect(
          calls.where((command) => command == 'devices.wake'),
          hasLength(1),
        );
        expect(calls.where((command) => command == 'session.start'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'closing while startup wake is pending cannot start a late window',
    (tester) async {
      final pending = Completer<Json>();
      final wakeRequested = Completer<void>();
      final calls = <String>[];
      final controller = createTestController(
        (command, [params = const {}]) async {
          calls.add(command);
          if (command == 'devices.wake') {
            if (!wakeRequested.isCompleted) wakeRequested.complete();
            return pending.future;
          }
          return {};
        },
        initialState: AppState(
          settings: const {
            'deviceSettings': {
              'phone': {'wakeOnConnect': true},
            },
          },
        ),
      );
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
              packageName: 'com.example.app',
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(wakeRequested.isCompleted, isTrue);
        expect(
          calls.where((command) => command == 'devices.wake'),
          hasLength(1),
        );
        // 首帧前由环境加载场占据页面，工具和导航键尚未出现；关闭使用明确的启动取消动作。
        expect(find.bySemanticsLabel(RegExp('展开画面工具，')), findsNothing);
        expect(find.text('取消打开'), findsOneWidget);
        await tester.tap(find.text('取消打开'));
        await tester.pumpAndSettle();
        pending.complete({});
        await tester.pumpAndSettle();
        expect(find.byType(RemotePage), findsNothing);
        expect(calls.where((command) => command == 'session.start'), isEmpty);
        expect(
          calls.where((command) => command == 'devices.wake'),
          hasLength(1),
        );
      } finally {
        if (!pending.isCompleted) pending.complete({});
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'each new phone or application window wakes even with another open window',
    (tester) async {
      final calls = <(String, Json)>[];
      var created = 0;
      final controller = createTestController(
        (command, [params = const {}]) async {
          calls.add((command, params));
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
      Widget pages() => RouterTestApp(
        controller: controller,
        home: Stack(
          children: [
            RemotePage(
              key: const ValueKey('phone'),
              controller: controller,
              device: const {'id': 'phone'},
            ),
            RemotePage(
              key: const ValueKey('app'),
              controller: controller,
              device: const {'id': 'phone'},
              packageName: 'com.example.app',
            ),
          ],
        ),
      );
      try {
        await tester.pumpWidget(pages());
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'devices.wake'), hasLength(2));
        expect(
          calls
              .where((c) => c.$1 == 'session.start')
              .map((c) => c.$2['keepActive']),
          [true, true],
        );
        await tester.pumpWidget(pages());
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'devices.wake'), hasLength(2));
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
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
        final calls = <(String, Json)>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          calls.add((command, params));
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
        }, initialState: AppState(devices: const [device]));
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              devices: const [device],
              home: RemotePage(controller: controller, device: device),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('转为独立窗口'));
          await tester.pumpAndSettle();
          if (match) {
            expect(
              tester.widget<RemotePage>(find.byType(RemotePage)).packageName,
              'com.example.app',
            );
            expect(
              calls.where(
                (c) =>
                    c.$1 == 'session.start' &&
                    c.$2['packageName'] == 'com.example.app',
              ),
              hasLength(1),
            );
            expect(calls.where((c) => c.$1 == 'session.stop').single.$2, {
              'sessionId': 'phone-screen',
              'keepTask': true,
            });
            await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
            await tester.pumpAndSettle();
            expect(find.text('转为独立窗口'), findsNothing);
          } else {
            expect(
              tester.widget<RemotePage>(find.byType(RemotePage)).packageName,
              isNull,
            );
            expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
            expect(calls.where((c) => c.$1 == 'session.stop'), isEmpty);
            expect(find.textContaining('没有可接续的应用任务'), findsOneWidget);
          }
          expect(
            calls
                .where((c) => c.$1 == 'apps.foreground')
                .every((c) => c.$2['connectionId'] == 'connection'),
            isTrue,
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }
}
