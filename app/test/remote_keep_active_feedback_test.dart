import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/application/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _device = <String, dynamic>{
  'id': 'phone',
  'name': '测试手机',
  'status': 'connected',
};
const _session = <String, dynamic>{
  'deviceId': 'phone',
  'sessionId': 'current',
  'textureId': 1,
  'width': 400,
  'height': 800,
  'status': 'streaming',
  'captureGeneration': 2,
  'rendererGeneration': 3,
};
Json _failure(String reason) => {'code': 'keep_active_ended', 'reason': reason};
Json _update(
  Object? error, {
  String device = 'phone',
  String session = 'current',
  int capture = 2,
}) => {
  'type': 'session.updated',
  'deviceId': device,
  'data': {
    ..._session,
    'sessionId': session,
    'deviceId': device,
    'captureGeneration': capture,
    'keepActiveError': error,
  },
};

Future<void> _mount(
  WidgetTester tester,
  AppController controller, {
  bool pushed = false,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      devices: const [_device],
      theme: ConnectTokens.theme(Brightness.light),
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openRemoteRoute(context, deviceId: 'phone'),
                  child: const Text('工作台打开'),
                ),
              ),
            )
          : RemotePage(controller: controller, device: _device),
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.text('工作台打开'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'keep-active startup failure is a deduplicated notice while the picture stays controllable',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'session.start') {
          return {..._session, 'keepActiveError': _failure('保活服务启动失败')};
        }
        return {};
      }, events: events.stream);
      controller.settings = {
        'deviceSettings': {
          'phone': {'stayAwake': true},
        },
      };
      try {
        await _mount(tester, controller);
        expect(find.text('保持唤醒尚未确认：保活服务启动失败'), findsOneWidget);
        final dynamic state = tester.state(find.byType(RemotePage));
        expect(state.presentation.error, isNull);
        expect(state.canSendInput, isTrue);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(calls.where((call) => call.$1 == 'session.key'), hasLength(2));
        expect(
          calls
              .singleWhere((call) => call.$1 == 'session.start')
              .$2['keepActive'],
          isTrue,
        );
        expect(
          jsonObject(
            jsonObject(controller.settings['deviceSettings'])['phone'],
          )['stayAwake'],
          isTrue,
        );
        events.add(_update(_failure('保活服务启动失败')));
        events.add(_update(_failure('保活服务启动失败')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('保持唤醒尚未确认：保活服务启动失败'), findsNothing);
        events.add(_update(null));
        await tester.pumpAndSettle();
        events.add(_update(_failure('保活服务启动失败')));
        await tester.pumpAndSettle();
        expect(find.text('保持唤醒尚未确认：保活服务启动失败'), findsOneWidget);
        expect(state.presentation.error, isNull);
        expect(state.canSendInput, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );

  testWidgets(
    'keep-active notices wait through background and occlusion and fence other bindings',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'session.start') {
          return {..._session, 'keepActiveError': null};
        }
        if (command == 'session.resume') {
          return {
            ..._session,
            'firstFrameDecoded': true,
            'evidence': 'media_codec.decodedFrame',
          };
        }
        return {};
      }, events: events.stream);
      try {
        await _mount(tester, controller);
        events.add(_update(_failure('错误设备'), device: 'other'));
        events.add(_update(_failure('错误会话'), session: 'other'));
        events.add(_update(_failure('旧捕获'), capture: 1));
        await tester.pumpAndSettle();
        expect(find.textContaining('保持唤醒尚未确认'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        events.add(_update(_failure('后台保活结束')));
        await tester.pumpAndSettle();
        expect(find.textContaining('后台保活结束'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('保持唤醒尚未确认：后台保活结束'), findsOneWidget);
        events.add(_update(null));
        await tester.pumpAndSettle();
        // 已可见的短暂提醒可自然结束。
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.textContaining('后台保活结束'), findsNothing);
        final context = tester.element(find.byType(RemotePage));
        final covered = Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('覆盖页'))),
        );
        await tester.pumpAndSettle();
        events.add(_update(_failure('覆盖时保活结束')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('覆盖时保活结束', skipOffstage: false),
          findsNothing,
        );
        Navigator.of(tester.element(find.text('覆盖页'))).pop();
        await covered;
        await tester.pumpAndSettle();
        expect(find.text('保持唤醒尚未确认：覆盖时保活结束'), findsOneWidget);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );

  testWidgets(
    'success cancels unshown keep-active notices without replacing another notification',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'session.start') {
          return {
            ..._session,
            'resourceAdjustment': '真实资源提示',
            'keepActiveError': null,
          };
        }
        if (command == 'session.resume') {
          return {
            ..._session,
            'firstFrameDecoded': true,
            'evidence': 'media_codec.decodedFrame',
          };
        }
        return {};
      }, events: events.stream);
      try {
        await _mount(tester, controller);
        expect(find.text('真实资源提示'), findsOneWidget);
        events.add(_update(_failure('排队中恢复')));
        await tester.pumpAndSettle();
        expect(find.textContaining('排队中恢复'), findsNothing);
        events.add(_update(null));
        await tester.pumpAndSettle();
        expect(find.text('真实资源提示'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.textContaining('排队中恢复'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        events.add(_update(_failure('后台已恢复')));
        await tester.pumpAndSettle();
        events.add(_update(null));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('后台已恢复'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );

  testWidgets(
    'a disposed page cannot surface a late startup keep-active error',
    (tester) async {
      final started = Completer<Json>();
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        if (command == 'session.start') return started.future;
        return {};
      });
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: RemotePage(controller: controller, device: _device),
          ),
        );
        await tester.pump();
        expect(calls, contains('session.start'));
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('其他设备'))),
        );
        started.complete({..._session, 'keepActiveError': _failure('旧页面迟到失败')});
        await tester.pumpAndSettle();
        expect(find.text('其他设备'), findsOneWidget);
        expect(find.textContaining('旧页面迟到失败'), findsNothing);
        expect(calls.where((call) => call == 'session.stop'), hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        if (!started.isCompleted) started.complete(_session);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  for (final pixels in [true, false]) {
    testWidgets(
      'closed window reports unconfirmed keep-active cleanup on the workspace, pixels=$pixels',
      (tester) async {
        final stopped = Completer<Json>();
        final calls = <String>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          calls.add(command);
          if (command == 'session.start') {
            return {..._session, if (!pixels) 'textureId': null};
          }
          if (command == 'session.stop') return stopped.future;
          return {};
        });
        try {
          await _mount(tester, controller, pushed: true);
          final dynamic state = tester.state(find.byType(RemotePage));
          unawaited(state.leave() as Future<void>);
          await tester.pumpAndSettle();
          expect(find.byType(RemotePage), findsNothing);
          expect(find.text('工作台打开'), findsOneWidget);
          expect(calls.where((call) => call == 'session.stop'), hasLength(1));
          stopped.complete({
            'sessionId': 'current',
            'status': 'stopped',
            'keepActiveCleanup': {
              'status': 'cleanup_unconfirmed',
              'cleanupConfirmed': false,
              'leaseId': 8,
              'pid': 123,
              'connectionId': 'one',
              'error': {'code': 'timeout', 'reason': '释放回执超时'},
            },
          });
          await tester.pumpAndSettle();
          expect(find.text('窗口已关闭，保持唤醒服务释放尚未确认：释放回执超时'), findsOneWidget);
          expect(find.textContaining('关闭窗口尚未确认'), findsNothing);
          expect(find.byType(RemotePage), findsNothing);
          expect(calls.where((call) => call == 'session.stop'), hasLength(1));
        } finally {
          if (!stopped.isCompleted) stopped.complete({});
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }
}
