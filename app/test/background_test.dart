import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:scrcpy_connect/widgets/grouped_list.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/settings/background/settings_background_page.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'background receipts and foreground return refresh status without requesting permission again',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final commands = <String>[];
      var title = '后台正在核验';
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add(command);
        return command == 'background.status'
            ? {'title': title, 'reason': '当前状态'}
            : {};
      }, events: events.stream);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: BackgroundPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('后台正在核验'), findsOneWidget);
      title = '设备活动正在保持';
      events.add({'type': 'background.changed', 'data': <String, dynamic>{}});
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(
        commands.where((command) => command == 'background.status'),
        hasLength(2),
      );
      events.add({'type': 'device.changed', 'data': <String, dynamic>{}});
      await tester.pumpAndSettle();
      expect(
        commands.where((command) => command == 'background.status'),
        hasLength(2),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      title = '通知权限已变更';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(
        commands.where((command) => command == 'background.status'),
        hasLength(3),
      );
      expect(
        commands.where((command) => command == 'background.request'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      final before = commands.length;
      events.add({'type': 'background.changed', 'data': <String, dynamic>{}});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(commands.length, before);
      expect(tester.takeException(), isNull);
      controller.dispose();
      await events.close();
    },
  );

  testWidgets(
    'explicit background preference requests native permission once after saving and refreshes status',
    (tester) async {
      final commands = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        commands.add((command, params));
        return command == 'background.status'
            ? {'title': '系统后台条件', 'reason': '已核验', 'canRequest': true}
            : {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: BackgroundPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(commands.where((c) => c.$1 == 'background.request'), isEmpty);
      await tester.tap(find.widgetWithText(ConnectSwitchRow, '允许后台保持'));
      await tester.pumpAndSettle();
      final requests = commands
          .where((c) => c.$1 == 'background.request')
          .toList();
      expect(requests, hasLength(1));
      expect(requests.single.$2, {
        'enabled': true,
        'askNotificationPermission': true,
      });
      expect(
        commands.indexWhere((c) => c.$1 == 'settings.update'),
        lessThan(commands.indexWhere((c) => c.$1 == 'background.request')),
      );
      expect(commands.where((c) => c.$1 == 'background.status'), hasLength(2));
      await tester.tap(find.widgetWithText(ConnectSwitchRow, '允许后台保持'));
      await tester.pumpAndSettle();
      expect(commands.lastWhere((c) => c.$1 == 'background.request').$2, {
        'enabled': false,
        'askNotificationPermission': false,
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
