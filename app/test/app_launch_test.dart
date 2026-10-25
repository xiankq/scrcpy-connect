import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'support/test_controller.dart';
import 'support/router_test_app.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/apps/devices_workspace_apps_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';

void main() {
  testWidgets('older phones open an app on the retained phone screen', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final calls = <(String, Json)>[];
    const phone = {'id': 'phone', 'name': '我的手机', 'apiLevel': 28};
    const screen = {
      'sessionId': 'phone-screen',
      'deviceId': 'phone',
      'status': 'ready',
      'textureId': 3,
      'width': 200,
      'height': 400,
      'firstFrameDecoded': true,
      'evidence': 'media_codec.decodedFrame',
    };
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add((command, params));
      return switch (command) {
        'apps.list' => {
          'apps': [
            {'name': '设置', 'packageName': 'com.android.settings'},
          ],
        },
        'session.list' => {
          'sessions': [screen],
        },
        'session.resume' => screen,
        _ => {},
      };
    });
    try {
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: AppsPage(controller: controller, device: phone),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('在独立窗口打开'), findsNothing);
      expect(find.text('在手机屏幕打开'), findsOneWidget);
      await tester.tap(find.text('在手机屏幕打开'));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);
      expect(calls.where((c) => c.$1 == 'session.start'), isEmpty);
      final launch = calls.singleWhere((c) => c.$1 == 'session.launch').$2;
      expect(launch['sessionId'], 'phone-screen');
      expect(launch['deviceId'], 'phone');
      expect(launch['packageName'], 'com.android.settings');
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets(
    'a pending phone-screen app launch runs once after foreground resume even when its result is unknown',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final pendingStart = Completer<Json>();
      final calls = <(String, Json)>[];
      const screen = {
        'sessionId': 'deferred-main',
        'deviceId': 'phone',
        'status': 'ready',
        'textureId': 1,
        'width': 200,
        'height': 400,
        'firstFrameDecoded': true,
        'evidence': 'media_codec.decodedFrame',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.start') return pendingStart.future;
        if (command == 'session.launch') {
          throw const RequestFailure('timeout', '启动请求结果未知');
        }
        return switch (command) {
          'session.list' => {'sessions': <Json>[]},
          'session.resume' => screen,
          'session.pause' => {
            ...screen,
            'status': 'paused',
            'capturePaused': true,
          },
          _ => {},
        };
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
              initialAction: const RemoteControlIntent.launchApp(
                'com.android.settings',
              ),
            ),
          ),
        );
        await tester.pump();
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        pendingStart.complete(screen);
        await tester.pumpAndSettle();
        expect(
          calls.where((c) => c.$1 == 'session.launch'),
          isEmpty,
          reason: 'The pending app action must wait while the page is backgrounded.',
        );
        expect(calls.where((c) => c.$1 == 'session.pause'), hasLength(1));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.resume'), hasLength(1));
        final launch = calls.where((c) => c.$1 == 'session.launch').toList();
        expect(
          launch,
          hasLength(1),
          reason: 'A successful foreground resume must apply the app action skipped during startup.',
        );
        expect(launch.single.$2['sessionId'], 'deferred-main');
        expect(launch.single.$2['packageName'], 'com.android.settings');
        expect(find.text('启动请求结果未知'), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(
          calls.where((c) => c.$1 == 'session.launch'),
          hasLength(1),
          reason: 'Once submitted, a later resume must not replay even an unknown result.',
        );
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
      } finally {
        if (!pendingStart.isCompleted) pendingStart.complete(screen);
        await tester.pumpWidget(const SizedBox());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        controller.dispose();
      }
    },
  );

  for (final stalled in ['pause', 'key-up']) {
    testWidgets(
      'unknown phone-screen opening can be checked and closed while $stalled is pending',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final launch = Completer<Json>();
        final blocked = Completer<Json>();
        final calls = <(String, Json)>[];
        const screen = {
          'sessionId': 'held-main',
          'deviceId': 'phone',
          'textureId': 1,
          'width': 200,
          'height': 400,
          'status': 'ready',
          'firstFrameDecoded': true,
          'evidence': 'media_codec.decodedFrame',
        };
        const unknown = {
          'sessionId': 'held-open-record',
          'launchOperationId': 'held-open-record',
          'linkedSessionId': 'held-main',
          'deviceId': 'phone',
          'packageName': 'com.android.settings',
          'status': 'failed',
          'launchOutcome': 'unknown',
          'recordOnly': true,
        };
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          calls.add((command, params));
          if ((stalled == 'pause' && command == 'session.pause') ||
              (stalled == 'key-up' &&
                  command == 'session.key' &&
                  params['action'] == 'up')) {
            return blocked.future;
          }
          return switch (command) {
            'session.list' => {
              'sessions': [screen],
            },
            'session.resume' => screen,
            'session.launch' => launch.future,
            _ => {},
          };
        });
        TestGesture? gesture;
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              home: RemotePage(
                controller: controller,
                device: const {'id': 'phone'},
                initialAction: const RemoteControlIntent.launchApp(
                  'com.android.settings',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
          gesture = await tester.startGesture(
            const Offset(400, 300),
            pointer: 101,
          );
          launch.completeError(
            const RequestFailure('app_launch_unknown', '应用打开结果未知', unknown),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 30));
          expect(find.text('关闭本次打开记录'), findsOneWidget);
          await tester.tap(find.text('只读检查'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('关闭本次打开记录'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('确认关闭'));
          await tester.pumpAndSettle();
          expect(
            calls.singleWhere((c) => c.$1 == 'session.stop').$2['sessionId'],
            'held-open-record',
          );
          expect(calls.where((c) => c.$1 == 'session.launch'), hasLength(1));
          expect(blocked.isCompleted, isFalse);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
          blocked.complete({});
          await tester.pumpAndSettle();
          final keyUp = calls.singleWhere(
            (c) => c.$1 == 'session.key' && c.$2['action'] == 'up',
          );
          final pointerCancel = calls.singleWhere(
            (c) => c.$1 == 'session.touch' && c.$2['action'] == 'cancel',
          );
          final paused = calls.singleWhere((c) => c.$1 == 'session.pause');
          expect(keyUp.$2['sessionId'], 'held-main');
          expect(pointerCancel.$2['sessionId'], 'held-main');
          expect(paused.$2['sessionId'], 'held-main');
          expect(calls.indexOf(keyUp), lessThan(calls.indexOf(paused)));
          expect(calls.indexOf(pointerCancel), lessThan(calls.indexOf(paused)));
          expect(calls.where((c) => c.$1 == 'session.key'), hasLength(1));
        } finally {
          if (!launch.isCompleted) launch.complete({});
          if (!blocked.isCompleted) blocked.complete({});
          await gesture?.up();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }

  testWidgets(
    'unknown independent app launch is checked without replay across page entry',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final calls = <(String, Json)>[];
      var listed = false;
      const unknown = {
        'sessionId': 'unknown-open',
        'deviceId': 'phone',
        'packageName': 'com.android.settings',
        'status': 'failed',
        'launchOutcome': 'unknown',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.start') {
          listed = true;
          throw const RequestFailure(
            'app_launch_unknown',
            '应用可能已打开，请先核对。',
            unknown,
          );
        }
        return switch (command) {
          'session.list' => {
            'sessions': [if (listed) unknown],
          },
          _ => {},
        };
      });
      Widget page(Key key) => RouterTestApp(
        key: key,
        controller: controller,
        home: RemotePage(
          controller: controller,
          device: const {'id': 'phone', 'apiLevel': 35},
          packageName: 'com.android.settings',
        ),
      );
      try {
        await tester.pumpWidget(page(const ValueKey('first')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(RegExp('只读检查|重新检查')));
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        expect(
          calls.where(
            (c) => c.$1 == 'session.list' && c.$2['deviceId'] == 'phone',
          ),
          hasLength(2),
        );
        expect(calls.where((c) => c.$1 == 'session.resume'), isEmpty);
        expect(find.text('在手机屏幕继续'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(page(const ValueKey('second')));
        await tester.pumpAndSettle();
        expect(find.text('只读检查'), findsOneWidget);
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        await tester.tap(find.text('关闭本次打开记录'));
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.stop'), isEmpty);
        await tester.tap(find.text('确认关闭'));
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.stop'), hasLength(1));
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        expect(find.text('重新打开'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  for (final failure in [
    const RequestFailure('timeout', '提交前连接超时', {
      'launchOutcome': 'not_submitted',
    }),
    const RequestFailure('encoder_start_failed', '编码首帧结果未知'),
  ]) {
    testWidgets('independent app retry respects ${failure.message}', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        if (command == 'session.start') throw failure;
        return command == 'session.list' ? {'sessions': <Json>[]} : {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone', 'apiLevel': 35},
              packageName: 'com.android.settings',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final notSubmitted =
            jsonObject(failure.details)['launchOutcome'] == 'not_submitted';
        await tester.tap(find.text(notSubmitted ? '重新检查' : '只读检查'));
        await tester.pumpAndSettle();
        expect(
          calls.where((c) => c == 'session.start'),
          hasLength(notSubmitted ? 2 : 1),
        );
        expect(
          calls.where((c) => c == 'session.launch' || c == 'session.resume'),
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    });
  }

  testWidgets(
    'unsupported independent window needs explicit consent before main-screen fallback',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final calls = <(String, Json)>[];
      const phone = {'id': 'phone', 'apiLevel': 28};
      const screen = {
        'sessionId': 'main',
        'deviceId': 'phone',
        'textureId': 1,
        'width': 200,
        'height': 400,
        'status': 'ready',
        'firstFrameDecoded': true,
        'evidence': 'media_codec.decodedFrame',
      };
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.start') {
          throw const RequestFailure('unsupported', '独立窗口不可用');
        }
        return switch (command) {
          'session.list' => {
            'sessions': [screen],
          },
          'session.resume' => screen,
          _ => {},
        };
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: const [phone],
            home: RemotePage(
              controller: controller,
              device: phone,
              packageName: 'com.android.settings',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.launch'), isEmpty);
        await tester.tap(find.text('在手机屏幕继续'));
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.launch'), isEmpty);
        await tester.tap(find.text('继续打开'));
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'session.start'), hasLength(1));
        final launch = calls.singleWhere((c) => c.$1 == 'session.launch').$2;
        expect(launch['sessionId'], 'main');
        expect(launch['packageName'], 'com.android.settings');
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
