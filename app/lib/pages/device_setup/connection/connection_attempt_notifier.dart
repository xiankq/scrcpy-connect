import 'dart:async';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';

import 'models/connection_attempt_request.dart';
import 'models/connection_attempt_state.dart';

part 'connection_attempt_notifier.g.dart';

/// 一次手动连接的执行状态；页面持有表单、确认及导航。
@riverpod
class ConnectionAttemptNotifier extends _$ConnectionAttemptNotifier {
  late _ConnectionAttemptOwner _owner;

  @override
  ConnectionAttemptState build({required Object scope}) {
    final owner = _owner = _ConnectionAttemptOwner(
      ref.watch(deviceSetupProvider),
      ref.watch(deviceManagementProvider),
      ref.watch(deviceConnectionsProvider),
    );
    ref.onDispose(owner.dispose);
    return const ConnectionAttemptState();
  }

  bool _current(_ConnectionAttemptOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(_owner, owner) &&
      identical(ref.read(deviceSetupProvider), owner.setup) &&
      identical(ref.read(deviceManagementProvider), owner.management) &&
      identical(ref.read(deviceConnectionsProvider), owner.connections);

  bool _accepts(_ConnectionAttemptOwner owner, _ConnectionAttempt attempt) =>
      _current(owner) && identical(owner.attempt, attempt) && attempt.accepting;

  Future<void> submit(ConnectionAttemptRequest request) async {
    final owner = _owner;
    if (!_current(owner) || owner.attempt != null || !state.canSubmit) return;
    owner.revision++;
    final attempt = owner.attempt = _ConnectionAttempt(
      'connection-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(owner)}-${owner.next++}',
    );
    state = ConnectionAttemptState(
      phase: .submitting,
      deviceId: request.deviceId,
      address: request.address,
    );
    try {
      PairingReceipt? paired;
      DeviceSnapshot? saved;
      String? connectedId;
      switch (request) {
        case PairDeviceRequest(
          :final address,
          :final port,
          :final code,
          :final deviceId,
        ):
          paired = await owner.setup.pairDevice(
            address,
            port,
            code,
            deviceId: deviceId,
            attemptId: attempt.id,
          );
          if (!_accepts(owner, attempt)) return;
          _verifyPairing(paired, deviceId);
        case ConnectDeviceRequest(
          :final endpoint,
          :final deviceId,
          :final configure,
        ):
          if (configure) {
            if (deviceId == null) {
              throw const RequestFailure('missing_device', '请先核对需要配置的设备。');
            }
            final receipt = await owner.connections.configureDevice(
              deviceId,
              endpoint,
              attemptId: attempt.id,
              cancellation: attempt.stop,
            );
            if (!_accepts(owner, attempt)) return;
            _verifyConnection(receipt, deviceId);
            connectedId = receipt.deviceId;
          } else {
            saved = deviceId == null
                ? await owner.management.addDevice(
                    endpoint,
                    cancellation: attempt.stop,
                  )
                : await owner.management.updateDeviceEndpoint(
                    deviceId,
                    endpoint,
                    cancellation: attempt.stop,
                  );
          }
      }
      if (!_accepts(owner, attempt)) return;
      final id =
          connectedId ?? saved?.id ?? paired?.deviceId ?? request.deviceId;
      state = state.copyWith(
        deviceId: id,
        pairing: paired,
        failure: paired?.connectionFailure,
      );
      if (saved case final device?
          when device.id.isNotEmpty && device.status != .connected) {
        final receipt = await owner.connections.connectDevice(
          device.id,
          attemptId: attempt.id,
          cancellation: attempt.stop,
        );
        if (!_accepts(owner, attempt)) return;
        _verifyConnection(receipt, device.id);
      }
      if (!_accepts(owner, attempt)) return;
      await ref.read(deviceListProvider.notifier).refresh();
      if (!_accepts(owner, attempt)) return;
      final connected = ref
          .read(deviceListProvider)
          .devices
          .where((device) => device.id == id && device.status == .connected)
          .firstOrNull;
      state = state.copyWith(connectedDeviceId: connected?.id);
    } catch (error) {
      if (!_accepts(owner, attempt)) return;
      PairingReceipt? known;
      if (error case DeviceSetupFailure(receipt: PairingReceipt receipt)) {
        if (request.deviceId == null || receipt.deviceId == request.deviceId) {
          known = receipt;
        }
      }
      state = state.copyWith(
        failure: _issue(error),
        pairing: known ?? state.pairing,
        deviceId: known?.deviceId ?? state.deviceId,
      );
    } finally {
      if (_accepts(owner, attempt)) {
        if (_unconfirmed(state.failure)) {
          state = state.copyWith(phase: .cleanupRequired);
        } else {
          owner.attempt = null;
          state = state.copyWith(phase: .settled);
        }
      }
    }
  }

  void _verifyPairing(PairingReceipt paired, String? deviceId) {
    if (deviceId != null && paired.deviceId != deviceId ||
        paired.connection != null &&
            paired.connection!.deviceId != paired.deviceId) {
      throw const RequestFailure(
        'configuration_unverified',
        '尚未核验原设备的连接配置，请重新检查。',
      );
    }
  }

  void _verifyConnection(DeviceConnectionReceipt receipt, String deviceId) {
    if (receipt.deviceId != deviceId || receipt.device.status != .connected) {
      throw const RequestFailure(
        'configuration_unverified',
        '尚未核验原设备的连接配置，请重新检查。',
      );
    }
  }

  Future<bool> cancel() {
    final owner = _owner;
    if (!_current(owner)) return Future.value(false);
    final attempt = owner.attempt;
    if (attempt?.cancellation case final pending?) return pending;
    owner.revision++;
    if (attempt == null) {
      if (state.checking) state = state.copyWith(phase: .settled);
      return Future.value(true);
    }
    attempt.accepting = false;
    attempt.stop.cancel();
    state = state.copyWith(phase: .cancelling, connectedDeviceId: null);
    return attempt.cancellation = _drain(owner, attempt);
  }

  Future<bool> _drain(
    _ConnectionAttemptOwner owner,
    _ConnectionAttempt attempt,
  ) async {
    try {
      await owner.management.cancelConnectionAttempt(attempt.id);
      if (!_current(owner) || !identical(owner.attempt, attempt)) return false;
      owner.attempt = null;
      state = state.copyWith(
        phase: .settled,
        failure: null,
        notice: state.pairing?.recorded == true
            ? '已取消连接，手机上的配对授权已保留。'
            : '已取消本次尝试。',
      );
      await ref.read(deviceListProvider.notifier).refresh();
      return _current(owner);
    } catch (error) {
      if (_current(owner) && identical(owner.attempt, attempt)) {
        state = state.copyWith(
          phase: .cleanupRequired,
          failure: SetupIssue('result_unknown', '取消结果尚未确认，请重新核对。$error'),
        );
      }
      return false;
    } finally {
      attempt.cancellation = null;
    }
  }

  Future<bool> reset() async {
    final owner = _owner;
    if (!await cancel() || !_current(owner) || owner.attempt != null) {
      return false;
    }
    state = const ConnectionAttemptState();
    return true;
  }

  void clearFeedback() {
    if (!_current(_owner) || _owner.attempt != null || !state.canSubmit) return;
    state = state.copyWith(
      pairing: null,
      failure: null,
      notice: null,
      connectedDeviceId: null,
    );
  }

  Future<void> recheck() async {
    final owner = _owner;
    if (!_current(owner) || state.busy || state.cancelling || state.checking) {
      return;
    }
    final revision = ++owner.revision;
    final reconcile = ref.read(reconcileStateProvider);
    bool ownsCheck() => _current(owner) && owner.revision == revision;
    bool current() =>
        ownsCheck() && identical(ref.read(reconcileStateProvider), reconcile);
    state = state.copyWith(phase: .checking);
    try {
      await reconcile();
      if (!current()) return;
      await ref.read(deviceListProvider.notifier).refresh();
      if (!current()) return;
      final connected = ref
          .read(deviceListProvider)
          .devices
          .where(
            (device) =>
                device.id == state.deviceId && device.status == .connected,
          )
          .firstOrNull;
      state = state.copyWith(connectedDeviceId: connected?.id);
    } catch (error) {
      if (current()) state = state.copyWith(failure: _issue(error));
    } finally {
      if (ownsCheck()) {
        state = state.copyWith(
          phase: owner.attempt == null ? .settled : .cleanupRequired,
        );
      }
    }
  }

  SetupIssue _issue(Object error) => SetupIssue(
    error is RequestFailure ? error.code : 'request_failed',
    '$error',
  );

  bool _unconfirmed(SetupIssue? issue) =>
      issue != null &&
      (issue.code.contains('unknown') ||
          issue.code.contains('unconfirmed') ||
          issue.code == 'configuration_unverified');
}

final class _ConnectionAttemptOwner {
  _ConnectionAttemptOwner(this.setup, this.management, this.connections);
  final DeviceSetup setup;
  final DeviceManagement management;
  final DeviceConnectionControl connections;
  _ConnectionAttempt? attempt;
  int revision = 0, next = 0;
  bool disposed = false;

  void dispose() {
    disposed = true;
    final pending = attempt;
    if (pending == null) return;
    pending.accepting = false;
    pending.stop.cancel();
    if (pending.cancellation == null) {
      management.cancelConnectionAttempt(pending.id).ignore();
    }
  }
}

final class _ConnectionAttempt {
  _ConnectionAttempt(this.id);
  final String id;
  final stop = AdbCancellation();
  bool accepting = true;
  Future<bool>? cancellation;
}
