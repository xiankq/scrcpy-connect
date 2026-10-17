import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('feedback from the previous page never overlays remote content', (
    tester,
  ) async {
    final controller = createTestController(
      (command, [params = const {}]) async => command == 'session.start'
          ? {
              'sessionId': 'phone-screen',
              'textureId': 1,
              'width': 200,
              'height': 400,
            }
          : {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('上一页的操作结果'),
                      duration: Duration(seconds: 30),
                    ),
                  );
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => RemotePage(
                        controller: controller,
                        device: const {'id': 'phone'},
                      ),
                    ),
                  );
                },
                child: const Text('进入远控'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入远控'));
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RemotePage),
          matching: find.byType(SnackBar),
        ),
        findsNothing,
      );
      expect(find.text('上一页的操作结果'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
  testWidgets(
    'native first-frame receipt displays resource adjustment once even when the early frame preceded binding',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      const message = '本次画面已降低负载，已保存的画质和其他活动保持不变。';
      final controller = createTestController(
        (command, [params = const {}]) async => command == 'session.start'
            ? {
                'sessionId': 'adjusted',
                'textureId': 1,
                'width': 200,
                'height': 400,
                'resourceAdjustment': message,
              }
            : {},
        events: events.stream,
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      events.add({
        'type': 'session.frame',
        'deviceId': 'phone',
        'data': {'sessionId': 'adjusted', 'width': 200, 'height': 400},
      });
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'return drains queued key-up before pausing and retaining its session',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final semantics = tester.ensureSemantics();
      final down = Completer<Json>();
      final commands = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'session.start') {
          return {
            'sessionId': 'original',
            'textureId': 1,
            'width': 200,
            'height': 400,
          };
        }
        if (command == 'session.key' && params['action'] == 'down') {
          return down.future;
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
        await tester.pump();
        expect(
          commands.where((c) => c.$1 == 'session.pause'),
          isEmpty,
          reason:
              'The live input queue still owes the original session a key-up.',
        );
        down.complete({});
        await tester.pumpAndSettle();
        expect(
          commands
              .where((c) => c.$1 == 'session.key')
              .map((c) => c.$2['action']),
          ['down', 'up'],
        );
        expect(commands.where((c) => c.$1 == 'session.pause'), hasLength(1));
        expect(
          commands.indexWhere(
            (c) => c.$1 == 'session.key' && c.$2['action'] == 'up',
          ),
          lessThan(commands.indexWhere((c) => c.$1 == 'session.pause')),
        );
      } finally {
        if (!down.isCompleted) down.complete({});
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        semantics.dispose();
      }
    },
  );
  testWidgets('return releases held keys before pausing its original session', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final semantics = tester.ensureSemantics();
    final commands = <(String, Json)>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      commands.add((command, params));
      return command == 'session.start'
          ? {
              'sessionId': 'original',
              'textureId': 1,
              'width': 200,
              'height': 400,
            }
          : {};
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        home: RemotePage(controller: controller, device: const {'id': 'phone'}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
    await tester.pumpAndSettle();
    final keys = commands.where((c) => c.$1 == 'session.key').toList();
    expect(keys.map((c) => c.$2['action']), ['down', 'up']);
    expect(keys.every((c) => c.$2['sessionId'] == 'original'), isTrue);
    expect(
      commands.indexOf(keys.last),
      lessThan(commands.indexWhere((c) => c.$1 == 'session.pause')),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    semantics.dispose();
  });
  testWidgets(
    'an input error releases held keys while a known closed channel only clears them',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (final code in ['invalid_argument', 'disconnected']) {
        final commands = <(String, Json)>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          commands.add((command, params));
          if (command == 'session.start') {
            return {
              'sessionId': code,
              'textureId': 1,
              'width': 200,
              'height': 400,
            };
          }
          if (command == 'session.key' && params['action'] == 'down') {
            throw RequestFailure(code, '按键未完成');
          }
          return {};
        });
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            key: ValueKey(code),
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final actions = commands
            .where((c) => c.$1 == 'session.key')
            .map((c) => c.$2['action']);
        expect(actions, code == 'disconnected' ? ['down'] : ['down', 'up']);
        expect(find.text('画面已暂停'), findsOneWidget);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets(
    'focus loss releases a held physical key once before capture pause and ignores its late key-up',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final commands = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        return command == 'session.start'
            ? {
                'sessionId': 'original',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final keys = commands
          .where((c) => c.$1 == 'session.key')
          .map((c) => c.$2)
          .toList();
      expect(keys.map((p) => p['action']), ['down', 'up']);
      expect(
        keys.every((p) => p['sessionId'] == 'original' && p['keyCode'] == 20),
        isTrue,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(commands.where((c) => c.$1 == 'session.key'), hasLength(2));
      expect(
        commands.indexWhere(
          (c) => c.$1 == 'session.key' && c.$2['action'] == 'up',
        ),
        lessThan(commands.indexWhere((c) => c.$1 == 'session.pause')),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'IME submission is blocked while inactive or awaiting a resumed frame',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      final commands = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        return command == 'session.start'
            ? {
                'sessionId': 'session',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      }, events: events.stream);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
            requestKeyboard: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byType(TextField));
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(commands.where((c) => c.$1 == 'session.key'), isEmpty);
      events.add({
        'type': 'session.updated',
        'deviceId': 'phone',
        'data': {'sessionId': 'session', 'status': 'paused'},
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(commands.where((c) => c.$1 == 'session.key'), isEmpty);
      events.add({
        'type': 'session.frame',
        'deviceId': 'phone',
        'data': {'sessionId': 'session', 'width': 200, 'height': 400},
      });
      await tester.pump();
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        commands.where((c) => c.$1 == 'session.key').map((c) => c.$2['action']),
        ['down', 'up'],
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
  testWidgets(
    'a late key failure cannot pause or send an old release into a replacement session',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      final oldKey = Completer<Json>();
      final commands = <(String, Json)>[];
      var starts = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'session.start') {
          return {
            'sessionId': ++starts == 1 ? 'original' : 'replacement',
            'textureId': starts,
            'width': 200,
            'height': 400,
          };
        }
        if (command == 'session.key' && params['sessionId'] == 'original') {
          return oldKey.future;
        }
        return {};
      }, events: events.stream);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      events.add({
        'type': 'session.disconnected',
        'deviceId': 'phone',
        'data': {'sessionId': 'original', 'reason': '旧会话断开'},
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新检查'));
      await tester.pumpAndSettle();
      oldKey.completeError(const RequestFailure('not_found', '旧会话回执'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('画面已暂停'), findsNothing);
      expect(find.text('旧会话回执'), findsNothing);
      expect(commands.where((c) => c.$1 == 'session.key'), hasLength(1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        commands
            .where(
              (c) =>
                  c.$1 == 'session.key' && c.$2['sessionId'] == 'replacement',
            )
            .map((c) => c.$2['action']),
        ['down', 'up'],
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
  testWidgets(
    'a sleeping phone wakes only after explicit screen-lighting confirmation',
    (tester) async {
      final commands = <String>[];
      var starts = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        if (command == 'session.start') {
          if (++starts == 1) {
            throw const RequestFailure('device_asleep', '手机当前休眠，尚无可用画面。');
          }
          return {
            'sessionId': 'session',
            'textureId': 1,
            'width': 200,
            'height': 400,
          };
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(commands.where((c) => c != 'session.list'), ['session.start']);
      await tester.tap(find.text('唤醒手机'));
      await tester.pumpAndSettle();
      expect(find.textContaining('可能点亮被控手机的实体屏幕'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(commands.where((c) => c != 'session.list'), ['session.start']);
      await tester.tap(find.text('唤醒手机'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('唤醒手机').last);
      await tester.pumpAndSettle();
      expect(commands.where((c) => c != 'session.list').take(3), [
        'session.start',
        'devices.wake',
        'session.start',
      ]);
      expect(find.byType(Texture), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'temporary system focus loss releases input while keeping visible video live',
    (tester) async {
      final commands = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        return command == 'session.start'
            ? {
                'sessionId': 'session',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final active = await tester.startGesture(
        const Offset(400, 300),
        pointer: 101,
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'session.pause'), isEmpty);
      expect(
        commands
            .where((c) => c.$1 == 'session.touch')
            .map((c) => c.$2['action']),
        ['down', 'cancel'],
      );
      await active.up();
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(commands.where((c) => c.$1 == 'session.touch'), hasLength(2));
      expect(find.text('画面已暂停'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'session.resume'), isEmpty);
      expect(
        commands
            .where((c) => c.$1 == 'session.touch')
            .map((c) => c.$2['action']),
        ['down', 'cancel', 'down', 'up'],
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'pause releases active input once and resume blocks input until a rendered frame',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      final commands = <(String, Json)>[];
      final resume = Completer<Json>();
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'session.resume') return resume.future;
        return command == 'session.start'
            ? {
                'sessionId': 'session',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      }, events: events.stream);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final active = await tester.startGesture(
        const Offset(400, 300),
        pointer: 101,
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      final touch = commands
          .where((c) => c.$1 == 'session.touch')
          .map((c) => c.$2)
          .toList();
      expect(touch.map((p) => p['action']), ['down', 'cancel']);
      expect(touch.last['pointerId'], 101);
      expect(touch.last['x'], touch.first['x']);
      expect(commands.where((c) => c.$1 == 'session.pause'), hasLength(1));
      await active.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      events.add({
        'type': 'session.updated',
        'deviceId': 'phone',
        'data': {'sessionId': 'session', 'status': 'streaming'},
      });
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'session.touch'), hasLength(2));
      // A stale frame cannot unlock input while the current resume is pending.
      events.add({
        'type': 'session.output.resumed',
        'deviceId': 'phone',
        'data': {
          'sessionId': 'session',
          'firstFrameDecoded': true,
          'evidence': 'mdk.snapshot',
          'textureId': 1,
          'width': 200,
          'height': 400,
        },
      });
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'session.touch'), hasLength(2));
      resume.complete({
        'sessionId': 'session',
        'firstFrameDecoded': true,
        'evidence': 'mdk.snapshot',
        'textureId': 1,
      });
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(
        commands
            .where((c) => c.$1 == 'session.touch')
            .map((c) => c.$2['action']),
        ['down', 'cancel', 'down', 'up'],
      );
      expect(find.text('画面已暂停'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
