import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final (code, message) in [
    ('permission_denied', '尚未允许主控应用访问 USB 设备。'),
    ('cancelled', '已取消选择 USB 设备。'),
  ]) {
    testWidgets('$code permits a fresh USB attempt after changing modes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final requests = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'devices.usb') {
          requests.add(params);
          throw RequestFailure(code, message);
        }
        return {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      const UsbGuideRoute().push<void>(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();
      final check = find.widgetWithText(FilledButton, '检查连接');
      Future<void> checkAgain() async {
        await tester.scrollUntilVisible(
          check,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(check);
        await tester.pumpAndSettle();
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
        expect(find.text('取消本次检查'), findsNothing);
      }

      await checkAgain();
      await checkAgain();
      expect(requests, hasLength(2));
      await Scrollable.ensureVisible(
        tester.element(find.text('无线配对码')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('无线配对码'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.byType(UsbGuidePage), findsNothing);
      await Scrollable.ensureVisible(
        tester.element(find.text('USB')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('USB'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
      await checkAgain();
      expect(requests, hasLength(3));
      final attempts = requests.map((request) => value(request, 'attemptId'));
      expect(attempts.every((id) => id.isNotEmpty), isTrue);
      expect(attempts.toSet(), hasLength(3));
      expect(requests.every((request) => request['connect'] != true), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
