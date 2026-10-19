import 'package:scrcpy_connect/widgets/grouped_list.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/background/background_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
