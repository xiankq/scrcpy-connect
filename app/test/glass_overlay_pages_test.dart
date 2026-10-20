import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/test_controller.dart';

const _device = {'id': 'phone-a', 'name': '来源手机'};

Future<void> _mount(
  WidgetTester tester,
  AppController controller,
  Widget page, {
  double scale = 1,
}) async {
  controller.loading = false;
  await tester.pumpWidget(
    TestProviderScope(
      controller: controller,
      child: MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'long call route sheet scrolls at 2x and preserves the call target',
    (tester) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final actions = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'calls.action') actions.add(params);
        return command == 'calls.list'
            ? {
                'status': 'available',
                'live': true,
                'calls': [
                  {
                    'id': 'call-a',
                    'name': '当前通话',
                    'state': 'active',
                    'canSetRoute': true,
                    'routes': [
                      for (var index = 0; index < 18; index++)
                        {'id': 'route-$index', 'name': '声音设备 $index'},
                    ],
                  },
                ],
              }
            : {};
      });
      try {
        await _mount(
          tester,
          controller,
          CallsPage(controller: controller, device: _device),
          scale: 2,
        );
        await tester.scrollUntilVisible(find.text('声音路由'), 300);
        await tester.pumpAndSettle();
        expect(find.text('声音路由').hitTestable(), findsOneWidget);
        await tester.tap(find.text('声音路由'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(actions, isEmpty);
        expect(find.byType(BottomSheet), findsNothing);
        await tester.ensureVisible(find.text('声音路由'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('声音路由'));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        await tester.scrollUntilVisible(
          find.text('声音设备 17'),
          300,
          scrollable: find
              .descendant(of: sheet, matching: find.byType(Scrollable))
              .first,
        );
        await tester.tap(find.text('声音设备 17'));
        await tester.pumpAndSettle();
        expect(actions, [
          {
            'deviceId': 'phone-a',
            'callId': 'call-a',
            'action': 'route',
            'route': 'route-17',
          },
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'notification clear remains reachable at 2x and synchronizes the phone snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final dismissals = <Json>[];
      final remaining = ['one', 'two'];
      final commands = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        if (command == 'notifications.dismiss') {
          dismissals.add(params);
          remaining.remove(params['notificationId']);
          return {'dismissed': true, 'markedRead': false};
        }
        return command == 'notifications.list'
            ? {
                'status': 'available',
                'live': true,
                'notifications': [
                  for (final id in remaining)
                    {
                      'id': id,
                      'appName': '消息 $id',
                      'title': '通知 $id',
                      'canDismiss': true,
                    },
                ],
              }
            : {};
      });
      try {
        await _mount(
          tester,
          controller,
          NotificationsPage(controller: controller, device: _device),
          scale: 2,
        );
        expect(find.text('仅在本机隐藏'), findsNothing);
        for (final id in ['one', 'two']) {
          final clear = find.descendant(
            of: find.byKey(ValueKey('notification-$id')),
            matching: find.byTooltip('已读（清除）'),
          );
          await tester.scrollUntilVisible(clear, 180);
          await tester.ensureVisible(clear);
          await tester.pumpAndSettle();
          expect(clear.hitTestable(), findsOneWidget);
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(find.text('通知 $id'), findsNothing);
        }
        expect(dismissals, [
          {'deviceId': 'phone-a', 'notificationId': 'one'},
          {'deviceId': 'phone-a', 'notificationId': 'two'},
        ]);
        expect(find.text('没有当前通知'), findsOneWidget);
        expect(commands, isNot(contains('notifications.open')));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
