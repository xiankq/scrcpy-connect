import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/connection/usb/connection_usb_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/application/app_controller.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'product_flow_test.dart' show waitFor;

// 需要在 Android 主控上预先准备外部 USBIP ADB 夹具；Android UsbManager 和权限界面真实，仅线缆虚拟。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var stage = 'waiting-fixture';
  String? runId;
  var hostFailed = false;
  final acknowledged = <String>{};
  binding.reportData = {
    'usbConnectionComplete': false,
    'systemDenialReturned': false,
    'denialRetryAvailable': false,
    'systemGrantReturned': false,
    'usbWorkspaceOpened': false,
    'postLeaseShellVerified': false,
    'postLeaseFilesVerified': false,
    'ownedRecordRemoved': false,
    'baselineRecordsRetained': false,
    'evidenceScope':
        'real-Android-USB-permission-API-with-virtual-USBIP-transport',
    'physicalCableVerified': false,
  };
  developer.registerExtension('ext.connect.usb', (_, args) async {
    final action = args['action'];
    if (args['error'] == 'true') hostFailed = true;
    var valid = true;
    if (action == 'fixture') {
      final incoming = args['runId'];
      valid =
          stage == 'waiting-fixture' &&
          runId == null &&
          incoming != null &&
          RegExp(r'^[0-9a-f]{32}$').hasMatch(incoming);
      if (valid) runId = incoming;
    } else if (action == 'denied' || action == 'granted') {
      final expectedStage = action == 'denied' ? 'need-deny' : 'need-grant';
      valid =
          stage == expectedStage &&
          runId != null &&
          args['runId'] == runId &&
          !acknowledged.contains(action);
      if (valid) acknowledged.add(action!);
    } else if (action != null) {
      valid = false;
    }
    if (!valid) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        'Invalid USB checkpoint action or state.',
      );
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'stage': stage, 'runId': runId}),
    );
  });

  testWidgets('real USB permission denial, retry and retained connection', (
    tester,
  ) async {
    AppController? controller;
    Set<String>? baselineIds;
    final ownedIds = <String>{};
    final originalHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    final page = find.byType(ConnectionFormPage);

    void publish(String next) {
      stage = next;
      binding.reportData!['stage'] = next;
    }

    Future<void> hostReady(bool Function() ready) async {
      await waitFor(
        tester,
        () => ready() || hostFailed,
        timeout: const Duration(seconds: 60),
        reason:
            'The host must acknowledge the real system USB dialog at $stage.',
      );
      expect(hostFailed, isFalse, reason: 'The USB host coordination failed.');
    }

    Future<Json> request(String command, [Json params = const {}]) =>
        controller!
            .request(command, params)
            .timeout(const Duration(seconds: 75));

    Future<List<Json>> devices() async =>
        objects((await request('devices.list'))['devices']);

    Future<void> collectOwned() async {
      if (controller == null || baselineIds == null) return;
      // 隔离夹具是本轮唯一新增 USB 设备；记录精确新 ID，不遗忘基线记录，也不按显示名称删除。
      for (final device in await devices()) {
        final id = value(device, 'id');
        if (id.isNotEmpty &&
            !baselineIds!.contains(id) &&
            device['transport'] == 'usb') {
          ownedIds.add(id);
        }
      }
    }

    Finder button(String label) => find.descendant(
      of: page,
      matching: find.widgetWithText(FilledButton, label),
    );

    Future<void> tapButton(String label) async {
      final target = button(label);
      await tester.scrollUntilVisible(
        target,
        180,
        scrollable: find
            .descendant(of: page, matching: find.byType(Scrollable))
            .first,
        maxScrolls: 12,
      );
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 200));
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pump();
    }

    try {
      await app.main();
      await waitFor(
        tester,
        () => find.byTooltip('添加设备').evaluate().isNotEmpty,
        reason: 'The ordinary production bootstrap must initialize Rust.',
      );
      controller = ProviderScope.containerOf(
        tester.element(find.byType(ConnectApp)),
      ).read(appControllerProvider.notifier);
      baselineIds = (await devices()).map((d) => value(d, 'id')).toSet();
      await hostReady(() => runId != null);
      binding.reportData!['fixtureRunId'] = runId;
      await tester.tap(find.byTooltip('添加设备'));
      await waitFor(
        tester,
        () =>
            page.evaluate().length == 1 &&
            ModalRoute.of(tester.element(page))?.animation?.status ==
                AnimationStatus.completed,
        reason: 'The real add-device form must open.',
      );
      final usbTab = find.descendant(of: page, matching: find.text('USB'));
      expect(usbTab, findsOneWidget);
      await tester.tap(usbTab);
      await tester.pump();
      expect(find.byType(UsbGuidePage), findsOneWidget);

      publish('need-deny');
      await tapButton('检查连接');
      await hostReady(() => acknowledged.contains('denied'));
      await waitFor(
        tester,
        () =>
            find
                    .descendant(
                      of: page,
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is StateNote &&
                            widget.message == '尚未允许主控应用访问 USB 设备。',
                      ),
                    )
                    .evaluate()
                    .length ==
                1 &&
            button('检查连接').evaluate().length == 1,
        timeout: const Duration(seconds: 15),
        reason:
            'System Cancel must return a localized denial, not hang checking.',
      );
      expect(find.text('正在检查…'), findsNothing);
      expect(tester.widget<FilledButton>(button('检查连接')).onPressed, isNotNull);
      expect((await devices()).map((d) => value(d, 'id')).toSet(), baselineIds);
      binding.reportData!['systemDenialReturned'] = true;
      binding.reportData!['denialRetryAvailable'] = true;

      publish('need-grant');
      await tapButton('检查连接');
      await hostReady(() => acknowledged.contains('granted'));
      await waitFor(
        tester,
        () => button('打开设备工作台').evaluate().length == 1,
        timeout: const Duration(seconds: 75),
        reason: 'System OK must admit the actual USB ADB connection.',
      );
      binding.reportData!['systemGrantReturned'] = true;
      await collectOwned();
      expect(
        ownedIds,
        hasLength(1),
        reason: 'Use a fixture without a preexisting target record.',
      );
      final id = ownedIds.single;
      final connected = await request('device.info', {'deviceId': id});
      expect(connected['transport'], 'usb');
      expect(connected['status'], 'connected');
      // device.info 是存储记录，devices.list 增加当前活动连接投影；后续探测全部绑定此精确 ID。
      final live = (await devices()).singleWhere(
        (device) => device['id'] == id,
      );
      expect(live['transport'], 'usb');
      expect(live['status'], 'connected');
      final connectionId = value(live, 'connectionId');
      expect(connectionId, isNotEmpty);
      await tapButton('打开设备工作台');
      await waitFor(
        tester,
        () => find.byType(DeviceWorkspacePage).evaluate().length == 1,
        reason: 'The real USB result action must open its device workspace.',
      );
      expect(
        tester
            .widget<DeviceWorkspacePage>(find.byType(DeviceWorkspacePage))
            .device['id'],
        id,
      );
      binding.reportData!['usbWorkspaceOpened'] = true;

      // devices.usb 的 finally 释放 Java UsbDeviceConnection 租约后才返回；此后新查询经已准入且归 Rust 所有的连接执行真实 shell、同步和包探测。
      final result = await request('device.capabilities', {'deviceId': id});
      expect(result['deviceId'], id);
      expect(result['connectionId'], connectionId);
      final capabilities = objects(result['capabilities']);
      for (final key in ['shell', 'files']) {
        expect(
          capabilities.singleWhere((c) => c['key'] == key)['status'],
          'available',
        );
      }
      expect(
        (await devices()).singleWhere(
          (device) => device['id'] == id,
        )['connectionId'],
        connectionId,
      );
      binding.reportData!['postLeaseShellVerified'] = true;
      binding.reportData!['postLeaseFilesVerified'] = true;
      expect(tester.takeException(), isNull);
    } catch (error, stack) {
      binding.reportData!['failedStage'] = stage;
      binding.reportData!['failureType'] = '${error.runtimeType}';
      binding.reportData!['failureLocations'] = stack
          .toString()
          .split('\n')
          .where((line) => line.contains('usb_connection_test.dart'))
          .take(3)
          .toList();
      rethrow;
    } finally {
      publish('cleanup');
      try {
        await collectOwned();
        for (final id in ownedIds) {
          expect(baselineIds!.contains(id), isFalse);
          await request('devices.forget', {'deviceId': id});
        }
        if (controller != null && baselineIds != null) {
          final remaining = (await devices())
              .map((d) => value(d, 'id'))
              .toSet();
          expect(remaining.intersection(ownedIds), isEmpty);
          expect(remaining.containsAll(baselineIds), isTrue);
          binding.reportData!['ownedRecordRemoved'] = ownedIds.isNotEmpty;
          binding.reportData!['baselineRecordsRetained'] = true;
        }
      } finally {
        WidgetController.hitTestWarningShouldBeFatal = originalHitTestPolicy;
        publish('done');
      }
    }
    for (final key in [
      'systemDenialReturned',
      'denialRetryAvailable',
      'systemGrantReturned',
      'usbWorkspaceOpened',
      'postLeaseShellVerified',
      'postLeaseFilesVerified',
      'ownedRecordRemoved',
      'baselineRecordsRetained',
    ]) {
      expect(
        binding.reportData![key],
        isTrue,
        reason: '$key requires real evidence.',
      );
    }
    binding.reportData!['usbConnectionComplete'] = true;
  });
}
