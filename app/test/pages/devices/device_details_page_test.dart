import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/devices/details/device_details_page.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';

void main() {
  testWidgets('设备详情首次读取延迟显示值骨架，刷新时保留已读值', (tester) async {
    const device = DeviceSnapshot(
      id: 'phone',
      status: DeviceConnectionStatus.connected,
      connectionId: 'live',
    );
    final first = Completer<DeviceReading<DeviceDetails>>();
    final refreshed = Completer<DeviceReading<DeviceDetails>>();
    final reads = [first, refreshed];
    var request = 0;
    await _pumpDetails(tester, device, () => reads[request++].future);

    expect(find.text('设备详情'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 149));
    expect(find.byType(SkeletonLine), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(SkeletonLine), findsWidgets);
    final label = find.text('设备型号');
    final placeholderPosition = tester.getCenter(label);
    expect(find.text('未获取'), findsNothing);

    const reading = DeviceReading(
      deviceId: 'phone',
      connectionId: 'live',
      value: DeviceDetails(system: DeviceSystemInfo(model: 'Pixel 8')),
    );
    first.complete(reading);
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonLine), findsNothing);
    expect(tester.getCenter(label), placeholderPosition);
    expect(find.text('Pixel 8'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, AppIcons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.byType(SkeletonLine), findsNothing);
    refreshed.complete(
      reading.copyWith(
        value: const DeviceDetails(system: DeviceSystemInfo(model: 'Pixel 9')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pixel 9'), findsOneWidget);
  });

  testWidgets('device details starts with compact label and value rows', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const device = DeviceSnapshot(
      id: 'phone',
      name: '测试手机',
      status: DeviceConnectionStatus.connected,
      connectionId: 'live',
    );
    await _pumpDetails(
      tester,
      device,
      () => const DeviceReading(
        deviceId: 'phone',
        connectionId: 'live',
        observedAt: 1700000000,
        value: DeviceDetails(
          system: DeviceSystemInfo(model: 'Pixel 8', serial: 'DEMO-0482'),
          battery: DeviceBattery(
            level: 100,
            status: DeviceBatteryStatus.full,
            temperatureC: 30,
          ),
        ),
      ),
    );

    final label = tester.getCenter(find.text('设备型号'));
    final value = tester.getCenter(find.text('Pixel 8'));
    expect(value.dx, greaterThan(label.dx));
    expect(value.dy, closeTo(label.dy, 1));
    expect(
      tester.getCenter(find.text('品牌 / 产品')).dy - label.dy,
      closeTo(50, 1),
    );
    expect(find.text('测试手机'), findsNothing);
    expect(find.text('设备序列号').hitTestable(), findsOneWidget);
    expect(find.text('当前电量').hitTestable(), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('已充满'), findsOneWidget);
    expect(find.text('30 °C'), findsOneWidget);
  });

  testWidgets('narrow dark details wraps long values at large text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(300, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const device = DeviceSnapshot(
      id: 'phone',
      status: DeviceConnectionStatus.offline,
    );
    const model = 'Long Android model name';
    await _pumpDetails(
      tester,
      device,
      () => const DeviceReading(
        deviceId: 'phone',
        stale: true,
        observedAt: 1700000000,
        value: DeviceDetails(system: DeviceSystemInfo(model: model)),
      ),
      brightness: Brightness.dark,
      textScale: 2,
    );

    final note = find.textContaining('最近连接');
    final heading = find.text('设备与系统');
    expect(tester.getCenter(note).dy, lessThan(tester.getCenter(heading).dy));
    expect(tester.getSize(find.text(model)).height, greaterThan(56));
    final lastField = find.text('处理器核心');
    await tester.scrollUntilVisible(lastField, 300);
    await Scrollable.ensureVisible(tester.element(lastField), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(lastField.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDetails(
  WidgetTester tester,
  DeviceSnapshot device,
  FutureOr<DeviceReading<DeviceDetails>> Function() read, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  final details = deviceDetailsProvider(
    device.id,
    connectionId: device.connectionId,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceListProvider.overrideWith(() => _Devices(device)),
        recoveryStateProvider.overrideWith(_Recovery.new),
        details.overrideWith((_) => read()),
      ],
      child: MaterialApp(
        theme: ConnectTokens.theme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: DeviceDetailsPage(device: device),
      ),
    ),
  );
  await tester.pump();
}

class _Devices extends DeviceListNotifier {
  _Devices(this.device);
  final DeviceSnapshot device;

  @override
  DeviceListState build() => DeviceListState(devices: [device], loading: false);
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}
