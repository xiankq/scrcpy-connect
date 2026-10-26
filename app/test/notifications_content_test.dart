import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/models/app_state.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/stores/system_notification_coordinator.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

class _DeniedReminderSink extends NoopSystemNotificationSink {
  var requests = 0;
  @override
  Future<SystemNotificationStatus> status() async =>
      const SystemNotificationStatus(
        supported: true,
        permissionGranted: false,
        canRequest: true,
        reason: '系统通知权限未获允许',
      );
  @override
  Future<SystemNotificationStatus> requestPermission() {
    requests++;
    return status();
  }
}

void main() {
  for (final code in ['authentication_required', 'stale_notification']) {
    testWidgets(
      'notification opening handles structured $code without replay',
      (tester) async {
        const device = {'id': 'phone', 'name': '来源手机', 'status': 'connected'};
        final commands = <(String, Json)>[];
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          commands.add((command, params));
          if (command == 'notifications.list') {
            return {
              'status': 'available',
              'notifications': [
                {
                  'id': 'locked',
                  'title': '原通知',
                  'appName': '消息',
                  'canOpen': true,
                },
              ],
            };
          }
          if (command == 'notifications.open') {
            throw RequestFailure(code, '请核对手机上的通知');
          }
          return {};
        });
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: NotificationsPage(controller: controller, device: device),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('原通知'));
        await tester.pumpAndSettle();
        expect(
          commands.where((call) => call.$1 == 'notifications.open').single.$2,
          {'deviceId': 'phone', 'notificationId': 'locked'},
        );
        final sessions = commands.where((call) => call.$1 == 'session.start');
        if (code == 'authentication_required') {
          expect(sessions.single.$2['deviceId'], 'phone');
          expect(sessions.single.$2['packageName'], isNull);
        } else {
          expect(sessions, isEmpty);
          expect(find.text('请核对手机上的通知'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'confirmed bulk clearing only dismisses remote items and retains unknown results',
    (tester) async {
      const device = {'id': 'phone', 'name': '手机', 'status': 'connected'};
      final commands = <(String, Json)>[];
      final items = <Json>[
        {'id': 'clear', 'appName': '消息应用', 'title': '可清通知', 'canDismiss': true},
        {
          'id': 'pending',
          'appName': '消息应用',
          'title': '等待手机确认',
          'canDismiss': true,
        },
        {
          'id': 'ongoing',
          'appName': '音乐应用',
          'title': '常驻播放',
          'canDismiss': false,
        },
      ];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'notifications.list') {
          return {
            'status': 'available',
            'live': true,
            'notifications': List<Json>.of(items),
          };
        }
        if (command == 'notifications.dismiss') {
          if (params['notificationId'] == 'clear') {
            items.removeWhere((item) => item['id'] == 'clear');
            return {'dismissed': true, 'markedRead': false};
          }
          return {
            'acceptedBySystem': true,
            'dismissed': false,
            'markedRead': false,
          };
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('仅在本机隐藏'), findsNothing);
      expect(find.text('进入手机原应用'), findsNothing);
      expect(find.byType(ContentPanel), findsNWidgets(3));
      expect(
        tester.getSize(find.byKey(const ValueKey('notification-clear'))).height,
        DesignTokens.componentNotificationCardHeight,
      );
      await tester.tap(find.byTooltip('清除全部通知'));
      await tester.pumpAndSettle();
      expect(
        commands.where((call) => call.$1 == 'notifications.dismiss'),
        isEmpty,
      );
      expect(find.textContaining('手机 当前可清除的 2 条通知'), findsOneWidget);
      await tester.tap(find.text('清除通知').last);
      await tester.pumpAndSettle();
      expect(
        commands
            .where((call) => call.$1 == 'notifications.dismiss')
            .map((call) => call.$2['notificationId']),
        ['clear', 'pending'],
      );
      expect(find.text('可清通知'), findsNothing);
      expect(find.text('等待手机确认'), findsOneWidget);
      expect(find.text('常驻播放'), findsOneWidget);
      expect(find.text('手机系统将此项标为不可清除，请在原应用中处理。'), findsOneWidget);
      expect(find.byType(ContentPanel), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'notification page requests reminders only on explicit action and preserves call intent after denial',
    (tester) async {
      final sink = _DeniedReminderSink();
      final writes = <Json>[];
      final dependencies = AppDependencies(
        initialize: false,
        events: const Stream.empty(),
        initialState: AppState(
          loading: false,
          settings: {'notificationAlerts': false, 'callAlerts': false},
        ),
        request: (command, [params = const {}]) async {
          if (command == 'settings.update') writes.add(params);
          return command == 'notifications.list'
              ? {'status': 'available', 'notifications': <Json>[]}
              : {};
        },
      );
      late AppController controller;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDependenciesProvider.overrideWithValue(dependencies),
            systemNotificationSinkProvider.overrideWithValue(sink),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              controller = ref.watch(appControllerProvider.notifier);
              return MaterialApp(
                theme: ConnectTokens.theme(Brightness.light),
                home: NotificationsPage(
                  controller: controller,
                  device: const {'id': 'phone', 'name': '手机'},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sink.requests, 0);
      expect(writes, isEmpty);
      expect(find.text('没有当前通知'), findsOneWidget);
      await tester.tap(find.text('开启系统提醒'));
      await tester.pumpAndSettle();
      expect(sink.requests, 1);
      expect(writes, [
        {'notificationAlerts': true},
      ]);
      expect(controller.snapshot().settings['callAlerts'], isFalse);
      expect(find.textContaining('系统通知权限未获允许'), findsOneWidget);
      expect(find.text('没有当前通知'), findsOneWidget);
      expect(find.text('开启系统提醒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'card taps use the exact remote notification and do not duplicate a pending open',
    (tester) async {
      const device = {
        'id': 'source-phone',
        'name': '手机',
        'status': 'connected',
      };
      final commands = <(String, Json)>[];
      final opening = Completer<Json>();
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'notifications.list') {
          return {
            'status': 'available',
            'notifications': [
              {
                'id': 'original-notification',
                'packageName': 'dev.target.messenger',
                'appName': '真实消息应用',
                'userId': 0,
                'title': '点击原通知',
                'canOpen': true,
              },
            ],
          };
        }
        if (command == 'notifications.open') return opening.future;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('真实消息应用'), findsOneWidget);
      expect(find.text('dev.target.messenger'), findsNothing);
      expect(commands.where((call) => call.$1 == 'apps.icon').single.$2, {
        'deviceId': 'source-phone',
        'packageName': 'dev.target.messenger',
      });
      await tester.tap(find.text('点击原通知'));
      await tester.pump();
      await tester.tap(find.text('点击原通知'));
      await tester.pump();
      expect(
        commands.where((call) => call.$1 == 'notifications.open').single.$2,
        {'deviceId': 'source-phone', 'notificationId': 'original-notification'},
      );
      opening.completeError(StateError('notification expired'));
      await tester.pumpAndSettle();
      expect(find.textContaining('notification expired'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'clearing a preceding card preserves a pending open across status offsets',
    (tester) async {
      const device = {'id': 'phone', 'name': '手机', 'status': 'connected'};
      var firstPresent = true;
      var opens = 0;
      final opening = Completer<Json>();
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.list') {
          return {
            'status': firstPresent ? 'limited' : 'available',
            'reason': firstPresent ? '部分通知受限' : '',
            'live': true,
            'notifications': [
              if (firstPresent)
                {
                  'id': 'first',
                  'appName': '消息应用',
                  'title': '前一条',
                  'canDismiss': true,
                },
              {
                'id': 'second',
                'appName': '消息应用',
                'title': '正在打开的原通知',
                'canOpen': true,
              },
            ],
          };
        }
        if (command == 'notifications.dismiss') {
          firstPresent = false;
          return {'dismissed': true};
        }
        if (command == 'notifications.open') {
          opens++;
          return opening.future;
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('正在打开的原通知'));
      await tester.pump();
      await tester.tap(find.byTooltip('清除通知'));
      await tester.pumpAndSettle();
      expect(find.text('前一条'), findsNothing);
      expect(find.text('部分通知受限'), findsNothing);
      await tester.tap(find.text('正在打开的原通知'));
      await tester.pump();
      expect(opens, 1);
      opening.completeError(StateError('notification expired'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
