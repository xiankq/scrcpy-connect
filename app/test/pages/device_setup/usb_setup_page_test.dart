import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/usb_setup_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('离页取消原能力拥有的 USB 尝试，迟到回执不再刷新状态', (tester) async {
    final setup = _Setup();
    final management = _Management();
    final container = ProviderContainer(
      overrides: [
        deviceSetupProvider.overrideWithValue(setup),
        deviceManagementProvider.overrideWithValue(management),
        deviceListProvider.overrideWith(_Devices.new),
      ],
    );
    addTearDown(container.dispose);
    final devices = container.read(deviceListProvider.notifier) as _Devices;
    await tester.pumpWidget(_page(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(setup.attempts, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(management.cancelled, [setup.attempts.single.id]);
    setup.attempts.single.result.complete(
      const UsbSetupResult.selectionRequired([], message: 'retired'),
    );
    await tester.pump();
    expect(devices.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('替换能力后由原能力取消尝试，旧回执不写入新的页面流程', (tester) async {
    final previous = _Setup();
    final previousManagement = _Management();
    final deviceList = deviceListProvider.overrideWith(_Devices.new);
    final container = ProviderContainer(
      overrides: [
        deviceSetupProvider.overrideWithValue(previous),
        deviceManagementProvider.overrideWithValue(previousManagement),
        deviceList,
      ],
    );
    addTearDown(container.dispose);
    final devices = container.read(deviceListProvider.notifier) as _Devices;
    await tester.pumpWidget(_page(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    final replacement = _Setup();
    final replacementManagement = _Management();
    container.updateOverrides([
      deviceSetupProvider.overrideWithValue(replacement),
      deviceManagementProvider.overrideWithValue(replacementManagement),
      deviceList,
    ]);
    await tester.pumpAndSettle();
    expect(previousManagement.cancelled, [previous.attempts.single.id]);
    expect(replacementManagement.cancelled, isEmpty);
    previous.attempts.single.result.complete(
      const UsbSetupResult.selectionRequired([], message: 'retired'),
    );
    await tester.pumpAndSettle();
    expect(find.text('retired'), findsNothing);
    expect(devices.refreshes, 0);
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    replacement.attempts.single.result.complete(
      const UsbSetupResult.selectionRequired([], message: 'current'),
    );
    await tester.pumpAndSettle();
    expect(find.text('current'), findsOneWidget);
    expect(devices.refreshes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _page(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: ConnectTokens.theme(Brightness.light),
    home: const Scaffold(
      body: CustomScrollView(slivers: [UsbSetupPage(embedded: true)]),
    ),
  ),
);

class _Setup implements DeviceSetup {
  final attempts = <({String id, Completer<UsbSetupResult> result})>[];
  @override
  Future<UsbSetupResult> connectUsb({
    String? deviceId,
    String? attemptId,
    String? serial,
    String? usbDeviceId,
    bool connect = false,
    SetupIdentity? identity,
  }) {
    final result = Completer<UsbSetupResult>();
    attempts.add((id: attemptId!, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Management implements DeviceManagement {
  final cancelled = <String>[];
  @override
  Future<void> cancelConnectionAttempt(String id) async => cancelled.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices extends DeviceListNotifier {
  int refreshes = 0;
  @override
  DeviceListState build() => DeviceListState(loading: false);
  @override
  Future<void> refresh() async => refreshes++;
}
