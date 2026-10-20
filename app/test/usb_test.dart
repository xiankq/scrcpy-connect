import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'USB discovery requires an explicit device choice before opening its connected workspace',
    (tester) async {
      final requests = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'device.info') {
          return {
            'id': 'usb-phone',
            'name': 'USB Pixel',
            'status': 'connected',
          };
        }
        if (command == 'devices.usb') {
          requests.add(params);
          if (params['usbDeviceId'] == 'attachment-a') {
            return {
              'connected': true,
              'deviceId': 'usb-phone',
              'device': {
                'id': 'usb-phone',
                'name': 'USB Pixel',
                'status': 'connected',
              },
            };
          }
          return {
            'supported': true,
            'selectionRequired': true,
            'devices': [
              {
                'usbDeviceId': 'attachment-a',
                'vendorId': 6353,
                'productId': 20199,
              },
              {'usbDeviceId': 'attachment-b', 'serial': 'serial-b'},
            ],
          };
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: UsbGuidePage(controller: controller),
        ),
      );
      await tester.scrollUntilVisible(find.text('检查连接'), 250);
      await tester.tap(find.text('检查连接'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('打开设备工作台'), findsNothing);
      await tester.scrollUntilVisible(find.text('USB 设备 1'), 200);
      await tester.ensureVisible(find.text('USB 设备 1'));
      await tester.pumpAndSettle();
      expect(find.text('attachment-a'), findsNothing);
      await tester.tap(find.text('USB 设备 1'));
      await tester.pumpAndSettle();
      expect(requests.last['connect'], isTrue);
      expect(requests.last['usbDeviceId'], 'attachment-a');
      expect(requests.last.containsKey('serial'), false);
      expect(requests.last['attemptId'], isNotEmpty);
      await tester.scrollUntilVisible(find.text('打开设备工作台'), 200);
      await tester.ensureVisible(find.text('打开设备工作台'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开设备工作台'));
      await tester.pumpAndSettle();
      expect(find.text('打开手机屏幕'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'USB cancellation and disposal target only the owning attempt and ignore late results',
    (tester) async {
      final attempts = <Json>[];
      final cancellations = <Json>[];
      final pending = <Completer<Json>>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'devices.usb') {
          attempts.add(params);
          final result = Completer<Json>();
          pending.add(result);
          return result.future;
        }
        if (command == 'devices.cancel') cancellations.add(params);
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: UsbGuidePage(controller: controller),
        ),
      );
      await tester.scrollUntilVisible(find.text('检查连接'), 250);
      await tester.pump();
      await tester.tap(find.text('检查连接'));
      await tester.pump();
      expect(attempts.single['attemptId'], isNotEmpty);
      await tester.scrollUntilVisible(find.text('取消本次检查'), 200);
      await tester.pump();
      await tester.tap(find.text('取消本次检查'));
      await tester.pumpAndSettle();
      expect(cancellations.single['attemptId'], attempts.single['attemptId']);
      await tester.tap(find.text('检查连接'));
      await tester.pump();
      expect(attempts, hasLength(2));
      expect(attempts[1]['attemptId'], isNot(attempts[0]['attemptId']));
      pending[0].complete({'message': 'stale success'});
      await tester.pump();
      expect(find.text('stale success'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cancellations.last['attemptId'], attempts[1]['attemptId']);
      pending[1].completeError(StateError('cancelled'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
