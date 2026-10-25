import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/devices/details/convert_ip/devices_details_convert_ip_page.dart';
import 'package:scrcpy_connect/application/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const phone = <String, dynamic>{
  'id': 'original',
  'name': '手机',
  'status': 'connected',
  'transport': 'tls',
  'address': 'phone.local',
  'port': 37123,
  'connectionId': 'connection-original',
};
const pem = '-----BEGIN PRIVATE KEY-----\nAQID\n-----END PRIVATE KEY-----';

Future<void> mount(
  WidgetTester tester,
  AppController controller,
  Widget page,
) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      home: page,
      devices: [phone],
      theme: ConnectTokens.theme(Brightness.light),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text).last;
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'custom identity is validated and submitted with the selected IP attempt',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return {};
      });
      await mount(tester, controller, AddDevicePage(controller: controller));
      await tap(tester, 'IP连接');
      await tester.enterText(find.byType(TextFormField).first, 'phone.local');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备专属私钥').last);
      await tester.pumpAndSettle();
      await tap(tester, '连接设备');
      expect(find.text('请输入 PEM 私钥'), findsOneWidget);
      expect(calls.where((c) => c.$1 == 'devices.add'), isEmpty);
      await tester.enterText(find.widgetWithText(TextFormField, 'PEM 私钥'), pem);
      await tap(tester, '连接设备');
      expect(calls.singleWhere((c) => c.$1 == 'devices.add').$2['identity'], {
        'scope': 'device',
        'privateKeyPem': pem,
      });
      expect(
        calls.where(
          (c) => c.$1.startsWith('identity.') && c.$1 != 'identity.device.get',
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'changing an identity draft cancels an old QR and waits for explicit generation',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'devices.pair.qr') {
          return {
            'attemptId': 'old-qr',
            'payload': 'WIFI:T:ADB;S:test;P:secret;;',
          };
        }
        return {};
      });
      await mount(tester, controller, AddDevicePage(controller: controller));
      await tap(tester, '扫码配对');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备专属私钥').last);
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.$1 == 'devices.cancel').last.$2['attemptId'],
        'old-qr',
      );
      expect(calls.where((c) => c.$1 == 'devices.pair.qr').length, 1);
      await tester.enterText(find.widgetWithText(TextFormField, 'PEM 私钥'), pem);
      await tap(tester, '重新生成');
      final qr = calls.where((c) => c.$1 == 'devices.pair.qr').last;
      expect(qr.$2['identity'], {'scope': 'device', 'privateKeyPem': pem});
      expect(find.widgetWithText(FilledButton, '重新生成'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'IP switch only selects target interfaces and aborts if the address changes',
    (tester) async {
      var queries = 0;
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'device.network.get') {
          return {
            'deviceId': 'original',
            'connectionId': 'connection-original',
            'addresses': [
              {
                'address': ++queries == 1 ? '192.168.1.8' : '192.168.1.9',
                'interface': 'wlan0',
              },
            ],
          };
        }
        return {};
      });
      await mount(
        tester,
        controller,
        DeviceConvertIpPage(controller: controller, device: phone),
      );
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '5555',
      );
      await tap(tester, '切换并连接');
      expect(find.text('目标设备的网络地址已变化，请重新选择。'), findsOneWidget);
      expect(calls.where((c) => c.$1 == 'devices.wireless'), isEmpty);
      expect(find.text('192.168.1.9 · wlan0'), findsOneWidget);
    },
  );

  testWidgets(
    'IP switch rejects another connection receipt and offers a new read',
    (tester) async {
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'device.network.get') {
          return {
            'deviceId': 'other-phone',
            'connectionId': 'other-connection',
            'addresses': [
              {'address': '192.168.1.7'},
            ],
          };
        }
        return {};
      });
      await mount(
        tester,
        controller,
        DeviceConvertIpPage(controller: controller, device: phone),
      );
      expect(find.textContaining('设备连接已变化'), findsOneWidget);
      expect(find.text('192.168.1.7'), findsNothing);
      expect(find.text('重新获取地址'), findsOneWidget);
    },
  );
}
