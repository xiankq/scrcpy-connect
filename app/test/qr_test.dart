import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/connection/wireless/qr/connection_wireless_qr_page.dart';

import 'support/router_test_app.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'switching to a pairing-code form cancels the hidden QR attempt first',
    (tester) async {
      final cancelled = <String>[];
      final controller = createTestController((command, params) async {
        if (command == 'device.info') {
          return {'id': 'paired-device', 'name': '配对设备', 'status': 'offline'};
        }
        if (command == 'devices.pair.qr') {
          return {
            'payload': 'WIFI:T:ADB;S:test;P:123456;;',
            'attemptId': 'visible-qr',
            'expiresAt': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
          };
        }
        if (command == 'devices.cancel') {
          cancelled.add(value(params, 'attemptId'));
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: QrPairPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('使用配对码'));
      await tester.tap(find.text('使用配对码'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionFormPage), findsOneWidget);
      expect(cancelled, ['visible-qr']);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'regenerated QR ignores an old terminal event and preserves the paired device for a missing connection port',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      final cancelled = <String>[];
      var generation = 0;
      final controller = createTestController((command, params) async {
        if (command == 'device.info') {
          return {'id': 'paired-device', 'name': '配对设备', 'status': 'offline'};
        }
        if (command == 'devices.pair.qr') {
          return {
            'payload': 'WIFI:T:ADB;S:test;P:123456;;',
            'attemptId': 'qr-${++generation}',
            'expiresAt': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
          };
        }
        if (command == 'devices.cancel') {
          cancelled.add(value(params, 'attemptId'));
        }
        return {};
      }, events: events.stream);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: QrPairPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重新生成'));
      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();
      expect(cancelled, contains('qr-1'));
      events.add({
        'type': 'pairing.changed',
        'data': {'attemptId': 'qr-1', 'status': 'expired'},
      });
      await tester.pump();
      expect(find.text('二维码已过期，请重新生成。'), findsNothing);
      events.add({
        'type': 'pairing.changed',
        'data': {
          'attemptId': 'qr-2',
          'status': 'paired',
          'result': {
            'deviceId': 'paired-device',
            'address': '192.0.2.4',
            'connected': false,
          },
        },
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('填写连接端口'));
      await tester.tap(find.text('填写连接端口'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ConnectionFormPage>(find.byType(ConnectionFormPage))
            .deviceId,
        'paired-device',
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
    },
  );
}
