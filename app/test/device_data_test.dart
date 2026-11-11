import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/details/data/devices_details_data_page.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'device facts invalidate on disconnect and fence replaced reads',
    (tester) async {
      tester.view.physicalSize = const Size(600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const first = <String, dynamic>{
        'id': 'phone',
        'name': 'Phone',
        'status': 'connected',
        'connectionId': 'a',
      };
      final replacedRead = Completer<Json>();
      final calls = <Json>[];
      late AppStore controller;
      controller = createTestController((command, params) async {
        if (command != 'device.data.get') return {};
        calls.add(Map.of(params));
        final connectionId =
            params['connectionId'] ?? controller.devices.first['connectionId'];
        if (connectionId == 'b') return replacedRead.future;
        return {
          'deviceId': 'phone',
          'connectionId': params['connectionId'],
          'stale': connectionId == null,
          'system': {'model': 'Known phone'},
          if (connectionId != null)
            'battery': {'level': connectionId == 'c' ? 67 : 39},
        };
      });
      controller.devices = [first];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: Scaffold(
            body: DeviceDataPage(controller: controller, device: first),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('设备详情'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('39%'), findsOneWidget);
      controller.devices = [
        {...first, 'status': 'offline', 'connectionId': null},
      ];
      await tester.pumpAndSettle();
      expect(find.text('39%'), findsNothing);
      expect(find.text('设备离线，以下为本机记录；动态数据尚未更新。'), findsOneWidget);
      controller.devices = [
        {...first, 'connectionId': 'b'},
      ];
      await tester.pump();
      await tester.pump();
      controller.devices = [
        {...first, 'connectionId': 'c'},
      ];
      await tester.pumpAndSettle();
      expect(find.text('67%'), findsOneWidget);
      replacedRead.complete({
        'stale': false,
        'battery': {'level': 99},
      });
      await tester.pumpAndSettle();
      expect(find.text('99%'), findsNothing);
      expect(find.text('67%'), findsOneWidget);
      expect(calls.map((p) => p['connectionId']), ['a', null, 'b', 'c']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
