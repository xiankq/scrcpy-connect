import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_actions.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_disconnect_requested.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

void main() {
  test('停止意图在排空前交付，精确设备释放仍须等待，非法身份不撤销任何意图', () async {
    final devices = _Devices();
    final prepared = Completer<void>();
    final order = <String>[];
    final requested = <DeviceDisconnectRequested>[];
    final actions = _actions(
      devices,
      (_) {
        order.add('drain');
        return prepared.future;
      },
      onDisconnectRequested: (event) {
        order.add('request');
        requested.add(event);
      },
    );
    await expectLater(
      actions.disconnectDevice(''),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'invalid_argument'),
      ),
    );
    expect(order, isEmpty);
    var completed = false;
    final pending = actions
        .disconnectDevice('device')
        .then((_) => completed = true);
    expect(requested.single.deviceId, 'device');
    expect(order, ['request', 'drain']);
    expect(devices.disconnected, isEmpty);
    expect(completed, isFalse);
    prepared.complete();
    await pending;
    expect(devices.disconnected, ['device']);
    expect(completed, isTrue);
  });

  test('等待旧资源回收的 USB、二维码与直接连接，取消后不再提交执行', () async {
    for (final kind in ['usb', 'qr', 'connect']) {
      final prepared = Completer<void>();
      final devices = _Devices();
      final actions = _actions(devices, (change) async {
        if (change.manual) await prepared.future;
      });
      final Future<Object?> pending = switch (kind) {
        'usb' => actions.connectUsb(attemptId: 'attempt'),
        'qr' => actions.beginQrPairing(attemptId: 'attempt'),
        _ => actions.connectDevice('device', attemptId: 'attempt'),
      };
      final cancelled = expectLater(
        pending,
        throwsA(
          isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await actions.cancelConnectionAttempt('attempt');
      expect(devices.cancelled, ['attempt']);
      prepared.complete();
      await cancelled;
      expect(devices.executed, isEmpty, reason: kind);
    }
  });

  test('取消清理失败仍阻止原提交，后续独立尝试不受污染', () async {
    final prepared = Completer<void>();
    final devices = _Devices()..cancelFailure = StateError('cleanup failed');
    final actions = _actions(devices, (change) async {
      if (change.manual) await prepared.future;
    });
    final old = actions.connectUsb(attemptId: 'old');
    final retired = expectLater(
      old,
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    final next = actions.connectUsb(attemptId: 'next');
    await expectLater(actions.cancelConnectionAttempt('old'), throwsStateError);
    prepared.complete();
    await retired;
    await next;
    expect(devices.executed, ['next']);
    devices.cancelFailure = null;
    await actions.cancelConnectionAttempt('old');
    expect(devices.cancelled, ['old', 'old']);
  });

  test('记录修改、空取消和已撤销发现不取得配对执行能力', () async {
    final devices = _Devices();
    final actions = _actions(
      devices,
      (_) async {},
      setup: () => throw StateError('此操作不应取得配对执行能力'),
    );
    await actions.renameDevice('device', 'Phone');
    await actions.cancelConnectionAttempt('unused');
    await expectLater(
      actions.discoverDevices(cancellation: AdbCancellation()..cancel()),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(devices.cancelled, ['unused']);
  });
}

DeviceActions _actions(
  _Devices devices,
  Future<void> Function(ConnectionChange) prepare, {
  DeviceSetup Function()? setup,
  void Function(DeviceDisconnectRequested)? onDisconnectRequested,
}) => DeviceActions(
  devices: devices,
  connections: devices,
  setup: setup ?? () => devices,
  isStateUnverified: () => false,
  prepareChange: prepare,
  beginChange: (_) => () async {},
  cancelContent: (_) async {},
  cancelUsbAttempt: (_) async {},
  cancelFiles: (_) async {},
  forgetObservation: (_) async {},
  forgetPreferences: (_) async {},
  stopMediaIntent: (_) {},
  finishMediaStop: (_) async {},
  onDisconnectRequested: onDisconnectRequested ?? (_) {},
  isDisposed: () => false,
);

final class _Devices
    implements DeviceManagement, DeviceConnectionControl, DeviceSetup {
  final executed = <String>[];
  final cancelled = <String>[];
  final disconnected = <String>[];
  Object? cancelFailure;

  @override
  Future<void> renameDevice(String id, String name) async {}

  @override
  Future<void> disconnectDevice(String deviceId) async =>
      disconnected.add(deviceId);

  @override
  Future<void> cancelConnectionAttempt(String attemptId) async {
    cancelled.add(attemptId);
    if (cancelFailure case final failure?) throw failure;
  }

  @override
  Future<UsbSetupResult> connectUsb({
    String? deviceId,
    String? attemptId,
    String? serial,
    String? usbDeviceId,
    bool connect = false,
    SetupIdentity? identity,
  }) async {
    executed.add(attemptId!);
    return const UsbSetupResult.selectionRequired([]);
  }

  @override
  Future<QrPairingSession> beginQrPairing({
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) async {
    executed.add(attemptId!);
    return QrPairingSession(
      attemptId: attemptId,
      payload: 'test',
      expiresAt: DateTime.now(),
      result: Future.value(
        const PairingReceipt(guid: 'guid', address: 'phone'),
      ),
    );
  }

  @override
  Future<DeviceConnectionReceipt> connectDevice(
    String deviceId, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) async {
    executed.add(attemptId!);
    return DeviceConnectionReceipt(device: DeviceSnapshot(id: deviceId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
