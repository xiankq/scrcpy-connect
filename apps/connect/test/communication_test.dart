import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/pages/calls/calls_page.dart';
import 'package:scrcpy_connect/pages/notification_reply/notification_reply_page.dart';
import 'package:scrcpy_connect/pages/notifications/notifications_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const device = {'id': 'phone', 'name': '来源手机', 'status': 'connected'};

void main() {
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
      await tester.ensureVisible(find.text('在手机上查看'));
      await tester.tap(find.text('在手机上查看'));
      await tester.pumpAndSettle();
      expect(commands, isNot(contains('notifications.open')));
      expect(commands, contains('session.start'));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'unknown notification state cannot be presented as a confirmed empty list',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => {
          'status': 'unknown',
          'reason': '尚未获得实时通知状态',
          'notifications': <Json>[],
        },
      );
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未获得实时通知状态'), findsOneWidget);
      expect(find.text('没有当前通知'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

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
      await tester.pumpAndSettle();
      expect(find.text('来源手机 有来电'), findsOneWidget);
      expect(find.text('查看来电与声音'), findsOneWidget);
      expect(commands, isNot(contains('calls.action')));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
