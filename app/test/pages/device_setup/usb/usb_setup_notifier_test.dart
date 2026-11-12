import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_endpoint.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/usb_setup_notifier.dart';
import 'package:scrcpy_connect/pages/device_setup/usb/models/usb_setup_state.dart';

void main() {
  late _Setup setup;
  late _Management management;
  late ProviderContainer container;
  final scope = Object();
  final provider = usbSetupProvider(deviceId: 'device', scope: scope);
  late UsbSetupNotifier actions;
  late void Function() leave;
  final session = AppSession(initialize: false);
  overrides() => [
    appSessionProvider.overrideWithValue(session),
    deviceSetupProvider.overrideWithValue(setup),
    deviceManagementProvider.overrideWithValue(management),
    deviceReaderProvider.overrideWithValue(management),
  ];
  setUp(() {
    setup = _Setup();
    management = _Management();
    container = ProviderContainer(overrides: overrides());
    final subscription = container.listen(provider, (_, _) {});
    leave = subscription.close;
    actions = container.read(provider.notifier);
  });
  tearDown(() => container.dispose());

  test('取消立即封闭结果准入，迟到成功不覆盖取消或下一次尝试', () async {
    final first = actions.check(serial: 'first');
    await actions.check(serial: 'duplicate');
    expect(setup.calls, hasLength(1));
    final cancel = actions.cancel();
    final sameCancel = actions.cancel();
    expect(management.cancellations, hasLength(1));
    expect(container.read(provider).phase, UsbSetupPhase.cancelling);
    setup.calls.first.result.complete(_connected('device'));
    await first;
    expect(container.read(provider).phase, UsbSetupPhase.cancelling);
    expect(container.read(provider).result, isNull);
    await actions.check(serial: 'too-early');
    expect(setup.calls, hasLength(1));
    management.cancellations.single.result.complete();
    await Future.wait([cancel, sameCancel]);
    expect(container.read(provider).phase, UsbSetupPhase.cancelled);
    final next = actions.check(serial: 'second');
    setup.calls.last.result.complete(
      const UsbSetupResult.selectionRequired([]),
    );
    await next;
    expect(setup.calls.last.id, isNot(setup.calls.first.id));
    expect(container.read(provider).phase, UsbSetupPhase.completed);
  });

  test('取消失败保留原尝试，禁止重发并允许按同一标识重试清理', () async {
    final check = actions.check();
    final cancel = actions.cancel();
    management.cancellations.single.result.completeError(
      StateError('still owned'),
    );
    await cancel;
    expect(container.read(provider).phase, UsbSetupPhase.cleanupRequired);
    expect(container.read(provider).message, contains('still owned'));
    await actions.check();
    expect(setup.calls, hasLength(1));
    final retry = actions.cancel();
    expect(management.cancellations.last.id, setup.calls.single.id);
    management.cancellations.last.result.complete();
    await retry;
    setup.calls.single.result.completeError(StateError('late failure'));
    await check;
    expect(container.read(provider).phase, UsbSetupPhase.cancelled);
  });

  test('换源与离页只取消各自原尝试，旧结果不进入新页面状态', () async {
    final first = actions.check();
    final oldSetup = setup;
    final oldManagement = management;
    setup = _Setup();
    management = _Management();
    container.updateOverrides(overrides());
    await container.pump();
    expect(oldManagement.cancellations.single.id, oldSetup.calls.single.id);
    oldSetup.calls.single.result.complete(_connected('device'));
    oldManagement.cancellations.single.result.complete();
    await first;
    expect(container.read(provider).phase, UsbSetupPhase.idle);
    final next = actions.check();
    leave();
    await container.pump();
    expect(management.cancellations.single.id, setup.calls.single.id);
    setup.calls.single.result.completeError(StateError('retired'));
    management.cancellations.single.result.complete();
    await next;
  });

  test('同一设备的两个页面保持独立尝试，回执必须归属于原设备', () async {
    final otherScope = Object();
    final other = usbSetupProvider(deviceId: 'device', scope: otherScope);
    final subscription = container.listen(other, (_, _) {});
    addTearDown(subscription.close);
    final first = actions.check(serial: 'first');
    expect(container.read(other).phase, UsbSetupPhase.idle);
    final second = container.read(other.notifier).check(serial: 'second');
    expect(setup.calls, hasLength(2));
    setup.calls.first.result.complete(_connected('wrong-device'));
    setup.calls.last.result.complete(_connected('device'));
    await Future.wait([first, second]);
    expect(container.read(provider).phase, UsbSetupPhase.failed);
    expect(container.read(provider).result, isNull);
    expect(container.read(provider).message, contains('不属于原设备'));
    expect(container.read(other).result!.deviceId, 'device');
  });

  test('执行回收失败仍保留已连接事实和原清理责任', () async {
    final check = actions.check(serial: 'device');
    setup.calls.single.result.completeError(
      DeviceSetupFailure(
        'setup_cleanup_unconfirmed',
        'release failed',
        receipt: _connected('device'),
      ),
    );
    await check;
    expect(container.read(provider).phase, UsbSetupPhase.cleanupRequired);
    expect(container.read(provider).result!.connected, isTrue);
    await actions.check();
    expect(setup.calls, hasLength(1));
    final cancel = actions.cancel();
    expect(management.cancellations.single.id, setup.calls.single.id);
    management.cancellations.single.result.complete();
    await cancel;
    expect(container.read(provider).result!.connected, isTrue);
  });
}

UsbSetupResult _connected(String id) => UsbSetupResult.connected(
  DeviceConnectionReceipt(
    device: DeviceSnapshot(id: id, status: .connected),
  ),
);

final class _Setup implements DeviceSetup {
  final calls = <({String id, Completer<UsbSetupResult> result})>[];
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
    calls.add((id: attemptId!, result: result));
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Management implements DeviceManagement, DeviceReader {
  final cancellations = <({String id, Completer<void> result})>[];
  @override
  Future<void> cancelConnectionAttempt(String attemptId) {
    final result = Completer<void>();
    cancellations.add((id: attemptId, result: result));
    return result.future;
  }

  @override
  List<DeviceSnapshot> readDevices() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
