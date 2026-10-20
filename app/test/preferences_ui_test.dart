import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'device switches default independently and save only that device',
    (tester) async {
      final updates = <Map<String, dynamic>>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'settings.update') updates.add(Map.of(params));
        return {};
      });
      addTearDown(controller.dispose);
      controller.settings = {
        'deviceSettings': {
          'other': {'clipboardSync': true, 'showNavigationBar': false},
        },
      };
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: DeviceWorkspacePage(
            controller: controller,
            device: const {'id': 'phone', 'name': '手机'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final clipboard = find.widgetWithText(ConnectSwitchRow, '自动同步剪贴板');
      final navigation = find.widgetWithText(ConnectSwitchRow, '显示导航键');
      await tester.scrollUntilVisible(clipboard, 200);
      expect(tester.widget<ConnectSwitchRow>(clipboard).value, isFalse);
      await tester.scrollUntilVisible(navigation, 100);
      expect(tester.widget<ConnectSwitchRow>(navigation).value, isTrue);
      await tester.scrollUntilVisible(clipboard, -100);
      await Scrollable.ensureVisible(tester.element(clipboard), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(clipboard);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(navigation), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(navigation);
      await tester.pumpAndSettle();
      expect(updates, hasLength(2));
      expect(controller.settings['deviceSettings'], {
        'other': {'clipboardSync': true, 'showNavigationBar': false},
        'phone': {'clipboardSync': true, 'showNavigationBar': false},
      });
      expect(tester.takeException(), isNull);
    },
  );
}
