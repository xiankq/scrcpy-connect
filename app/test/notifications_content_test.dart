import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

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
    'empty group summaries do not obscure current actionable content',
    (tester) async {
      const device = {'id': 'phone', 'name': '手机', 'status': 'connected'};
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.list') {
          return {
            'status': 'available',
            'notifications': [
              {'id': 'summary', 'appName': '空白汇总', 'groupSummary': true},
              {
                'id': 'message',
                'appName': '消息应用',
                'title': '当前消息',
                'body': '仍然显示原内容',
                'canReply': true,
              },
              {
                'id': 'useful-summary',
                'appName': '有内容的汇总',
                'groupSummary': true,
                'body': '三条未读消息',
              },
              {'id': 'private', 'appName': '隐藏正文的应用'},
            ],
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
      expect(find.text('空白汇总'), findsNothing);
      expect(find.text('当前消息'), findsOneWidget);
      expect(find.text('仍然显示原内容'), findsOneWidget);
      expect(find.text('快捷回复'), findsNothing);
      await tester.scrollUntilVisible(find.text('三条未读消息'), 200);
      expect(find.text('三条未读消息'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('此通知未提供预览内容'), 200);
      expect(find.text('隐藏正文的应用'), findsOneWidget);
      expect(find.text('此通知未提供预览内容'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'all read clears only dismissible remote items and retains unknown results',
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
      await tester.tap(find.byTooltip('全部已读'));
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
    'single read clears on the phone without executing the card action',
    (tester) async {
      const device = {'id': 'phone', 'name': '手机', 'status': 'connected'};
      final commands = <(String, Json)>[];
      var present = true;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        if (command == 'notifications.list') {
          return {
            'status': 'available',
            'live': true,
            'notifications': [
              if (present)
                {
                  'id': 'message',
                  'appName': '消息应用',
                  'title': '收到消息',
                  'canDismiss': true,
                },
            ],
          };
        }
        if (command == 'notifications.dismiss') {
          present = false;
          return {'dismissed': true, 'markedRead': false};
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
      expect(
        tester
            .getSize(find.byKey(const ValueKey('notification-message')))
            .height,
        DesignTokens.componentNotificationCardHeight,
      );
      await tester.tap(find.byTooltip('已读（清除）'));
      await tester.pumpAndSettle();
      expect(
        commands.where((call) => call.$1 == 'notifications.dismiss').single.$2,
        {'deviceId': 'phone', 'notificationId': 'message'},
      );
      expect(commands.any((call) => call.$1 == 'notifications.open'), isFalse);
      expect(find.text('收到消息'), findsNothing);
      expect(find.text('没有当前通知'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
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
      await tester.tap(find.byTooltip('已读（清除）'));
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
