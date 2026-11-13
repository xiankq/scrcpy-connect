import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/wireless/wireless_setup_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('表单核验后先显示确认，接受后提交精确目标并展示真实结果', (tester) async {
    final fixture = _Fixture();
    await fixture.show(tester);
    await fixture.confirm(tester);
    expect(fixture.setup.calls, hasLength(1));
    final call = fixture.setup.calls.single;
    expect(call.connectionId, 'original');
    expect(call.address, '192.0.2.1');
    expect(call.port, 5555);
    call.result.complete(_receipt);
    await tester.pumpAndSettle();
    expect(find.text('已转为 IP 连接'), findsOneWidget);
    expect(fixture.devices._refreshes, 1);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    expect(fixture.management.cancelled, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离页取消本页已确认尝试，迟到成功不再刷新设备列表', (tester) async {
    final fixture = _Fixture();
    await fixture.show(tester);
    await fixture.confirm(tester);
    final call = fixture.setup.calls.single;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.management.cancelled, [call.attemptId]);
    call.result.complete(_receipt);
    await tester.pumpAndSettle();
    expect(fixture.devices._refreshes, 0);
    expect(tester.takeException(), isNull);
  });
}

const _device = DeviceSnapshot(
  id: 'device',
  status: .connected,
  connectionId: 'original',
);
final _receipt = WirelessReceipt(
  deviceId: 'device',
  address: '192.0.2.1',
  port: 5555,
  connection: DeviceConnectionReceipt(
    device: _device.copyWith(connectionId: 'tcp'),
  ),
);

final class _Fixture {
  final setup = _Setup();
  final management = _Management();
  late ProviderContainer container;
  _Devices get devices =>
      container.read(deviceListProvider.notifier) as _Devices;

  Future<void> show(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(AppSession(initialize: false)),
        deviceSetupProvider.overrideWithValue(setup),
        deviceManagementProvider.overrideWithValue(management),
        deviceInspectionProvider.overrideWithValue(_Inspection()),
        deviceReaderProvider.overrideWithValue(_Reader()),
        deviceListProvider.overrideWith(_Devices.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: const WirelessSetupPage(device: _device),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    expect(find.text('192.0.2.1 · wlan0'), findsOneWidget);
    await tester.ensureVisible(find.text('切换并连接'));
    await tester.tap(find.text('切换并连接'));
    await tester.pumpAndSettle();
    expect(find.text('切换并连接？'), findsOneWidget);
    expect(setup.calls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '切换并连接').last);
    await tester.pumpAndSettle();
  }
}

class _Inspection implements DeviceInspection {
  @override
  Future<DeviceReading<DeviceNetworkInfo>> readNetwork(
    String deviceId, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) async => DeviceReading(
    deviceId: deviceId,
    connectionId: connectionId,
    value: const DeviceNetworkInfo(
      addresses: [
        DeviceNetworkAddress(interface: 'wlan0', address: '192.0.2.1'),
      ],
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Setup implements DeviceSetup {
  final calls =
      <
        ({
          String attemptId,
          String? connectionId,
          String address,
          int port,
          Completer<WirelessReceipt> result,
        })
      >[];
  @override
  Future<WirelessReceipt> enableWireless(
    String deviceId,
    String address, {
    int port = 5555,
    required String connectionId,
    String? attemptId,
  }) {
    final result = Completer<WirelessReceipt>();
    calls.add((
      attemptId: attemptId!,
      connectionId: connectionId,
      address: address,
      port: port,
      result: result,
    ));
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

class _Reader implements DeviceReader {
  @override
  DeviceSnapshot readDevice(String id) => _device;
  @override
  List<DeviceSnapshot> readDevices() => [_device];
}

class _Devices extends DeviceListNotifier {
  var _refreshes = 0;
  @override
  DeviceListState build() =>
      DeviceListState(devices: [_device], loading: false);
  @override
  Future<void> refresh() async => _refreshes++;
}
