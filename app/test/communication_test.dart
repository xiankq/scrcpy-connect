import 'package:scrcpy_connect/models/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
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
        final controller = createTestController((command, params) async {
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
        await tester.ensureVisible(find.text('在手机画面接听'));
        await tester.tap(find.text('在手机画面接听'));
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
    'a limited partial notification snapshot preserves items and disables unavailable actions',
    (tester) async {
      final commands = <String>[];
      final controller = createTestController((command, params) async {
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
      expect(find.text('此通知的原始动作已不可用，请在手机原应用中处理。'), findsOneWidget);
      await tester.ensureVisible(find.text('当前可用通知'));
      await tester.tap(find.text('当前可用通知'));
      await tester.pumpAndSettle();
      expect(commands, isNot(contains('notifications.open')));
      expect(commands, isNot(contains('session.start')));
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
          final controller = createTestController((command, params) async {
            commands.add((command, params));
            if (command == 'observation.start') {
              requested = true;
              return starting.future;
            }
            if (command == 'calls.openPhoneApp') {
              return {
                'target': 'phoneApp',
                'acceptedBySystem': true,
                'uiVisible': null,
                'callControlled': false,
              };
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
          if (!notifications) {
            await tester.scrollUntilVisible(
              find.text('打开手机电话界面'),
              -200,
              scrollable: find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.tap(find.text('打开手机电话界面'));
            await tester.pumpAndSettle();
            expect(
              commands
                  .where((entry) => entry.$1 == 'calls.openPhoneApp')
                  .single
                  .$2,
              {'deviceId': 'phone'},
            );
            expect(
              commands.where((entry) => entry.$1 == 'observation.start'),
              hasLength(1),
            );
            expect(
              commands.where(
                (entry) =>
                    entry.$1 == 'calls.action' || entry.$1 == 'calls.open',
              ),
              isEmpty,
            );
          }
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await events.close();
        },
      );
    }
  }

  testWidgets(
    'a live batched incoming event presents its device source without answering',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final events = StreamController<Json>.broadcast();
      final commands = <String>[];
      final controller = createTestController((command, params) async {
        commands.add(command);
        if (command == 'device.info') return device;
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
      expect(find.textContaining('来源手机 ·'), findsOneWidget);
      expect(find.byType(CallsPage), findsNothing);
      await tester.tap(find.text('查看电话'));
      await tester.pumpAndSettle();
      expect(find.byType(CallsPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('来源手机 ·'), findsNothing);
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
      expect(find.textContaining('来源手机 ·'), findsNothing);
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
        final controller = createTestController((command, params) async {
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
        expect(find.textContaining('来源手机 ·'), findsNothing);
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
          expect(find.textContaining('来源手机 ·'), findsNothing);
          events.add(incoming);
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('来源手机 ·'), findsOneWidget);
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
        (command, params) async => command == 'devices.list'
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
      expect(find.textContaining('来源手机 ·'), findsNothing);
      events.add({
        ...incoming,
        'data': {'live': true, 'id': 'fresh-call', 'state': 'ringing'},
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('来源手机 ·'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
