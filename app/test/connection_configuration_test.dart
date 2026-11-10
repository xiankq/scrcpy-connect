import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/index/connection_index_page.dart';
import 'package:scrcpy_connect/pages/devices/details/convert_ip/devices_details_convert_ip_page.dart';
import 'package:scrcpy_connect/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';

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
    'IP conversion follows the current authorized connection and surfaces unsupported reads',
    (tester) async {
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'device.network.get') {
          throw const RequestFailure('unsupported', '当前设备不支持读取网络接口。');
        }
        return {};
      })..devices = [phone];
      await mount(
        tester,
        controller,
        DeviceConnectionPreferencesPage(controller: controller, device: phone),
      );
      await tap(tester, '转为 IP 连接');
      expect(find.textContaining('当前设备不支持读取网络接口'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '切换并连接'))
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      controller.devices = [
        {...phone, 'status': 'offline'},
      ];
      await tester.pumpAndSettle();
      expect(find.text('转为 IP 连接'), findsNothing);
      controller.devices = [
        {...phone, 'transport': 'usb'},
      ];
      await tester.pumpAndSettle();
      expect(find.text('转为 IP 连接'), findsOneWidget);
      controller.devices = [
        {...phone, 'transport': 'tcp'},
      ];
      await tester.pumpAndSettle();
      expect(find.text('转为 IP 连接'), findsNothing);
      controller.devices = [];
      await tester.pumpAndSettle();
      expect(find.text('转为 IP 连接'), findsNothing);
    },
  );

  testWidgets(
    'new IP attempts use the managed global identity without exposing private keys',
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
      await tap(tester, 'IP 连接');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('PEM 私钥'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, 'phone.local');
      await tap(tester, '连接设备');
      expect(
        calls
            .singleWhere((c) => c.$1 == 'devices.add')
            .$2
            .containsKey('identity'),
        isFalse,
      );
      expect(calls.where((c) => c.$1.startsWith('identity.')), isEmpty);
    },
  );

  testWidgets(
    'unknown connection uses ordinary feedback and rechecking never resends the request',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'devices.add') {
          throw const RequestFailure('result_unknown', '连接回执尚未确认。');
        }
        return {};
      });
      await mount(tester, controller, AddDevicePage(controller: controller));
      await tap(tester, 'IP 连接');
      await tester.enterText(find.byType(TextFormField).first, 'phone.local');
      await tap(tester, '连接设备');
      expect(find.byType(AmbientLoadingField), findsNothing);
      expect(find.text('连接结果待确认'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      await tap(tester, '重新核对');
      expect(calls.where((c) => c.$1 == 'devices.add').length, 1);
      expect(calls.where((c) => c.$1 == 'state.reconcile').length, 1);
      expect(find.text('连接结果待确认'), findsOneWidget);
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
