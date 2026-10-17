import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/pages/session_tools/session_tools_page.dart';
import 'package:scrcpy_connect/pages/sessions/sessions_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

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
  testWidgets('closing B refreshes the session workspace and preserves A', (
    tester,
  ) async {
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
          home: SessionsPage(controller: controller, device: _phone),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('窗口 A'), findsOneWidget);
      expect(find.text('窗口 B'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close-session:B')));
      await tester.pumpAndSettle();

      expect(
        calls.where((call) => call.$1 == 'session.stop').map((call) => call.$2),
        [
          {'sessionId': 'B', 'keepTask': true},
        ],
      );
      expect(
        calls.where((call) => call.$1 == 'session.list').length,
        greaterThan(1),
      );
      expect(sessions.map((item) => item['sessionId']), ['A']);
      expect(find.text('窗口 A'), findsOneWidget);
      expect(find.text('窗口 B'), findsNothing);
      expect(calls.where((call) => call.$1 == 'session.pause'), isEmpty);
      expect(calls.where((call) => call.$1 == 'session.resume'), isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets(
    'selecting B in tools captures that session without a device fallback',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.list') return {'sessions': _sessions()};
        if (command == 'session.screenshot') return {'message': '窗口 B 截图已保存'};
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: const [_phone],
            theme: ConnectTokens.theme(Brightness.light),
            home: SessionToolsPage(controller: controller, device: _phone),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('截取当前画面'), findsNothing);
        await tester.tap(find.text('窗口 B'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('截取当前画面'));
        await tester.pumpAndSettle();

        expect(
          calls
              .where((call) => call.$1 == 'session.screenshot')
              .map((call) => call.$2),
          [
            {'sessionId': 'B'},
          ],
        );
        expect(find.text('窗口 B 截图已保存'), findsOneWidget);
        expect(calls.where((call) => call.$1 == 'session.start'), isEmpty);
        expect(calls.where((call) => call.$1 == 'session.resume'), isEmpty);
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
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.list') return {'sessions': sessions};
        if (command == 'session.resume') return resumed.future;
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
            home: SessionToolsPage(
              controller: controller,
              device: _phone,
              sessionId: 'B',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('主屏幕'), 250);
        await tester.tap(find.text('主屏幕'));
        for (var attempt = 0; attempt < 20; attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (calls.any((call) => call.$1 == 'session.resume')) break;
        }
        expect(find.byType(RemotePage), findsOneWidget);
        expect(
          calls
              .where((call) => call.$1 == 'session.resume')
              .map((call) => call.$2),
          [
            {'sessionId': 'B'},
          ],
        );

        // A late notification from earlier playback must not substitute for the
        // current resume operation's receipt.
        events.add({
          'type': 'session.output.resumed',
          'deviceId': 'phone',
          'data': {
            'sessionId': 'B',
            'textureId': 2,
            'firstFrameDecoded': true,
            'evidence': 'mdk.snapshot',
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
          'evidence': 'mdk.snapshot',
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
        expect(
          router.routeInformationProvider.value.uri.path,
          '/devices/phone/sessions/B',
        );
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
