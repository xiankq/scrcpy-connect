import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/models/connection_validation.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'reauthorization preserves device identity and cancellation targets its attempt',
    (tester) async {
      final pending = Completer<Json>();
      Json? pairParams;
      Json? cancelParams;
      final controller = createTestController((command, params) async {
        if (command == 'devices.pair') {
          pairParams = Map<String, dynamic>.from(params);
          return pending.future;
        }
        if (command == 'devices.cancel') {
          cancelParams = Map<String, dynamic>.from(params);
          return {'cancelled': true};
        }
        return command == 'devices.list' ? {'devices': <Json>[]} : {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: AddDevicePage(
            controller: controller,
            initialDevice: const {
              'id': 'restored-id',
              'name': '恢复的手机',
              'address': 'phone.local',
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).at(1), '37123');
      await tester.enterText(find.byType(TextFormField).at(2), '123456');
      await tester.ensureVisible(find.text('配对并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('配对并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '应用并连接'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pairParams?['deviceId'], 'restored-id');
      expect(pairParams?['address'], 'phone.local');
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(cancelParams?['attemptId'], pairParams?['attemptId']);
      expect(cancelParams?['attemptId'], isNotEmpty);
      pending.completeError(StateError('cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('已取消本次尝试。'), findsOneWidget);
      expect(find.byType(ConnectionFailureNote), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'wireless fields accept IP and hostnames and reject malformed input',
    () {
      for (final address in [
        '192.168.0.8',
        'phone.local',
        '2001:db8::1',
        '[2001:db8::1]',
        'fe80::1%wlan0',
      ]) {
        expect(validateAddress(address), isNull, reason: address);
      }
      for (final address in [
        '',
        '256.0.0.1',
        'http://phone',
        'phone:37123',
        '::::',
        'phone..local',
      ]) {
        expect(validateAddress(address), isNotNull, reason: address);
      }
      for (final port in ['1', '65535', '37123']) {
        expect(validatePort(port), isNull);
      }
      for (final port in ['', '0', '65536', '12.5', 'abc']) {
        expect(validatePort(port), isNotNull);
      }
    },
  );
}
