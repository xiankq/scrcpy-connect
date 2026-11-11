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
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app_launcher.dart';

const _package = 'com.android.settings';
Json _screen(String id) => {
  'sessionId': id,
  'deviceId': 'phone',
  'status': 'ready',
  'textureId': 1,
  'width': 200,
  'height': 400,
  'firstFrameDecoded': true,
  'evidence': 'media_codec.decodedFrame',
};

List<Json> _sent(List<(String, Json)> calls, String command) => [
  for (final call in calls)
    if (call.$1 == command) call.$2,
];

AppStore _controller(
  List<(String, Json)> calls,
  Future<Json> Function(String, Json) respond,
) => createTestController((command, params) {
  calls.add((command, params));
  return respond(command, params);
});

Future<void> _showRemote(
  WidgetTester tester,
  AppStore controller, {
  Json device = const {'id': 'phone', 'apiLevel': 35},
  String? packageName,
  RemoteControlIntent? action,
}) => tester.pumpWidget(
  RouterTestApp(
    controller: controller,
    home: RemotePage(
      controller: controller,
      device: device,
      packageName: packageName,
      initialAction: action,
    ),
  ),
);

void _background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'app choice is remembered, editable and reuses retained screens',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final calls = <(String, Json)>[];
      const phone = {'id': 'phone', 'name': '我的手机', 'apiLevel': 28};
      var screen = _screen('phone-screen');
      var activeApp = false, listed = true;
      final controller = _controller(calls, (command, params) async {
        if (command == 'session.stop') listed = false;
        if (command == 'session.start') {
          screen = _screen('replacement-screen');
          listed = true;
          return screen;
        }
        return switch (command) {
          'apps.list' => {
            'apps': [
              {'name': '设置', 'packageName': _package},
            ],
          },
          'session.list' => {
            'sessions': [
              if (activeApp)
                {
                  ..._screen('active-app'),
                  'packageName': _package,
                  'kind': 'app',
                }
              else if (listed)
                screen,
            ],
          },
          'session.resume' =>
            activeApp
                ? {
                    ..._screen('active-app'),
                    'packageName': _package,
                    'kind': 'app',
                  }
                : screen,
          'settings.update' => params,
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
        await _tap(tester, find.text('设置').hitTestable().first);
        final window = find.widgetWithText(OutlinedButton, '在独立窗口打开');
        expect(tester.widget<OutlinedButton>(window).onPressed, isNull);
        expect(find.widgetWithText(FilledButton, '在手机屏幕打开'), findsOneWidget);
        await _tap(tester, find.text('在手机屏幕打开'));
        expect(find.byType(RemotePage), findsOneWidget);
        expect(_sent(calls, 'session.start'), isEmpty);
        final launch = _sent(calls, 'session.launch').single;
        expect(launch['sessionId'], 'phone-screen');
        expect(launch['deviceId'], 'phone');
        expect(launch['packageName'], _package);
        expect(controller.appOpenMode('phone', _package), 'phone');
        Navigator.of(tester.element(find.byType(RemotePage))).pop();
        await tester.pumpAndSettle();
        await _tap(tester, find.text('设置').hitTestable().first);
        expect(find.byType(BottomSheet), findsNothing);
        expect(_sent(calls, 'session.launch'), hasLength(2));
        expect(_sent(calls, 'settings.update'), hasLength(1));
        Navigator.of(tester.element(find.byType(RemotePage))).pop();
        await tester.pumpAndSettle();
        await _tap(tester, find.byTooltip('更改打开方式'));
        expect(find.text('在手机屏幕打开'), findsOneWidget);
        await _tap(tester, find.text('取消'));
        controller.devices = [
          {...phone, 'apiLevel': 35},
        ];
        await controller.rememberAppOpenMode('phone', _package, 'window');
        final opening = openPhoneApp(
          tester.element(find.byType(AppsPage)),
          controller,
          phone,
          const {'packageName': _package, 'name': '设置'},
          existingTask: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('切换应用打开方式？'), findsOneWidget);
        expect(_sent(calls, 'session.start'), hasLength(1));
        await _tap(tester, find.text('取消'));
        await opening;
        expect(find.byType(RemotePage), findsNothing);
        activeApp = true;
        await _tap(tester, find.text('设置').hitTestable().first);
        expect(find.byType(RemotePage), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(_sent(calls, 'session.launch'), hasLength(2));
        expect(_sent(calls, 'session.start'), hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'a pending phone-screen app launch runs once after foreground resume even when its result is unknown',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final pendingStart = Completer<Json>();
      final calls = <(String, Json)>[];
      final screen = _screen('deferred-main');
      final controller = _controller(calls, (command, params) async {
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
        await _showRemote(
          tester,
          controller,
          device: const {'id': 'phone'},
          action: const RemoteControlIntent.launchApp(_package),
        );
        await tester.pump();
        expect(_sent(calls, 'session.start'), hasLength(1));
        _background(tester);
        pendingStart.complete(screen);
        await tester.pumpAndSettle();
        expect(
          _sent(calls, 'session.launch'),
          isEmpty,
          reason: 'The pending app action must wait while the page is backgrounded.',
        );
        expect(_sent(calls, 'session.pause'), hasLength(1));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(_sent(calls, 'session.resume'), hasLength(1));
        final launch = _sent(calls, 'session.launch').toList();
        expect(
          launch,
          hasLength(1),
          reason: 'A successful foreground resume must apply the app action skipped during startup.',
        );
        expect(launch.single['sessionId'], 'deferred-main');
        expect(launch.single['packageName'], _package);
        expect(find.text('启动请求结果未知'), findsOneWidget);

        _background(tester);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(
          _sent(calls, 'session.launch'),
          hasLength(1),
          reason: 'Once submitted, a later resume must not replay even an unknown result.',
        );
        expect(_sent(calls, 'session.start'), hasLength(1));
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
        final screen = _screen('held-main');
        const unknown = {
          'sessionId': 'held-open-record',
          'launchOperationId': 'held-open-record',
          'linkedSessionId': 'held-main',
          'deviceId': 'phone',
          'packageName': _package,
          'status': 'failed',
          'launchOutcome': 'unknown',
          'recordOnly': true,
        };
        final controller = _controller(calls, (command, params) async {
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
          await _showRemote(
            tester,
            controller,
            device: const {'id': 'phone'},
            action: const RemoteControlIntent.launchApp(_package),
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
          await _tap(tester, find.text('只读检查'));
          await _tap(tester, find.text('关闭本次打开记录'));
          await _tap(tester, find.text('确认关闭'));
          expect(
            _sent(calls, 'session.stop').single['sessionId'],
            'held-open-record',
          );
          expect(_sent(calls, 'session.launch'), hasLength(1));
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
          expect(_sent(calls, 'session.key'), hasLength(1));
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
        'packageName': _package,
        'status': 'failed',
        'launchOutcome': 'unknown',
      };
      final controller = _controller(calls, (command, params) async {
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
            'sessions': [
              if (listed)
                {
                  ...unknown,
                  'sessionId': 'other-window',
                  'status': 'ready',
                  'launchOutcome': 'sent',
                },
              if (listed) unknown,
            ],
          },
          'apps.list' => {
            'apps': [
              {'name': '设置', 'packageName': _package},
            ],
          },
          _ => {},
        };
      });
      Widget page(Key key) => RouterTestApp(
        key: key,
        controller: controller,
        home: listed
            ? AppsPage(
                controller: controller,
                device: const {'id': 'phone', 'apiLevel': 35},
              )
            : RemotePage(
                controller: controller,
                device: const {'id': 'phone', 'apiLevel': 35},
                packageName: _package,
              ),
      );
      try {
        await tester.pumpWidget(page(const ValueKey('first')));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('重新核对'));
        expect(_sent(calls, 'session.start'), hasLength(1));
        expect(
          calls.where(
            (c) => c.$1 == 'session.list' && c.$2['deviceId'] == 'phone',
          ),
          hasLength(2),
        );
        expect(_sent(calls, 'session.resume'), isEmpty);
        expect(find.text('在手机屏幕继续'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(page(const ValueKey('second')));
        await tester.pumpAndSettle();
        await _tap(tester, find.byTooltip('更改打开方式'));
        expect(find.text('在手机屏幕打开'), findsNothing);
        expect(find.text('重新核对'), findsOneWidget);
        expect(_sent(calls, 'session.start'), hasLength(1));
        await _tap(tester, find.text('关闭本次打开记录'));
        expect(_sent(calls, 'session.stop'), isEmpty);
        await _tap(tester, find.text('确认关闭'));
        expect(_sent(calls, 'session.stop'), hasLength(1));
        expect(_sent(calls, 'session.start'), hasLength(1));
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
      final controller = createTestController((command, params) async {
        calls.add(command);
        if (command == 'session.start') throw failure;
        return command == 'session.list' ? {'sessions': <Json>[]} : {};
      });
      try {
        await _showRemote(
          tester,
          controller,
          device: const {'id': 'phone', 'apiLevel': 35},
          packageName: _package,
        );
        await tester.pumpAndSettle();
        final notSubmitted =
            jsonObject(failure.details)['launchOutcome'] == 'not_submitted';
        await _tap(tester, find.text(notSubmitted ? '重试' : '重新核对'));
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
      final screen = _screen('main');
      final controller = _controller(calls, (command, params) async {
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
        await _showRemote(
          tester,
          controller,
          device: phone,
          packageName: _package,
        );
        await tester.pumpAndSettle();
        expect(_sent(calls, 'session.launch'), isEmpty);
        await _tap(tester, find.text('在手机屏幕继续'));
        expect(_sent(calls, 'session.launch'), isEmpty);
        await _tap(tester, find.text('继续打开'));
        expect(_sent(calls, 'session.start'), hasLength(1));
        final launch = _sent(calls, 'session.launch').single;
        expect(launch['sessionId'], 'main');
        expect(launch['packageName'], _package);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
