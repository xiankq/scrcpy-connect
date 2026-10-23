import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'local IME commits Chinese and emoji once when composition ends',
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
      try {
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
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
          isTrue,
          reason: 'The public keyboard request must focus its input itself.',
        );
        expect(tester.testTextInput.hasAnyClients, isTrue);
        await tester.showKeyboard(find.byType(TextField));
        const composing = TextEditingValue(
          text: '\u200B你好🙂',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 1, end: 5),
        );
        tester.testTextInput.updateEditingValue(composing);
        await tester.pump();
        expect(commands.where((c) => c.$1 == 'session.text'), isEmpty);
        tester.testTextInput.updateEditingValue(
          composing.copyWith(composing: const TextRange.collapsed(5)),
        );
        await tester.pump();
        tester.testTextInput.updateEditingValue(
          composing.copyWith(composing: TextRange.empty),
        );
        await tester.pump();
        expect(commands.where((c) => c.$1 == 'session.text').map((c) => c.$2), [
          {'sessionId': 'original', 'text': '你好🙂'},
        ]);
        expect(commands.where((c) => c.$1 == 'session.key'), isEmpty);
        // A long committed history retains only an editable suffix. Emoji
        // remain whole graphemes, and the next insertion must not replay it.
        final longText = '\u200B你好🙂${List.filled(100, '文🙂').join()}';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: longText,
            selection: TextSelection.collapsed(offset: longText.length),
          ),
        );
        await tester.pump();
        final editor = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        expect(editor.text.characters.length, 65);
        final retained = editor.text;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '$retained新',
            selection: TextSelection.collapsed(offset: retained.length + 1),
          ),
        );
        await tester.pump();
        expect(
          commands.where((c) => c.$1 == 'session.text').last.$2['text'],
          '新',
        );
        expect(commands.where((c) => c.$1 == 'session.key'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  for (final interruption in ['pause', 'replacement', 'focus loss']) {
    testWidgets('local IME discards uncommitted text after $interruption', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <(String, Json)>[];
      var starts = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'session.start' || command == 'session.resume') {
          if (command == 'session.start') starts++;
          return {
            'sessionId': 'session-$starts',
            'textureId': starts,
            'width': 200,
            'height': 400,
            'firstFrameDecoded': true,
            'evidence': 'media_codec.snapshot',
          };
        }
        return {};
      }, events: events.stream);
      try {
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
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '\u200B旧内容🙂',
            selection: TextSelection.collapsed(offset: 6),
            composing: TextRange(start: 1, end: 6),
          ),
        );
        await tester.pump();
        if (interruption == 'pause') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pumpAndSettle();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        } else if (interruption == 'replacement') {
          events.add({
            'type': 'session.disconnected',
            'data': {'sessionId': 'session-1'},
          });
          await tester.pumpAndSettle();
          await tester.tap(find.text('重新检查'));
          await tester.pumpAndSettle();
        } else {
          tester.widget<TextField>(find.byType(TextField)).focusNode!.unfocus();
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '\u200B',
        );
        expect(commands.where((c) => c.$1 == 'session.text'), isEmpty);
        await tester.showKeyboard(find.byType(TextField));
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '\u200B新🙂',
            selection: TextSelection.collapsed(offset: 4),
          ),
        );
        await tester.pump();
        expect(commands.where((c) => c.$1 == 'session.text').map((c) => c.$2), [
          {'sessionId': 'session-$starts', 'text': '新🙂'},
        ]);
        expect(commands.where((c) => c.$1 == 'session.key'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    });
  }
  for (final hanging in [false, true]) {
    testWidgets(
      'exit button remains reachable when window close ${hanging ? 'hangs' : 'fails'}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final semantics = tester.ensureSemantics();
        final pending = Completer<Json>();
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
          if (command == 'session.stop') {
            if (hanging) return pending.future;
            throw const RequestFailure('disconnected', 'window close failed');
          }
          return {};
        });
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              devices: const [
                {'id': 'phone', 'name': '测试手机'},
              ],
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openRemoteRoute(context, deviceId: 'phone'),
                    child: const Text('返回的原页面'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('返回的原页面'));
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
          await tester.pump();
          await tester.ensureVisible(find.text('关闭画面'));
          await tester.tap(find.text('关闭画面'));
          await tester.pumpAndSettle();
          expect(find.text('返回的原页面'), findsOneWidget);
          if (!hanging) {
            expect(find.textContaining('关闭窗口尚未确认'), findsOneWidget);
          }
          expect(
            find.byType(RemotePage),
            findsNothing,
            reason: 'Leaving presentation must not depend on a remote acknowledgement.',
          );
          expect(
            commands
                .where((c) => c.$1 == 'session.stop')
                .map((c) => c.$2['sessionId']),
            ['original'],
          );
          expect(commands.where((c) => c.$1 == 'session.pause'), isEmpty);
        } finally {
          if (!pending.isCompleted) pending.complete({});
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
  }
  for (final lateResume in [false, true]) {
    testWidgets(
      'returning from device B restores A focus${lateResume ? ' despite a late B resume' : ''}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final oldResume = Completer<Json>();
        final commands = <(String, Json)>[];
        final sessions = <String, Json>{};
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          commands.add((command, params));
          if (command == 'session.start') {
            final id = value(params, 'deviceId');
            return sessions[id] = {
              'sessionId': 'session-$id',
              'deviceId': id,
              'textureId': id == 'a' ? 1 : 2,
              'width': 200,
              'height': 400,
              'firstFrameDecoded': true,
              'evidence': 'media_codec.snapshot',
            };
          }
          if (command == 'session.resume') {
            if (lateResume && params['sessionId'] == 'session-b') {
              return oldResume.future;
            }
            return sessions.values.firstWhere(
              (s) => s['sessionId'] == params['sessionId'],
            );
          }
          return <String, dynamic>{};
        });
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              devices: const [
                {'id': 'a'},
                {'id': 'b'},
              ],
              home: RemotePage(
                controller: controller,
                device: const {'id': 'a'},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(controller.snapshot().focusedDeviceId, 'a');
          unawaited(
            openRemoteRoute(
              tester.element(find.byType(RemotePage)),
              deviceId: 'b',
            ),
          );
          await tester.pumpAndSettle();
          expect(controller.snapshot().focusedDeviceId, 'b');
          if (lateResume) {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            await tester.pumpAndSettle();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pumpAndSettle();
            expect(
              commands.where(
                (c) =>
                    c.$1 == 'session.resume' &&
                    c.$2['sessionId'] == 'session-b',
              ),
              hasLength(1),
            );
          }
          closePage<void>(tester.element(find.byType(RemotePage)));
          await tester.pumpAndSettle();
          expect(controller.snapshot().focusedDeviceId, 'a');
          if (lateResume) {
            oldResume.complete(sessions['b']!);
            await tester.pumpAndSettle();
            expect(controller.snapshot().focusedDeviceId, 'a');
          }
          expect(find.byType(Texture), findsOneWidget);
          expect(commands.where((c) => c.$1 == 'session.start'), hasLength(2));
          expect(tester.takeException(), isNull);
        } finally {
          if (!oldResume.isCompleted) {
            oldResume.complete(sessions['b'] ?? <String, dynamic>{});
          }
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }
  for (final terminal in ['session.disconnected', 'session.failed']) {
    testWidgets('a late resume cannot clear $terminal or accept new input', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final resumed = Completer<Json>();
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        if (command == 'session.resume') return resumed.future;
        return command == 'session.start'
            ? {
                'sessionId': 'original',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : <String, dynamic>{};
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        commands.where((command) => command == 'session.resume'),
        hasLength(1),
      );
      events.add({
        'type': terminal,
        'deviceId': 'phone',
        'data': {'sessionId': 'original', 'reason': '原会话已经结束'},
      });
      await tester.pumpAndSettle();
      expect(find.text('原会话已经结束'), findsOneWidget);
      final oldReceipt = <String, dynamic>{
        'sessionId': 'original',
        'textureId': 2,
        'firstFrameDecoded': true,
        'evidence': 'media_codec.snapshot',
      };
      resumed.complete(oldReceipt);
      await tester.pumpAndSettle();
      // The Bridge also publishes output evidence for that same late request.
      events.add({
        'type': 'session.output.resumed',
        'deviceId': 'phone',
        'data': oldReceipt,
      });
      await tester.pumpAndSettle();
      expect(find.text('原会话已经结束'), findsOneWidget);
      expect(find.text('画面已暂停'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(commands.where((command) => command == 'session.key'), isEmpty);
      expect(
        commands.where((command) => command == 'session.start'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    });
  }

  testWidgets(
    'resync drains original input releases before verifying resumed pixels',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final cleanup = Completer<Json>();
      final commands = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'session.touch' && params['action'] == 'cancel') {
          return cleanup.future;
        }
        return command == 'session.start' || command == 'session.resume'
            ? {
                'sessionId': 'original',
                'textureId': 1,
                'width': 200,
                'height': 400,
                'firstFrameDecoded': true,
                'evidence': 'media_codec.snapshot',
              }
            : {};
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
      final gesture = await tester.startGesture(
        const Offset(400, 300),
        pointer: 101,
      );
      await tester.pump();
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resynced',
        'data': {
          'devices': <Json>[],
          'settings': <String, dynamic>{},
          'shares': <Json>[],
          'sequence': 1,
          'sessions': [
            {
              'sessionId': 'original',
              'status': 'paused',
              'capturePaused': true,
              'textureId': 1,
              'width': 200,
              'height': 400,
            },
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(
        commands
            .where((c) => c.$1 == 'session.touch')
            .map((c) => c.$2['action']),
        ['down', 'cancel'],
      );
      expect(commands.where((c) => c.$1 == 'session.resume'), isEmpty);
      cleanup.complete({});
      await tester.pumpAndSettle();
      expect(
        commands.where((c) => c.$1 == 'session.key').map((c) => c.$2['action']),
        ['down', 'up'],
      );
      expect(
        commands
            .where((c) => c.$1 == 'session.key' || c.$1 == 'session.touch')
            .every((c) => c.$2['sessionId'] == 'original'),
        isTrue,
      );
      expect(
        commands.indexWhere(
          (c) => c.$1 == 'session.key' && c.$2['action'] == 'up',
        ),
        lessThan(commands.indexWhere((c) => c.$1 == 'session.resume')),
      );
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'session.key'), hasLength(2));
      expect(commands.where((c) => c.$1 == 'session.touch'), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets('covered resync waits for the original route to become visible', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = StreamController<Json>.broadcast(sync: true);
    final commands = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      commands.add(command);
      return command == 'session.start' || command == 'session.resume'
          ? {
              'sessionId': 'original',
              'textureId': 1,
              'width': 200,
              'height': 400,
              'firstFrameDecoded': true,
              'evidence': 'media_codec.snapshot',
            }
          : {};
    }, events: events.stream);
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        home: RemotePage(controller: controller, device: const {'id': 'phone'}),
      ),
    );
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(RemotePage)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
      ),
    );
    await tester.pumpAndSettle();
    final successor = controller.claimSessionView('original', visible: false);
    events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
    events.add({
      'type': 'state.resynced',
      'data': {
        'devices': <Json>[],
        'settings': <String, dynamic>{},
        'shares': <Json>[],
        'sequence': 10,
        'sessions': [
          {
            'sessionId': 'original',
            'status': 'paused',
            'capturePaused': true,
            'textureId': 1,
            'width': 200,
            'height': 400,
          },
        ],
      },
    });
    await tester.pumpAndSettle();
    expect(commands.where((c) => c == 'session.resume'), isEmpty);
    await successor.release();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(commands.where((c) => c == 'session.resume'), hasLength(1));
    expect(commands.where((c) => c == 'session.start'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await events.close();
  });

  testWidgets(
    'a launch returning after resync keeps only its identity for read-only verification',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final launched = Completer<Json>();
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return command == 'session.start' ? launched.future : {};
      }, events: events.stream);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
            initialAction: const RemoteControlIntent.key(3),
          ),
        ),
      );
      await tester.pump();
      expect(commands.where((c) => c == 'session.start'), hasLength(1));
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resynced',
        'data': {
          'devices': <Json>[],
          'settings': <String, dynamic>{},
          'shares': <Json>[],
          'sessions': <Json>[],
          'sequence': 10,
        },
      });
      launched.complete({
        'sessionId': 'late',
        'textureId': 1,
        'width': 200,
        'height': 400,
      });
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsNothing);
      expect(find.text('会话结果尚待核验，请重新检查。'), findsOneWidget);
      await tester.tap(find.text('重新检查'));
      await tester.pumpAndSettle();
      expect(commands.where((c) => c == 'state.reconcile'), hasLength(1));
      expect(
        commands.where(
          (c) => ['session.key', 'session.resume', 'session.stop'].contains(c),
        ),
        isEmpty,
      );
      expect(commands.where((c) => c == 'session.start'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'repeated resync markers fence old resume pixels and never replay a tool action',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final firstResume = Completer<Json>();
      final secondResume = Completer<Json>();
      final commands = <(String, Json)>[];
      var resumes = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'session.resume') {
          return ++resumes == 1 ? firstResume.future : secondResume.future;
        }
        return command == 'session.start'
            ? {
                'sessionId': 'original',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      }, events: events.stream);
      final snapshot = <String, dynamic>{
        'devices': <Json>[],
        'settings': <String, dynamic>{},
        'shares': <Json>[],
        'sequence': 10,
        'sessions': [
          {
            'sessionId': 'original',
            'deviceId': 'phone',
            'status': 'paused',
            'capturePaused': true,
            'textureId': 1,
            'width': 200,
            'height': 400,
          },
        ],
      };
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
            initialAction: const RemoteControlIntent.key(3),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'session.key'), hasLength(2));
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({'type': 'state.resynced', 'data': snapshot});
      await tester.pumpAndSettle();
      expect(resumes, 1);
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resynced',
        'data': {...snapshot, 'sequence': 11},
      });
      firstResume.complete({
        'sessionId': 'original',
        'textureId': 2,
        'firstFrameDecoded': true,
        'evidence': 'media_codec.snapshot',
      });
      await tester.pumpAndSettle();
      expect(resumes, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(commands.where((c) => c.$1 == 'session.key'), hasLength(2));
      secondResume.complete({
        'sessionId': 'original',
        'textureId': 3,
        'firstFrameDecoded': true,
        'evidence': 'media_codec.snapshot',
      });
      await tester.pumpAndSettle();
      events.add({
        'type': 'state.resynced',
        'data': {...snapshot, 'sequence': 11},
      });
      await tester.pumpAndSettle();
      expect(resumes, 2);
      expect(find.text('画面已暂停'), findsNothing);
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        commands
            .where((c) => c.$1 == 'session.key')
            .map((c) => c.$2['keyCode']),
        [3, 3, 22, 22],
      );
      expect(commands.where((c) => c.$1 == 'session.start'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'background resync keeps local presentation paused until visibility returns',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return command == 'session.start' || command == 'session.resume'
            ? {
                'sessionId': 'original',
                'textureId': 1,
                'width': 200,
                'height': 400,
                'firstFrameDecoded': true,
                'evidence': 'media_codec.snapshot',
              }
            : {};
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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resynced',
        'data': {
          'devices': <Json>[],
          'settings': <String, dynamic>{},
          'shares': <Json>[],
          'sequence': 10,
          'sessions': [
            {
              'sessionId': 'original',
              'status': 'streaming',
              'capturePaused': false,
              'textureId': 1,
              'width': 200,
              'height': 400,
            },
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(commands.where((c) => c == 'session.resume'), isEmpty);
      expect(commands.where((c) => c == 'session.pause'), hasLength(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(commands.where((c) => c == 'session.resume'), hasLength(1));
      expect(commands.where((c) => c == 'session.start'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'failed reconciliation stays frozen and explicit retry never starts another task',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        if (command == 'state.reconcile') {
          throw const RequestFailure('unavailable', '仍无法检查');
        }
        return command == 'session.start'
            ? {
                'sessionId': 'original',
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resync.failed',
        'data': {'reason': '快照不可用'},
      });
      await tester.pumpAndSettle();
      expect(find.text('快照不可用'), findsOneWidget);
      expect(controller.snapshot().reconciliationPending, isTrue);
      await tester.tap(find.text('重新检查'));
      await tester.pumpAndSettle();
      expect(find.text('仍无法检查'), findsOneWidget);
      expect(find.text('正在核验会话状态'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(commands.where((c) => c == 'session.key'), isEmpty);
      expect(commands.where((c) => c == 'state.reconcile'), hasLength(1));
      expect(commands.where((c) => c == 'session.start'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'resync freezes input, clears a missing session and retries only reconciliation',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return command == 'session.start'
            ? {
                'sessionId': 'original',
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      await tester.pumpAndSettle();
      expect(find.text('正在核验会话状态'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      events.add({
        'type': 'session.frame',
        'data': {'sessionId': 'original', 'textureId': 1},
      });
      await tester.pumpAndSettle();
      expect(commands.where((c) => c == 'session.key'), isEmpty);
      events.add({
        'type': 'state.resynced',
        'data': {
          'devices': <Json>[],
          'settings': <String, dynamic>{},
          'shares': <Json>[],
          'sessions': <Json>[],
          'sequence': 1,
        },
      });
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsNothing);
      expect(find.textContaining('原会话已结束'), findsOneWidget);
      expect(find.text('控制会话已结束'), findsOneWidget);
      expect(find.text('正在核验会话状态'), findsNothing);
      await tester.tap(find.text('重新检查'));
      await tester.pumpAndSettle();
      expect(commands.where((c) => c == 'state.reconcile'), hasLength(1));
      expect(commands.where((c) => c == 'session.start'), hasLength(1));
      expect(commands.where((c) => c == 'session.resume'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );

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
        TestProviderScope(
          controller: controller,
          child: MaterialApp(
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

  testWidgets('return drains queued key-up before closing its session', (
    tester,
  ) async {
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
      await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
      await tester.pump();
      await tester.ensureVisible(find.text('关闭画面'));
      await tester.tap(find.text('关闭画面'));
      await tester.pump();
      expect(
        commands.where((c) => c.$1 == 'session.stop'),
        isEmpty,
        reason:
            'The live input queue still owes the original session a key-up.',
      );
      down.complete({});
      await tester.pumpAndSettle();
      expect(
        commands.where((c) => c.$1 == 'session.key').map((c) => c.$2['action']),
        ['down', 'up'],
      );
      expect(commands.where((c) => c.$1 == 'session.stop'), hasLength(1));
      expect(
        commands.indexWhere(
          (c) => c.$1 == 'session.key' && c.$2['action'] == 'up',
        ),
        lessThan(commands.indexWhere((c) => c.$1 == 'session.stop')),
      );
    } finally {
      if (!down.isCompleted) down.complete({});
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      semantics.dispose();
    }
  });
  testWidgets('return releases held keys before closing its original session', (
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
    await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
    await tester.pump();
    await tester.ensureVisible(find.text('关闭画面'));
    await tester.tap(find.text('关闭画面'));
    await tester.pumpAndSettle();
    final keys = commands.where((c) => c.$1 == 'session.key').toList();
    expect(keys.map((c) => c.$2['action']), ['down', 'up']);
    expect(keys.every((c) => c.$2['sessionId'] == 'original'), isTrue);
    expect(
      commands.indexOf(keys.last),
      lessThan(commands.indexWhere((c) => c.$1 == 'session.stop')),
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
    'focus loss releases a held physical key once before pausing presentation and ignores its late key-up',
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
    'a sleeping phone exposes one direct idempotent wake action without modal confirmation',
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
      expect(
        commands.where((c) => c == 'session.start' || c == 'devices.wake'),
        ['session.start'],
      );
      expect(find.text('手机处于休眠状态'), findsNothing);
      await tester.tap(find.byTooltip('点亮屏幕'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        commands
            .where((c) => c == 'session.start' || c == 'devices.wake')
            .take(3),
        ['session.start', 'devices.wake', 'session.start'],
      );
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
          'evidence': 'media_codec.snapshot',
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
        'evidence': 'media_codec.snapshot',
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
