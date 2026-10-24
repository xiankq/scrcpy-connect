import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _phone = <String, dynamic>{
  'id': 'phone',
  'name': '测试手机',
  'status': 'connected',
};

List<Json> _sessions() => [
  {
    'sessionId': 'A',
    'deviceId': 'phone',
    'name': '窗口 A',
    'packageName': 'example.a',
    'status': 'paused',
    'capturePaused': true,
    'textureId': 1,
    'width': 200,
    'height': 400,
  },
  {
    'sessionId': 'B',
    'deviceId': 'phone',
    'name': '窗口 B',
    'packageName': 'example.b',
    'status': 'paused',
    'capturePaused': true,
    'textureId': 2,
    'width': 200,
    'height': 400,
  },
];

void main() {
  for (final oldAddress in [
    '/devices/phone/sessions',
    '/devices/phone/tools?session-id=B',
  ]) {
    testWidgets(
      'old management address redirects to the workspace without replay: $oldAddress',
      (tester) async {
        final calls = <String>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          calls.add(command);
          return {};
        });
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              devices: const [_phone],
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => GoRouter.of(context).go(oldAddress),
                  child: const Text('旧地址'),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('旧地址'));
          await tester.pumpAndSettle();
          expect(find.byType(DeviceWorkspacePage), findsOneWidget);
          expect(find.byType(RemotePage), findsNothing);
          expect(
            calls.where(
              (command) =>
                  command.startsWith('session.') || command == 'devices.wake',
            ),
            isEmpty,
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }

  testWidgets(
    'closing the current B window releases its resources and preserves A',
    (tester) async {
      final sessions = _sessions();
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.list') {
          return {'sessions': sessions.map(Map<String, dynamic>.of).toList()};
        }
        if (command == 'session.resume') {
          return {
            ...sessions[1],
            'status': 'streaming',
            'firstFrameDecoded': true,
            'evidence': 'media_codec.snapshot',
          };
        }
        if (command == 'session.stop') {
          sessions.removeWhere(
            (item) => item['sessionId'] == params['sessionId'],
          );
          return {'sessionId': params['sessionId'], 'status': 'stopped'};
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: RemotePage(
              controller: controller,
              device: _phone,
              packageName: 'example.b',
              existingSession: sessions[1],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await tester.pumpAndSettle();

        expect(
          calls
              .where((call) => call.$1 == 'session.stop')
              .map((call) => call.$2),
          [
            {'sessionId': 'B', 'keepTask': true},
          ],
        );
        expect(sessions.map((item) => item['sessionId']), ['A']);
        expect(calls.where((call) => call.$1 == 'session.pause'), isEmpty);
        expect(calls.where((call) => call.$1 == 'session.start'), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'the current window screenshot captures B without a device fallback',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.list') return {'sessions': _sessions()};
        if (command == 'session.screenshot') {
          return {'localPath': '/tmp/window-b.png'};
        }
        if (command == 'session.resume') {
          return {
            ..._sessions()[1],
            'status': 'streaming',
            'firstFrameDecoded': true,
            'evidence': 'media_codec.snapshot',
          };
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: const [_phone],
            theme: ConnectTokens.theme(Brightness.light),
            home: RemotePage(
              controller: controller,
              device: _phone,
              packageName: 'example.b',
              existingSession: _sessions()[1],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('截图'));
        await tester.pumpAndSettle();

        expect(
          calls
              .where((call) => call.$1 == 'session.screenshot')
              .map((call) => call.$2),
          [
            {'sessionId': 'B'},
          ],
        );
        expect(find.text('截图已保存：/tmp/window-b.png'), findsOneWidget);
        expect(calls.where((call) => call.$1 == 'session.start'), isEmpty);
        expect(
          calls.where((call) => call.$1 == 'session.resume'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'a tool waits for B resume pixels and route refresh never replays its key',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final sessions = _sessions();
      final calls = <(String, Json)>[];
      final events = StreamController<Json>.broadcast();
      final resumed = Completer<Json>();
      final resumeRequested = Completer<void>();
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.list') return {'sessions': sessions};
        if (command == 'session.resume') {
          if (!resumeRequested.isCompleted) resumeRequested.complete();
          return resumed.future;
        }
        if (command == 'session.pause') {
          return {'sessionId': params['sessionId'], 'status': 'paused'};
        }
        return {};
      }, events: events.stream);
      bool isInput((String, Json) call) => const {
        'session.key',
        'session.touch',
        'session.text',
        'session.rotate',
        'session.screen',
      }.contains(call.$1);
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: const [_phone],
            theme: ConnectTokens.theme(Brightness.light),
            home: RemotePage(
              controller: controller,
              device: _phone,
              packageName: 'example.b',
              existingSession: sessions[1],
              initialAction: const RemoteControlIntent.key(3),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(resumeRequested.isCompleted, isTrue);
        expect(find.byType(RemotePage), findsOneWidget);
        expect(
          calls
              .where((call) => call.$1 == 'session.resume')
              .map((call) => call.$2),
          [
            {'sessionId': 'B'},
          ],
        );

        // 早期播放的迟到通知不能代替当前恢复操作的回执。
        events.add({
          'type': 'session.output.resumed',
          'deviceId': 'phone',
          'data': {
            'sessionId': 'B',
            'textureId': 2,
            'firstFrameDecoded': true,
            'evidence': 'media_codec.snapshot',
          },
        });
        await tester.pump();
        await tester.tapAt(const Offset(400, 300));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.pump();
        expect(calls.where(isInput), isEmpty);

        sessions[1] = {
          ...sessions[1],
          'status': 'streaming',
          'capturePaused': false,
          'firstFrameDecoded': true,
          'evidence': 'media_codec.snapshot',
        };
        resumed.complete(sessions[1]);
        await tester.pumpAndSettle();
        expect(calls.where(isInput).map((call) => call.$1), [
          'session.key',
          'session.key',
        ]);
        expect(calls.where(isInput).map((call) => call.$2), [
          {'sessionId': 'B', 'keyCode': 3, 'action': 'down'},
          {'sessionId': 'B', 'keyCode': 3, 'action': 'up'},
        ]);

        final router = GoRouter.of(tester.element(find.byType(RemotePage)));
        expect(router.routeInformationProvider.value.uri.path, '/test');
        expect(
          router.routeInformationProvider.value.uri.queryParameters,
          isEmpty,
        );
        router.refresh();
        await tester.pumpAndSettle();
        expect(calls.where(isInput), hasLength(2));
        expect(calls.where((call) => call.$1 == 'session.start'), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        if (!resumed.isCompleted) resumed.complete(sessions[1]);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );
}
