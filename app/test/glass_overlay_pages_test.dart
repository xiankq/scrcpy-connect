import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/calls/devices_workspace_calls_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/notifications/index/devices_workspace_notifications_index_page.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';
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
    'notification menu keeps local hide separate from remote dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final dismissals = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.dismiss') dismissals.add(params);
        return command == 'notifications.list'
            ? {
                'status': 'available',
                'live': true,
                'notifications': [
                  for (final id in ['one', 'two'])
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
        await tester.ensureVisible(find.byTooltip('通知操作').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('通知操作').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('仅在本机隐藏'));
        await tester.pumpAndSettle();
        expect(find.text('通知 one'), findsNothing);
        expect(dismissals, isEmpty);
        await tester.ensureVisible(find.byTooltip('通知操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('通知操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('清除手机上的通知'));
        await tester.pumpAndSettle();
        expect(dismissals, [
          {'deviceId': 'phone-a', 'notificationId': 'two'},
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets('glass about dialog keeps version, licenses and close actions', (
    tester,
  ) async {
    final controller = createTestController(
      (command, [params = const {}]) async => command == 'system.info'
          ? {'version': '2.3.4', 'description': '设备互联'}
          : {},
    );
    try {
      await _mount(tester, controller, SettingsPage(controller: controller));
      await tester.scrollUntilVisible(find.text('关于邻接'), 300);
      await tester.tap(find.text('关于邻接'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassAlertDialog), findsOneWidget);
      expect(find.text('2.3.4'), findsOneWidget);
      final dialogContext = tester.element(find.byType(GlassAlertDialog));
      final labels = MaterialLocalizations.of(dialogContext);
      await tester.tap(find.text(labels.viewLicensesButtonLabel));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(labels.closeButtonLabel));
      await tester.pumpAndSettle();
      expect(find.byType(GlassAlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}
