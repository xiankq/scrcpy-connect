import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/reply/devices_workspace_notifications_reply_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const device = {'id': 'phone', 'name': '来源手机', 'status': 'connected'};

void main() {
  for (final accepted in [true, false]) {
    testWidgets(
      'current system call opens remote view only after system UI acceptance: $accepted',
      (tester) async {
        final commands = <(String, Json)>[];
        final opening = Completer<Json>();
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          commands.add((command, params));
          if (command == 'calls.open') return opening.future;
          if (command == 'calls.list') {
            return {
              'status': 'limited',
              'live': true,
              'canOpenSystemCallUi': true,
              'calls': [
                {
                  'id': 'aggregate-observation',
                  'state': 'ringing',
                  'aggregate': true,
                },
              ],
            };
          }
          return {};
        });
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: CallsPage(controller: controller, device: device),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('打开系统通话界面'));
        await tester.tap(find.text('打开系统通话界面'));
        await tester.pump();
        expect(commands.where((entry) => entry.$1 == 'calls.open').single.$2, {
          'deviceId': 'phone',
        });
        expect(commands.where((entry) => entry.$1 == 'session.start'), isEmpty);
        if (accepted) {
          opening.complete({
            'target': 'currentSystemCall',
            'acceptedBySystem': true,
            'uiVisible': null,
            'callControlled': false,
          });
        } else {
          opening.completeError(Exception('设备拒绝打开系统通话界面'));
        }
        await tester.pumpAndSettle();
        expect(
          commands.where((entry) => entry.$1 == 'session.start'),
          accepted ? isNotEmpty : isEmpty,
        );
        expect(commands.where((entry) => entry.$1 == 'calls.action'), isEmpty);
        if (!accepted) {
          expect(find.textContaining('设备拒绝打开系统通话界面'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'a limited partial notification snapshot preserves its items and fallback opens no original action',
    (tester) async {
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return command == 'notifications.list'
            ? {
                'status': 'limited',
                'live': true,
                'truncated': true,
                'reason': '部分通知未同步，请进入手机查看。',
                'notifications': [
                  {
                    'id': 'notification',
                    'appName': '消息',
                    'title': '当前可用通知',
                    'body': '内容',
                    'canOpen': false,
                  },
                ],
              }
            : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前可用通知'), findsOneWidget);
      expect(find.text('部分通知未同步，请进入手机查看。'), findsOneWidget);
      expect(find.text('此通知没有可接续的原始动作；点击将仅打开手机界面。'), findsOneWidget);
      await tester.ensureVisible(find.text('当前可用通知'));
      await tester.tap(find.text('当前可用通知'));
      await tester.pumpAndSettle();
      expect(commands, isNot(contains('notifications.open')));
      expect(commands, contains('session.start'));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final notifications in [true, false]) {
    for (final initialStatus in ['unknown', 'stopped']) {
      testWidgets(
        '${notifications ? 'notifications' : 'calls'} $initialStatus requires one explicit start and stays unverified while starting',
        (tester) async {
          final commands = <(String, Json)>[];
          final starting = Completer<Json>();
          final events = StreamController<Json>.broadcast();
          var requested = false;
          final controller = createTestController((
            command, [
            params = const {},
          ]) async {
            commands.add((command, params));
            if (command == 'observation.start') {
              requested = true;
              return starting.future;
            }
            return {
              'status': requested ? 'unknown' : initialStatus,
              'live': false,
              'reason': '尚未获得实时状态',
              'notifications': <Json>[],
              'calls': <Json>[],
            };
          }, events: events.stream);
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              theme: ConnectTokens.theme(Brightness.light),
              home: notifications
                  ? NotificationsPage(controller: controller, device: device)
                  : CallsPage(controller: controller, device: device),
            ),
          );
          await tester.pumpAndSettle();
          final unknownTitle = notifications ? '通知状态尚未核验' : '通话状态尚未核验';
          final stoppedTitle = notifications ? '通知观察已停止' : '来电观察已停止';
          expect(
            find.text(initialStatus == 'stopped' ? stoppedTitle : unknownTitle),
            findsOneWidget,
          );
          expect(
            commands.where((entry) => entry.$1 == 'observation.start'),
            isEmpty,
          );
          expect(
            commands.every((entry) => !entry.$2.containsKey('allowStart')),
            isTrue,
          );
          final listCommand = notifications
              ? 'notifications.list'
              : 'calls.list';
          final reads = commands
              .where((entry) => entry.$1 == listCommand)
              .length;
          events.add({
            'type': 'observation.changed',
            'deviceId': 'phone',
            'data': {'phase': initialStatus},
          });
          await tester.pumpAndSettle();
          expect(
            commands.where((entry) => entry.$1 == listCommand),
            hasLength(reads + 1),
          );
          expect(
            commands.where((entry) => entry.$1 == 'observation.start'),
            isEmpty,
          );
          final button = initialStatus == 'stopped'
              ? '启用通知与来电观察'
              : notifications
              ? '重新核验通知'
              : '重新核验通话';
          if (notifications) {
            await tester.ensureVisible(find.text(button));
          } else {
            await tester.scrollUntilVisible(
              find.text(button),
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
          }
          await tester.tap(find.text(button));
          await tester.tap(find.text(button));
          await tester.pump();
          final starts = commands.where(
            (entry) => entry.$1 == 'observation.start',
          );
          expect(starts, hasLength(1));
          expect(starts.single.$2, {'deviceId': 'phone'});
          starting.complete({'phase': 'starting', 'wanted': true});
          await tester.pumpAndSettle();
          expect(find.text(unknownTitle), findsOneWidget);
          expect(find.text('没有当前通知'), findsNothing);
          expect(find.text('没有可控制的当前通话'), findsNothing);
          expect(
            commands.last.$1,
            notifications ? 'notifications.list' : 'calls.list',
          );
          expect(
            commands.every((entry) => !entry.$2.containsKey('allowStart')),
            isTrue,
          );
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await events.close();
        },
      );
    }
  }

  testWidgets(
    'system acceptance preserves the reply draft without claiming delivery or permitting resend',
    (tester) async {
      var submissions = 0;
      const message = '原应用动作已交给系统；未确认应用或消息服务送达，不会自动重发。';
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.reply') submissions++;
        return {
          'status': 'acceptedBySystem',
          'acceptedBySystem': true,
          'delivered': null,
          'message': message,
        };
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationReplyPage(
            controller: controller,
            device: device,
            notification: const {'id': 'notification', 'title': '消息'},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '保留的真实草稿');
      await tester.ensureVisible(find.text('发送回复'));
      await tester.tap(find.text('发送回复'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留的真实草稿',
      );
      expect(find.text('发送回复'), findsNothing);
      expect(find.text('回复已由手机确认提交'), findsNothing);
      expect(submissions, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'aggregate call state remains limited and exposes no unsafe global actions',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => {
          'status': 'limited',
          'live': true,
          'audioStatus': 'unknown',
          'reason': '具体通话安全定位尚未完成，请在手机原电话应用操作。',
          'calls': [
            {
              'id': 'call',
              'state': 'ringing',
              'name': '当前系统通话',
              'canAnswer': false,
              'canReject': false,
              'canHangup': false,
            },
          ],
        },
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: CallsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('通话控制：受限'), findsOneWidget);
      expect(find.text('具体通话安全定位尚未完成，请在手机原电话应用操作。'), findsOneWidget);
      expect(find.text('接听'), findsNothing);
      expect(find.text('拒接'), findsNothing);
      expect(find.text('挂断'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'a live batched incoming event presents its device source without answering',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return command == 'devices.list'
            ? {
                'devices': [device],
              }
            : {};
      }, events: events.stream);
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      events.add({
        'type': 'calls.incoming',
        'deviceId': 'phone',
        'data': {
          'live': true,
          'calls': [
            {'id': 'call', 'name': '当前系统通话', 'state': 'ringing'},
          ],
        },
      });
      events.add({
        'type': 'observation.changed',
        'deviceId': 'phone',
        'data': {'phase': 'observing'},
      });
      events.add({'type': 'settings.changed', 'data': <String, dynamic>{}});
      await tester.pumpAndSettle();
      expect(find.text('来源手机 有来电'), findsOneWidget);
      expect(find.text('查看来电与声音'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('来源手机 有来电'), findsNothing);
      events.add({
        'type': 'calls.incoming',
        'deviceId': 'phone',
        'data': {'live': true, 'id': 'call', 'state': 'ringing'},
      });
      events.add({
        'type': 'call.incoming',
        'deviceId': 'unmatched-phone',
        'data': {'live': true, 'id': 'other-call', 'state': 'ringing'},
      });
      events.add({
        'type': 'calls.incoming',
        'deviceId': 'phone',
        'data': {'live': false, 'id': 'stale-call', 'state': 'ringing'},
      });
      await tester.pumpAndSettle();
      expect(find.text('来源手机 有来电'), findsNothing);
      expect(commands, isNot(contains('calls.action')));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
  for (final freshBeforeFrame in [false, true]) {
    testWidgets(
      'incoming presentation queued before backgrounding requires a fresh foreground event beforeFrame=$freshBeforeFrame',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final events = StreamController<Json>.broadcast();
        final commands = <String>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          commands.add(command);
          return command == 'devices.list'
              ? {
                  'devices': [device],
                }
              : {};
        }, events: events.stream);
        await controller.initialize();
        await tester.pumpWidget(
          TestProviderScope(controller: controller, child: const ConnectApp()),
        );
        await tester.pumpAndSettle();
        const incoming = {
          'type': 'calls.incoming',
          'deviceId': 'phone',
          'data': {
            'live': true,
            'calls': [
              {'id': 'queued-call', 'name': '当前来电', 'state': 'ringing'},
            ],
          },
        };
        events.add(incoming);
        await tester.idle();
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(find.text('来源手机 有来电'), findsNothing);
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        if (freshBeforeFrame) {
          events.add(incoming);
          await tester.idle();
        }
        await tester.pumpAndSettle();
        if (!freshBeforeFrame) {
          expect(find.text('来源手机 有来电'), findsNothing);
          events.add(incoming);
          await tester.pumpAndSettle();
        }
        expect(find.text('来源手机 有来电'), findsOneWidget);
        expect(commands, isNot(contains('calls.action')));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      },
    );
  }

  testWidgets(
    'disposed incoming subscription drops queued callbacks and remount does not replay its snapshot',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      final controller = createTestController(
        (command, [params = const {}]) async => command == 'devices.list'
            ? {
                'devices': [device],
              }
            : {},
        events: events.stream,
      );
      await controller.initialize();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      const incoming = {
        'type': 'calls.incoming',
        'deviceId': 'phone',
        'data': {'live': true, 'id': 'disposed-call', 'state': 'ringing'},
      };
      events.add(incoming);
      await tester.idle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      events.add(incoming);
      await tester.idle();
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('来源手机 有来电'), findsNothing);
      events.add({
        ...incoming,
        'data': {'live': true, 'id': 'fresh-call', 'state': 'ringing'},
      });
      await tester.pumpAndSettle();
      expect(find.text('来源手机 有来电'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
