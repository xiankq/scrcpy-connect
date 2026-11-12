import 'dart:async';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/companion/companion_exception.dart';
import 'package:scrcpy_connect/core/content/content_cache_failure.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_disconnect_requested.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/identity/models/setup_identity.dart';

/// 设备操作的跨能力提交顺序；设备、文件和播放器仍持有各自的实际资源与失败重试。
final class DeviceActions
    implements DeviceManagement, DeviceConnectionControl, DeviceSetup {
  DeviceActions({
    required this._devices,
    required this._connections,
    required this._setup,
    required this._isStateUnverified,
    required this._prepareChange,
    required this._beginChange,
    required this._cancelContent,
    required this._cancelUsbAttempt,
    required this._cancelFiles,
    required this._forgetObservation,
    required this._forgetPreferences,
    required this._stopMediaIntent,
    required this._finishMediaStop,
    required this._onDisconnectRequested,
    required this._isDisposed,
    this.diagnostics,
  });

  final DeviceManagement _devices;
  final DeviceConnectionControl _connections;
  final DeviceSetup Function() _setup;
  final bool Function() _isStateUnverified;
  final Future<void> Function(ConnectionChange change) _prepareChange;
  final Future<void> Function() Function(ConnectionChange change) _beginChange;
  final Future<void> Function(String deviceId) _cancelContent;
  final Future<void> Function(String attemptId) _cancelUsbAttempt;
  final Future<void> Function(String deviceId) _cancelFiles;
  final Future<void> Function(String deviceId) _forgetObservation;
  final Future<void> Function(String deviceId) _forgetPreferences;
  final void Function(String deviceId) _stopMediaIntent;
  final Future<void> Function(String deviceId) _finishMediaStop;
  final void Function(DeviceDisconnectRequested) _onDisconnectRequested;
  final bool Function() _isDisposed;
  final DiagnosticReporter? diagnostics;
  final _pendingChanges = <_PendingConnectionChange>{};

  @override
  Future<List<DiscoveredDevice>> discoverDevices({
    String? attemptId,
    AdbCancellation? cancellation,
  }) => _execute(() {
    cancellation?.check();
    return _setup().discoverDevices(
      attemptId: attemptId,
      cancellation: cancellation,
    );
  });

  @override
  Future<PairingReceipt> pairDevice(
    String address,
    int port,
    String code, {
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) => _setupAction(
    'devices.pair',
    () => _setup().pairDevice(
      address,
      port,
      code,
      deviceId: deviceId,
      attemptId: attemptId,
      identity: identity,
    ),
    deviceId: deviceId,
    attemptId: attemptId,
  );

  @override
  Future<QrPairingSession> beginQrPairing({
    String? deviceId,
    String? attemptId,
    SetupIdentity? identity,
  }) => _setupAction(
    'devices.pair.qr',
    () => _setup().beginQrPairing(
      deviceId: deviceId,
      attemptId: attemptId,
      identity: identity,
    ),
    deviceId: deviceId,
    attemptId: attemptId,
  );

  @override
  Future<UsbSetupResult> connectUsb({
    String? deviceId,
    String? attemptId,
    String? serial,
    String? usbDeviceId,
    bool connect = false,
    SetupIdentity? identity,
  }) => _setupAction(
    'devices.usb',
    () => _setup().connectUsb(
      deviceId: deviceId,
      attemptId: attemptId,
      serial: serial,
      usbDeviceId: usbDeviceId,
      connect: connect,
      identity: identity,
    ),
    deviceId: deviceId,
    attemptId: attemptId,
  );

  @override
  Future<WirelessReceipt> enableWireless(
    String deviceId,
    String address, {
    int port = 5555,
    String? attemptId,
  }) => _setupAction(
    'devices.wireless',
    () => _setup().enableWireless(
      deviceId,
      address,
      port: port,
      attemptId: attemptId,
    ),
    deviceId: deviceId,
    attemptId: attemptId,
    address: address,
  );

  Future<T> _setupAction<T>(
    String diagnosticLabel,
    Future<T> Function() action, {
    String? deviceId,
    String? attemptId,
    String? address,
  }) async {
    _checkOpen();
    for (final value in [?deviceId, ?attemptId, ?address]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw const RequestFailure('invalid_argument', '连接参数无效。');
      }
    }
    if (_isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    return _change(
      ConnectionChange(.setup, deviceId: deviceId, attemptId: attemptId),
      () async {
        final watch = Stopwatch()..start();
        try {
          final result = await _execute(action);
          diagnostics?.deviceSetup(
            diagnosticLabel,
            deviceId,
            watch.elapsedMilliseconds,
          );
          return result;
        } catch (error) {
          diagnostics?.deviceSetup(
            diagnosticLabel,
            deviceId,
            watch.elapsedMilliseconds,
            error: error,
          );
          rethrow;
        }
      },
    );
  }

  @override
  Future<DeviceConnectionReceipt> connectDevice(
    String deviceId, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) => _connect(
    deviceId,
    attemptId,
    cancellation,
    configuring: false,
    action: () => _connections.connectDevice(
      deviceId,
      attemptId: attemptId,
      candidateSource: candidateSource,
      cancellation: cancellation,
    ),
  );

  @override
  Future<DeviceConnectionReceipt> configureDevice(
    String deviceId,
    DeviceEndpoint endpoint, {
    String? attemptId,
    ConnectionCandidateSource candidateSource = .saved,
    AdbCancellation? cancellation,
  }) => _connect(
    deviceId,
    attemptId,
    cancellation,
    configuring: true,
    endpoint: endpoint,
    action: () => _connections.configureDevice(
      deviceId,
      endpoint,
      attemptId: attemptId,
      candidateSource: candidateSource,
      cancellation: cancellation,
    ),
  );

  Future<DeviceConnectionReceipt> _connect(
    String deviceId,
    String? attemptId,
    AdbCancellation? cancellation, {
    required bool configuring,
    required Future<DeviceConnectionReceipt> Function() action,
    DeviceEndpoint? endpoint,
  }) async {
    _checkOpen();
    // 保留入口拒绝顺序：未受理的请求不能撤销已有设置或重连尝试。
    for (final value in [deviceId, ?attemptId, ?endpoint?.address]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw const RequestFailure('invalid_argument', '连接参数无效。');
      }
    }
    if (_isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    if (cancellation?.isCancelled == true) {
      throw const RequestFailure('cancelled', '本次设备操作已取消。');
    }
    return _change(
      ConnectionChange(
        configuring ? .configure : .connect,
        deviceId: deviceId,
        attemptId: attemptId,
      ),
      () async {
        final watch = Stopwatch()..start();
        try {
          final receipt = await _execute(action);
          if (!configuring) {
            diagnostics?.deviceConnected(deviceId, watch.elapsedMilliseconds);
          }
          return receipt;
        } catch (error) {
          diagnostics?.deviceConnectionFailed(
            deviceId,
            configuring: configuring,
            elapsedMs: watch.elapsedMilliseconds,
            error: error,
          );
          rethrow;
        }
      },
    );
  }

  @override
  Future<DeviceSnapshot> addDevice(
    DeviceEndpoint endpoint, {
    String name = 'Android 设备',
    SetupIdentity? identity,
    AdbCancellation? cancellation,
  }) => _saveRecord(
    () => _devices.addDevice(
      endpoint,
      name: name,
      identity: identity,
      cancellation: cancellation,
    ),
  );

  @override
  Future<DeviceSnapshot> updateDeviceEndpoint(
    String deviceId,
    DeviceEndpoint endpoint, {
    AdbCancellation? cancellation,
  }) => _saveRecord(
    () => _devices.updateDeviceEndpoint(
      deviceId,
      endpoint,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
  );

  Future<DeviceSnapshot> _saveRecord(
    Future<DeviceSnapshot> Function() save, {
    String? deviceId,
  }) async {
    _checkOpen();
    final watch = Stopwatch()..start();
    try {
      return await _execute(save);
    } catch (error) {
      diagnostics?.deviceRecordFailed(
        deviceId,
        error,
        watch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  @override
  Future<void> renameDevice(String id, String name) =>
      _execute(() => _devices.renameDevice(id, name));

  @override
  Future<void> disconnectDevice(String id) => _stop(id, forget: false);

  @override
  Future<void> forgetDevice(String id) => _stop(id, forget: true);

  Future<void> _stop(String id, {required bool forget}) async {
    _checkOpen();
    if (id.isEmpty || id.contains('\u0000')) {
      throw const RequestFailure('invalid_argument', '设备标识无效。');
    }
    _onDisconnectRequested(DeviceDisconnectRequested(id));
    await _change(
      ConnectionChange(ConnectionChangeKind.stop, deviceId: id),
      () async {
        final watch = Stopwatch()..start();
        try {
          await _execute(() async {
            _stopMediaIntent(id);
            await _cancelContent(id);
            await _cancelFiles(id);
            if (forget) {
              await _devices.forgetDevice(id);
              await _forgetObservation(id);
              await _forgetPreferences(id);
            } else {
              await _devices.disconnectDevice(id);
            }
            await _finishMediaStop(id);
          });
          diagnostics?.deviceStopped(
            id,
            forgotten: forget,
            elapsedMs: watch.elapsedMilliseconds,
          );
        } catch (error) {
          diagnostics?.deviceStopped(
            id,
            forgotten: forget,
            elapsedMs: watch.elapsedMilliseconds,
            error: error,
          );
          rethrow;
        }
      },
    );
  }

  @override
  Future<void> cancelConnectionAttempt(String attemptId) async {
    _checkOpen();
    // 操作可能仍在等待旧资源回收，尚未进入设备模块；先撤销该次入口的准入。
    for (final pending in _pendingChanges) {
      if (pending.change.attemptId == attemptId) pending.cancelled = true;
    }
    await _change(
      ConnectionChange(ConnectionChangeKind.cancel, attemptId: attemptId),
      () async {
        final watch = Stopwatch()..start();
        try {
          await _execute(() async {
            await _cancelUsbAttempt(attemptId);
            await _devices.cancelConnectionAttempt(attemptId);
          });
        } catch (error) {
          diagnostics?.deviceCancellationFailed(
            error,
            watch.elapsedMilliseconds,
          );
          rethrow;
        }
      },
    );
  }

  Future<T> _change<T>(
    ConnectionChange change,
    Future<T> Function() action,
  ) async {
    final pending = change.manual ? _PendingConnectionChange(change) : null;
    if (pending != null) _pendingChanges.add(pending);
    try {
      await _prepareChange(change);
      if (pending?.cancelled == true) {
        throw const RequestFailure('cancelled', '本次连接流程已停止。');
      }
      final finish = _beginChange(change);
      try {
        return await action();
      } finally {
        await finish();
      }
    } finally {
      if (pending != null) _pendingChanges.remove(pending);
    }
  }

  void _checkOpen() {
    if (_isDisposed()) throw const RequestFailure('disposed', '应用已关闭。');
  }

  Future<T> _execute<T>(FutureOr<T> Function() action) async {
    _checkOpen();
    try {
      return await action();
    } on ContentCacheFailure catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message),
        stack,
      );
    } on FileFailure catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message),
        stack,
      );
    } on DeviceRecordsFailure catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message, error.details),
        stack,
      );
    } on CompanionException catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message),
        stack,
      );
    } on AdbException catch (error, stack) {
      Error.throwWithStackTrace(
        RequestFailure(error.code, error.message),
        stack,
      );
    }
  }
}

final class _PendingConnectionChange {
  _PendingConnectionChange(this.change);
  final ConnectionChange change;
  bool cancelled = false;
}
