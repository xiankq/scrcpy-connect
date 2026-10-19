import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/notification_reply/notification_reply_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/notification_replies.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const _device = {'id': 'phone-a', 'name': '手机 A', 'status': 'connected'};
const _notification = {
  'id': 'notification',
  'revision': 'action-1',
  'title': '消息',
};

Widget _page(
  AppController controller, {
  Json notification = _notification,
  Json device = _device,
}) => RouterTestApp(
  controller: controller,
  theme: ConnectTokens.theme(Brightness.light),
  home: NotificationReplyPage(
    controller: controller,
    device: device,
    notification: notification,
  ),
);

void main() {
  for (final status in ['unknown', 'acceptedBySystem']) {
    testWidgets(
      'reply $status survives leaving and reopening without another submission',
      (tester) async {
        final submitted = <Json>[];
        final pending = Completer<Json>();
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'notifications.reply') {
            submitted.add(params);
            return pending.future;
          }
          return {};
        });
        await tester.pumpWidget(_page(controller));
        await tester.enterText(find.byType(TextField), '离页后仍保留的回复');
        await tester.ensureVisible(find.text('发送回复'));
        await tester.tap(find.text('发送回复'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        pending.complete({'status': status});
        await tester.pump();
        await tester.pumpWidget(_page(controller));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '离页后仍保留的回复',
        );
        expect(find.text('发送回复'), findsNothing);
        expect(find.text('到手机上核对'), findsOneWidget);
        expect(submitted, hasLength(1));
        expect(submitted.single, {
          'deviceId': 'phone-a',
          'notificationId': 'notification',
          'text': '离页后仍保留的回复',
        });
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
  testWidgets(
    'a changed notification expires its old reply action and preserves the draft',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      var submissions = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.reply') submissions++;
        return {};
      }, events: events.stream);
      await tester.pumpWidget(_page(controller));
      await tester.enterText(find.byType(TextField), '已失效动作的草稿');
      events.add({
        'type': 'notifications.changed',
        'deviceId': 'phone-a',
        'data': {
          'status': 'available',
          'live': true,
          'notifications': [
            {'id': 'notification', 'revision': 'action-2', 'canReply': true},
          ],
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('发送回复'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '已失效动作的草稿',
      );
      expect(submissions, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
  testWidgets(
    'the real reply route retains submitted text when the original notification disappears',
    (tester) async {
      var listed = true;
      final submitted = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'device.info') return _device;
        if (command == 'devices.list') {
          return {
            'devices': [_device],
          };
        }
        if (command == 'notifications.list') {
          return {
            'status': 'available',
            'live': true,
            'notifications': [if (listed) _notification],
          };
        }
        if (command == 'notifications.reply') {
          submitted.add(params);
          return {'status': 'acceptedBySystem'};
        }
        return {};
      })..devices = [_device];
      final router = createAppRouter(
        initialLocation: '/devices/phone-a/notifications/notification/reply',
      );
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '原通知消失后仍可核对的内容');
      await tester.ensureVisible(find.text('发送回复'));
      await tester.tap(find.text('发送回复'));
      await tester.pumpAndSettle();
      router.go('/devices/phone-a');
      await tester.pumpAndSettle();
      listed = false;
      router.go('/devices/phone-a/notifications/notification/reply');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '原通知消失后仍可核对的内容',
      );
      expect(find.text('复制保留内容'), findsOneWidget);
      expect(find.text('发送回复'), findsNothing);
      expect(submitted, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      controller.dispose();
    },
  );
  testWidgets(
    'reply content and guards are isolated by device and action revision',
    (tester) async {
      final submitted = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.reply') submitted.add(params);
        return {'status': 'unknown'};
      });
      await tester.pumpWidget(_page(controller));
      await tester.enterText(find.byType(TextField), '只属于手机A旧动作');
      await tester.ensureVisible(find.text('发送回复'));
      await tester.tap(find.text('发送回复'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      for (final (device, notification) in [
        ({..._device, 'id': 'phone-b'}, _notification),
        (_device, {..._notification, 'revision': 'action-2'}),
      ]) {
        await tester.pumpWidget(
          _page(controller, device: device, notification: notification),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpWidget(_page(controller));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '只属于手机A旧动作',
      );
      expect(find.text('发送回复'), findsNothing);
      expect(submitted, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'bounded reply retention never evicts an unresolved submission',
    () async {
      final controller = createTestController(
        (command, [params = const {}]) async => {'status': 'unknown'},
      );
      for (var i = 0; i < 64; i++) {
        final key = AppController.notificationReplyKey('phone-a', {
          'id': 'notification-$i',
        });
        expect(controller.updateNotificationReplyDraft(key, '保留内容 $i'), isTrue);
        await controller.submitNotificationReply(key);
      }
      expect(
        controller.updateNotificationReplyDraft(
          AppController.notificationReplyKey('phone-a', {'id': 'new'}),
          '不能挤掉旧提交',
        ),
        isFalse,
      );
      final first =
          controller
              .snapshot()
              .notificationReplies[AppController.notificationReplyKey(
            'phone-a',
            {'id': 'notification-0'},
          )]!;
      expect(first.phase, NotificationReplyPhase.unknown);
      expect(first.text, '保留内容 0');
      expect(controller.snapshot().notificationReplies, hasLength(64));
      expect(
        () => controller.snapshot().notificationReplies.clear(),
        throwsUnsupportedError,
      );
      controller.dispose();
    },
  );

  testWidgets(
    'forgetting a device clears retained replies and a late submission cannot restore them',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      final result = Completer<Json>();
      final controller = createTestController(
        (command, [params = const {}]) async => command == 'notifications.reply'
            ? result.future
            : {'devices': <Json>[]},
        events: events.stream,
      );
      final key = AppController.notificationReplyKey('phone-a', _notification);
      controller.updateNotificationReplyDraft(key, '移除设备后不保留');
      final submitting = controller.submitNotificationReply(key);
      events.add({
        'type': 'devices.changed',
        'data': {'devices': <Json>[]},
      });
      await tester.pump();
      result.complete({'status': 'acceptedBySystem'});
      await submitting;
      expect(controller.snapshot().notificationReplies, isEmpty);
      controller.dispose();
      await events.close();
    },
  );
  testWidgets(
    'authentication rejection keeps an editable draft and an explicit retry after unlocking',
    (tester) async {
      var submissions = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.reply') {
          submissions++;
          if (submissions == 1) {
            throw const RequestFailure('authentication_required', '请先解锁被控手机');
          }
          return {'status': 'acceptedBySystem'};
        }
        return {};
      });
      await tester.pumpWidget(_page(controller));
      await tester.enterText(find.byType(TextField), '认证后由用户明确重新提交');
      await tester.ensureVisible(find.text('发送回复'));
      await tester.tap(find.text('发送回复'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.text('发送回复'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_page(controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('发送回复'));
      await tester.tap(find.text('发送回复'));
      await tester.pumpAndSettle();
      expect(submissions, 2);
      expect(find.text('发送回复'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '认证后由用户明确重新提交',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'authoritative recovery drops forgotten-device replies before a late receipt',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      final result = Completer<Json>();
      final controller = createTestController(
        (command, [params = const {}]) async =>
            command == 'notifications.reply' ? result.future : {},
        events: events.stream,
      );
      final key = AppController.notificationReplyKey('phone-a', _notification);
      controller.updateNotificationReplyDraft(key, '恢复快照中已被移除');
      final submitting = controller.submitNotificationReply(key);
      events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
      events.add({
        'type': 'state.resynced',
        'data': {
          'sequence': 10,
          'devices': <Json>[],
          'settings': <String, dynamic>{},
          'sessions': <Json>[],
          'shares': <Json>[],
        },
      });
      await tester.pump();
      result.complete({'status': 'acceptedBySystem'});
      await submitting;
      expect(controller.snapshot().notificationReplies, isEmpty);
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'recovery revalidates the original notification action from companion snapshots',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      final controller = createTestController(
        (command, [params = const {}]) async => {},
        events: events.stream,
      );
      final key = AppController.notificationReplyKey('phone-a', _notification);
      controller.updateNotificationReplyDraft(key, '已更新动作的草稿');
      events.add({
        'type': 'state.resynced',
        'data': {
          'sequence': 11,
          'devices': [_device],
          'settings': <String, dynamic>{},
          'sessions': <Json>[],
          'shares': <Json>[],
          'companions': [
            {
              'deviceId': 'phone-a',
              'state': {
                'notifications': {
                  'live': true,
                  'status': 'available',
                  'notifications': <Json>[],
                },
              },
            },
          ],
        },
      });
      await tester.pump();
      expect(controller.snapshot().notificationReplies[key]!.expired, isTrue);
      controller.dispose();
      await events.close();
    },
  );

  test('empty unsent drafts release capacity without evicting any unresolved reply', () {
    final controller = createTestController(
      (command, [params = const {}]) async => {},
    );
    for (var i = 0; i < 64; i++) {
      final key = AppController.notificationReplyKey('phone-a', {
        'id': 'notification-$i',
      });
      expect(controller.updateNotificationReplyDraft(key, '已清空的草稿'), isTrue);
      expect(controller.updateNotificationReplyDraft(key, ''), isTrue);
    }
    expect(controller.snapshot().notificationReplies, isEmpty);
    expect(
      controller.updateNotificationReplyDraft(
        AppController.notificationReplyKey('phone-a', {'id': 'new'}),
        '新的回复',
      ),
      isTrue,
    );
    controller.dispose();
  });
}
