import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:io';
import 'dart:convert';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/index/widgets/device_card.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/running_apps.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

final _icon = File('../designs/assets/android-settings-api36.png')
    .readAsBytesSync();
const _device = {
  'id': 'phone',
  'name': '我的手机',
  'model': 'Pixel 9',
  'androidVersion': '15',
  'apiLevel': 35,
  'transport': 'tls',
  'address': '192.168.1.8',
  'port': 37123,
  'status': 'connected',
};

void main() {
  testWidgets(
    'background grid requests only target tasks and rejects installed-list responses',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add((command, params));
        return command == 'apps.list'
            ? {
                'apps': [
                  {'name': '未启动应用', 'packageName': 'not.running'},
                ],
              }
            : {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [RunningApps(controller: controller, device: _device)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single.$1, 'apps.list');
      expect(calls.single.$2, {'deviceId': 'phone', 'filter': 'running'});
      expect(find.text('未启动应用'), findsNothing);
      expect(find.text('暂时无法读取后台应用'), findsOneWidget);
      expect(find.text('没有已启动的应用'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'one thousand running apps request icons only around the visible rows',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final iconRequests = <String>[];
      final image = base64Encode(_icon);
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'apps.list') {
          return {
            'deviceId': 'phone',
            'source': 'runningTasks',
            'live': true,
            'apps': List.generate(
              1000,
              (index) => {
                'name': '应用 $index',
                'packageName': 'dev.fixture.app$index',
                'userId': 0,
                'taskId': index,
              },
            ),
          };
        }
        if (command == 'apps.icon') {
          iconRequests.add(value(params, 'packageName'));
          return {
            'deviceId': 'phone',
            'packageName': params['packageName'],
            'userId': 0,
            'mimeType': 'image/png',
            'dataBase64': image,
          };
        }
        return {};
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: Scaffold(
              body: CustomScrollView(
                slivers: [RunningApps(controller: controller, device: _device)],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(iconRequests, isNotEmpty);
        expect(
          iconRequests.length,
          lessThanOrEqualTo(72),
          reason: 'A viewport plus its cache must not request all one thousand package icons.',
        );
        expect(iconRequests, isNot(contains('dev.fixture.app999')));
        expect(find.text('应用 999'), findsNothing);
        final initial = iconRequests.length;
        await tester.drag(find.byType(Scrollable), const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(iconRequests.length, greaterThan(initial));
        expect(iconRequests.length, lessThanOrEqualTo(120));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'waiting workspace keeps management and can stop reconnection without forgetting',
    (tester) async {
      final calls = <String>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        return {};
      });
      addTearDown(controller.dispose);
      final device = {..._device, 'status': 'offline', 'autoReconnect': true};
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: DeviceWorkspacePage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接手机'), findsOneWidget);
      expect(find.text('等待重连'), findsOneWidget);
      expect(find.text('我的手机'), findsOneWidget);
      expect(find.text('设备信息'), findsNothing);
      expect(find.text('信息来自本机记录'), findsOneWidget);
      expect(calls.where((c) => c == 'apps.list' || c == 'apps.icon'), isEmpty);
      await tester.scrollUntilVisible(
        find.text('文件'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('文件')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      expect(find.text('设备尚未连接'), findsOneWidget);
      expect(
        calls.where((c) => c == 'devices.connect' || c == 'files.list'),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        calls.where((c) => c == 'devices.connect' || c == 'files.list'),
        isEmpty,
      );

      await tester.scrollUntilVisible(
        find.text('移除此设备'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('移除此设备')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(find.text('移除此设备').hitTestable(), findsOneWidget);
      expect(find.byType(SettingsGroup), findsOneWidget);
      final stop = tester.widget<ActionRow>(
        find.widgetWithText(ActionRow, '停止连接'),
      );
      expect(stop.enabled, true);
      await tester.tap(find.text('停止连接'));
      await tester.pumpAndSettle();
      expect(find.textContaining('停止连接和自动重连'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '停止连接'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c == 'devices.disconnect'), hasLength(1));
      expect(calls, isNot(contains('devices.forget')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connecting device card keeps its stop action available', (
    tester,
  ) async {
    final calls = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add(command);
      return {};
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: DeviceCard(
            controller: controller,
            device: {..._device, 'status': 'connecting'},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('设备操作'));
    await tester.pumpAndSettle();
    expect(find.text('开始连接'), findsNothing);
    await tester.tap(find.text('停止连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '停止连接'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c == 'devices.disconnect'), hasLength(1));
    expect(calls, isNot(contains('devices.connect')));
    expect(tester.takeException(), isNull);
  });
}
