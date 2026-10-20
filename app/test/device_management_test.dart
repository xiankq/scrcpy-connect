import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/details/convert_ip/devices_details_convert_ip_page.dart';
import 'package:scrcpy_connect/pages/devices/details/connection_preferences/devices_details_connection_preferences_page.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/settings/adb_identity/settings_adb_identity_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

const phone = <String, dynamic>{
  'id': 'phone',
  'name': '我的手机',
  'model': 'Pixel 9',
  'androidVersion': '15',
  'transport': 'tls',
  'address': '192.168.1.8',
  'port': 37123,
  'status': 'connected',
};

Future<void> pump(
  WidgetTester tester,
  AppController controller,
  Widget page, {
  bool narrow = false,
}) async {
  tester.view.physicalSize = narrow
      ? const Size(280, 620)
      : const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = narrow ? 2 : 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    RouterTestApp(
      controller: controller,
      devices: [phone],
      theme: ConnectTokens.theme(narrow ? Brightness.dark : Brightness.light),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

void main() {
  for (final remoteAction in [false, true]) {
    testWidgets(
      'offline USB ${remoteAction ? 'remote action' : 'workspace connect'} requests a fresh system descriptor',
      (tester) async {
        final calls = <(String, Json)>[];
        final usb = {...phone, 'transport': 'usb', 'status': 'offline'};
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          calls.add((command, params));
          return command == 'devices.usb'
              ? {'devices': <Json>[]}
              : <String, dynamic>{};
        });
        addTearDown(controller.dispose);
        controller.devices = [usb];
        await pump(
          tester,
          controller,
          DeviceWorkspacePage(controller: controller, device: usb),
        );
        final action = find.text(remoteAction ? '文件管理' : '连接手机');
        await reveal(tester, action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        if (remoteAction) {
          await tester.tap(find.text('连接设备'));
          await tester.pumpAndSettle();
        }
        expect(calls.where((call) => call.$1 == 'devices.connect'), isEmpty);
        await reveal(tester, find.text('检查连接'));
        await tester.tap(find.text('检查连接'));
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call.$1 == 'devices.usb').single.$2['deviceId'],
          'phone',
        );
        expect(calls.where((call) => call.$1 == 'files.list'), isEmpty);
      },
    );
  }
  testWidgets(
    'device menu removal confirms its exact record and cancellation changes nothing',
    (tester) async {
      final calls = <(String, Json)>[];
      var removed = false;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'devices.forget') removed = true;
        return command == 'devices.list'
            ? {
                'devices': removed ? <Json>[] : [phone],
              }
            : <String, dynamic>{};
      });
      addTearDown(controller.dispose);
      controller.devices = [phone];
      await pump(tester, controller, DevicesPage(controller: controller));
      await tester.tap(find.byTooltip('设备操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除此设备'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'devices.forget'), isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(removed, isFalse);
      await tester.tap(find.byTooltip('设备操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除此设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除设备'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'devices.forget').single.$2, {
        'deviceId': 'phone',
      });
      expect(find.text('我的手机'), findsNothing);
    },
  );

  testWidgets(
    'global key reset requires the second confirmation and cancels with zero mutations',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'identity.global.get' ||
            command == 'identity.global.reset') {
          return {
            'scope': 'global',
            'fingerprint': 'SHA256:global-public-fingerprint',
            'affectedDeviceIds': ['phone'],
          };
        }
        return {};
      });
      addTearDown(controller.dispose);
      await pump(tester, controller, AdbIdentityPage(controller: controller));
      await tester.tap(find.widgetWithText(OutlinedButton, '重置密钥'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'identity.global.reset'), isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'identity.global.reset'), isEmpty);
      await tester.tap(find.widgetWithText(OutlinedButton, '重置密钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '重置密钥'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'identity.global.reset'), hasLength(1));
      expect(
        calls.where((c) => c.$1 == 'identity.global.reset').single.$2,
        isEmpty,
      );
      expect(find.text('私钥已更新，请在手机上重新授权。'), findsOneWidget);
    },
  );

  testWidgets(
    'device key rejects a password and inheritance changes only the selected device',
    (tester) async {
      final calls = <(String, Json)>[];
      var scope = 'device';
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'identity.device.useGlobal') scope = 'global';
        if (command.startsWith('identity.device.')) {
          return {
            'deviceId': 'phone',
            'scope': scope,
            'fingerprint': 'SHA256:device-public-fingerprint',
          };
        }
        return {};
      });
      addTearDown(controller.dispose);
      await pump(
        tester,
        controller,
        AdbIdentityPage(controller: controller, device: phone),
        narrow: true,
      );
      await reveal(tester, find.text('导入私钥'));
      await tester.tap(find.text('导入私钥'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'password123');
      await reveal(tester, find.text('继续'));
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('PEM 私钥格式无效'), findsOneWidget);
      expect(calls.where((c) => c.$1 == 'identity.device.import'), isEmpty);
      await reveal(tester, find.text('取消'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(OutlinedButton, '使用全局私钥'));
      await tester.tap(find.widgetWithText(OutlinedButton, '使用全局私钥'));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(FilledButton, '使用全局私钥'));
      await tester.tap(find.widgetWithText(FilledButton, '使用全局私钥'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.$1 == 'identity.device.useGlobal').single.$2,
        {'deviceId': 'phone'},
      );
      expect(calls.where((c) => c.$1.startsWith('identity.global.')), isEmpty);
    },
  );

  testWidgets(
    'a missing device private key can explicitly recover through global inheritance',
    (tester) async {
      final calls = <(String, Json)>[];
      var recovered = false;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'identity.device.useGlobal') recovered = true;
        if (command.startsWith('identity.device.')) {
          if (!recovered) {
            throw const RequestFailure(
              'identity_unavailable',
              '设备专用授权私钥不可用，请重新导入或明确选择全局密钥。',
            );
          }
          return {
            'deviceId': 'phone',
            'scope': 'global',
            'fingerprint': 'SHA256:global-public-fingerprint',
          };
        }
        return {};
      });
      addTearDown(controller.dispose);
      await pump(
        tester,
        controller,
        AdbIdentityPage(controller: controller, device: phone),
        narrow: true,
      );
      expect(find.textContaining('设备专用授权私钥不可用'), findsOneWidget);
      await reveal(tester, find.widgetWithText(OutlinedButton, '使用全局私钥'));
      await tester.tap(find.widgetWithText(OutlinedButton, '使用全局私钥'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('取消'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'identity.device.useGlobal'), isEmpty);
      await reveal(tester, find.widgetWithText(OutlinedButton, '使用全局私钥'));
      await tester.tap(find.widgetWithText(OutlinedButton, '使用全局私钥'));
      await tester.pumpAndSettle();
      await reveal(tester, find.widgetWithText(FilledButton, '使用全局私钥'));
      await tester.tap(find.widgetWithText(FilledButton, '使用全局私钥'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.$1 == 'identity.device.useGlobal').single.$2,
        {'deviceId': 'phone'},
      );
      expect(find.text('继承全局私钥'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '使用全局私钥'), findsNothing);
      expect(calls.where((c) => c.$1.startsWith('identity.global.')), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'convert IP validates before requesting and never treats an unverified response as success',
    (tester) async {
      final calls = <(String, Json)>[];
      var attempt = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        if (command == 'devices.list') {
          return {
            'devices': [phone],
          };
        }
        if (command == 'devices.wireless') {
          attempt++;
          if (attempt == 1) {
            throw const RequestFailure(
              'connection_timeout',
              '连接超时，请检查地址、连接端口和网络。',
            );
          }
          return {
            'enabled': true,
            'connected': attempt > 2,
            'deviceId': 'phone',
          };
        }
        return {};
      });
      addTearDown(controller.dispose);
      await pump(
        tester,
        controller,
        DeviceConvertIpPage(controller: controller, device: phone),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, '');
      await tester.enterText(fields.last, '99999');
      await tester.tap(find.text('切换并连接'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'devices.wireless'), isEmpty);
      expect(find.text('请输入被控手机的地址'), findsOneWidget);
      expect(find.text('端口应为 1–65535 的整数'), findsOneWidget);
      await tester.enterText(fields.first, '192.168.1.5');
      await tester.enterText(fields.last, '5666');
      await tester.tap(find.text('切换并连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'devices.wireless'), isEmpty);
      Future<void> submit() async {
        await tester.tap(find.text('切换并连接'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '切换并连接').last);
        await tester.pumpAndSettle();
      }

      await submit();
      expect(find.text('已转为 IP 连接'), findsNothing);
      expect(find.textContaining('连接超时'), findsOneWidget);
      await submit();
      expect(find.text('已转为 IP 连接'), findsNothing);
      expect(find.textContaining('尚未验证 IP 连接'), findsOneWidget);
      await submit();
      expect(find.text('已转为 IP 连接'), findsOneWidget);
      expect(
        calls
            .where((c) => c.$1 == 'devices.wireless')
            .every(
              (c) =>
                  c.$2['deviceId'] == 'phone' &&
                  c.$2['address'] == '192.168.1.5' &&
                  c.$2['port'] == 5666,
            ),
        isTrue,
      );
      expect(calls.where((c) => c.$1 == 'devices.add'), isEmpty);
    },
  );

  testWidgets(
    'offline remote action offers connection without replaying the remote action',
    (tester) async {
      final calls = <(String, Json)>[];
      final offline = {...phone, 'status': 'offline'};
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return {};
      });
      addTearDown(controller.dispose);
      await pump(
        tester,
        controller,
        DeviceWorkspacePage(controller: controller, device: offline),
      );
      await reveal(tester, find.text('文件管理'));
      await tester.tap(find.text('文件管理'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.$1 == 'files.list' || c.$1 == 'devices.connect'),
        isEmpty,
      );
      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == 'devices.connect').single.$2, {
        'deviceId': 'phone',
      });
      expect(calls.where((c) => c.$1 == 'files.list'), isEmpty);
    },
  );
  testWidgets(
    'existing device USB entry carries its identity before authorization',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return command == 'devices.usb'
            ? {'devices': <Json>[]}
            : <String, dynamic>{};
      });
      addTearDown(controller.dispose);
      await pump(
        tester,
        controller,
        DeviceConnectionPreferencesPage(controller: controller, device: phone),
      );
      await tester.tap(find.text('使用 USB 连接'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('检查连接'));
      await tester.tap(find.text('检查连接'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c.$1 == 'devices.usb').single.$2['deviceId'],
        'phone',
      );
      expect(
        calls.where(
          (c) => c.$1 == 'identity.global.reset' || c.$1 == 'devices.add',
        ),
        isEmpty,
      );
    },
  );
}
