import 'dart:async';
import 'dart:io';

import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:adb/adb.dart' show AdbCancellation;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/connection_validation.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

import 'models/wireless_setup_state.dart';

part 'wireless_setup_notifier.g.dart';

/// 持有本页读取、确认与切换意图；系统切换和回收仍归核心设置能力。
@riverpod
class WirelessSetupNotifier extends _$WirelessSetupNotifier {
  late _WirelessSetupOwner _owner;

  @override
  WirelessSetupState build({required String deviceId, required Object scope}) {
    final owner = _owner = _WirelessSetupOwner(
      ref.watch(deviceInspectionProvider),
      ref.watch(deviceSetupProvider),
      ref.watch(deviceManagementProvider),
      ref.watch(deviceReaderProvider),
    );
    ref.onDispose(owner.dispose);
    scheduleMicrotask(() {
      if (_current(owner)) unawaited(refresh());
    });
    return const WirelessSetupState();
  }

  bool _current(_WirelessSetupOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(_owner, owner) &&
      identical(ref.read(deviceInspectionProvider), owner.inspection) &&
      identical(ref.read(deviceSetupProvider), owner.setup) &&
      identical(ref.read(deviceManagementProvider), owner.management) &&
      identical(ref.read(deviceReaderProvider), owner.reader);

  bool _accepts(_WirelessSetupOwner owner, _WirelessSwitch attempt) =>
      _current(owner) && identical(owner.attempt, attempt) && attempt.accepting;

  Future<void> refresh() async {
    final owner = _owner;
    if (!_current(owner) || owner.attempt != null) return;
    owner.reading?.cancel();
    final reading = owner.reading = AdbCancellation();
    state = state.copyWith(phase: .reading, error: null);
    try {
      final network = await _readNetwork(owner, reading);
      if (!_current(owner) || !identical(owner.reading, reading)) return;
      state = state.copyWith(
        phase: .idle,
        addresses: _addresses(network.value),
      );
    } catch (error) {
      if (_current(owner) && identical(owner.reading, reading)) {
        state = state.copyWith(
          phase: .failed,
          addresses: [],
          error: failureMessage(error, fallback: '无法找到手机的网络地址。请确认手机已连上 Wi-Fi。'),
        );
      }
    } finally {
      if (identical(owner.reading, reading)) owner.reading = null;
    }
  }

  Future<WirelessSwitchRequest?> prepare({
    required String address,
    required int port,
  }) async {
    final owner = _owner;
    if (!_current(owner) || owner.attempt != null || state.loading) return null;
    owner.reading?.cancel();
    final attempt = owner.attempt = _WirelessSwitch(
      'ip-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(owner)}-${owner.next++}',
    );
    state = state.copyWith(
      phase: .preparing,
      confirmation: null,
      result: null,
      error: null,
      notice: null,
    );
    try {
      if (validatePort('$port') != null) {
        throw const RequestFailure('invalid_port', '请输入有效的连接端口。');
      }
      final network = await _readNetwork(owner, attempt.reading);
      if (!_accepts(owner, attempt)) return null;
      final addresses = _addresses(network.value);
      if (!addresses.any((item) => item.address == address)) {
        owner.attempt = null;
        state = state.copyWith(
          phase: .idle,
          addresses: addresses,
          notice: '目标设备的网络地址已变化，请重新选择。',
        );
        return null;
      }
      final request = attempt.request = WirelessSwitchRequest(
        attemptId: attempt.id,
        deviceId: deviceId,
        connectionId: network.connectionId!,
        address: address,
        port: port,
      );
      state = state.copyWith(
        phase: .confirming,
        addresses: addresses,
        confirmation: request,
      );
      return request;
    } catch (error) {
      if (_accepts(owner, attempt)) {
        owner.attempt = null;
        state = state.copyWith(
          phase: .failed,
          addresses: [],
          error: failureMessage(error, fallback: '无法读取手机的网络地址。请检查 USB 连接。'),
        );
      }
      return null;
    }
  }

  void dismiss(WirelessSwitchRequest request) {
    final owner = _owner;
    final attempt = owner.attempt;
    if (!_current(owner) ||
        attempt == null ||
        attempt.requested ||
        !identical(attempt.request, request)) {
      return;
    }
    attempt.accepting = false;
    attempt.reading.cancel();
    owner.attempt = null;
    state = state.copyWith(phase: .idle, confirmation: null);
  }

  Future<void> submit(WirelessSwitchRequest request) async {
    final owner = _owner;
    final attempt = owner.attempt;
    if (attempt == null ||
        !_accepts(owner, attempt) ||
        !identical(attempt.request, request) ||
        state.phase != .confirming) {
      return;
    }
    state = state.copyWith(phase: .switching, error: null);
    try {
      final current = await owner.reader.readDevice(deviceId);
      if (!_accepts(owner, attempt)) return;
      _checkConnection(current, request.connectionId);
      attempt.requested = true;
      final result = await owner.setup.enableWireless(
        deviceId,
        request.address,
        port: request.port,
        connectionId: request.connectionId,
        attemptId: request.attemptId,
      );
      if (!_accepts(owner, attempt)) return;
      if (!_matches(result, request) || !result.connected) {
        throw const RequestFailure(
          'ip_switch_unverified',
          '尚未验证原设备的 IP 连接，请检查设备连接状态。',
        );
      }
      owner.attempt = null;
      state = state.copyWith(
        phase: .completed,
        confirmation: null,
        result: result,
      );
      await ref.read(deviceListProvider.notifier).refresh();
    } catch (error) {
      if (!_accepts(owner, attempt)) return;
      final receipt = error is DeviceSetupFailure ? error.receipt : null;
      final known = receipt is WirelessReceipt && _matches(receipt, request)
          ? receipt
          : null;
      final cleanupRequired =
          error is DeviceSetupFailure &&
          error.code == 'setup_cleanup_unconfirmed';
      attempt.accepting = false;
      if (!cleanupRequired) owner.attempt = null;
      state = state.copyWith(
        phase: cleanupRequired ? .cleanupRequired : .failed,
        confirmation: null,
        result: known,
        error: failureMessage(
          error,
          fallback: '无法切换到无线连接。请保持 USB 连接并检查手机的 Wi-Fi。',
        ),
        notice: attempt.requested ? '设备记录未确认更新，调试服务可能已重启，请核对连接状态。' : null,
      );
      await ref.read(deviceListProvider.notifier).refresh();
    }
  }

  Future<void> cancel() async {
    final owner = _owner;
    final attempt = owner.attempt;
    if (!_current(owner) || attempt == null) return;
    if (attempt.cancellation case final pending?) return pending;
    attempt.accepting = false;
    attempt.reading.cancel();
    state = state.copyWith(phase: .cancelling, confirmation: null);
    final pending = Future<void>.microtask(() => _cancel(owner, attempt));
    attempt.cancellation = pending;
    await pending;
  }

  Future<void> _cancel(
    _WirelessSetupOwner owner,
    _WirelessSwitch attempt,
  ) async {
    try {
      if (attempt.requested) {
        await owner.management.cancelConnectionAttempt(attempt.id);
      }
      if (!_current(owner) || !identical(owner.attempt, attempt)) return;
      owner.attempt = null;
      state = state.copyWith(
        phase: .cancelled,
        error: null,
        notice: attempt.requested ? '已取消切换。调试服务可能已重启，请核对当前连接状态。' : '已取消本次切换。',
      );
      await ref.read(deviceListProvider.notifier).refresh();
    } catch (error) {
      if (_current(owner) && identical(owner.attempt, attempt)) {
        state = state.copyWith(
          phase: .cleanupRequired,
          error: failureMessage(error, fallback: '暂时无法取消连接。请点「重试取消」。'),
        );
      }
    } finally {
      attempt.cancellation = null;
    }
  }

  Future<DeviceReading<DeviceNetworkInfo>> _readNetwork(
    _WirelessSetupOwner owner,
    AdbCancellation cancellation,
  ) async {
    final current = await owner.reader.readDevice(deviceId);
    _checkRead(owner, cancellation);
    _checkConnection(current);
    final network = await owner.inspection.readNetwork(
      deviceId,
      connectionId: current.connectionId,
      cancellation: cancellation,
    );
    _checkRead(owner, cancellation);
    final latest = await owner.reader.readDevice(deviceId);
    _checkRead(owner, cancellation);
    _checkConnection(latest, current.connectionId);
    if (network.deviceId != deviceId ||
        network.stale ||
        network.connectionId != current.connectionId) {
      throw const RequestFailure('connection_changed', '设备连接已变化，请重新获取地址。');
    }
    return network;
  }

  void _checkRead(_WirelessSetupOwner owner, AdbCancellation cancellation) {
    if (!_current(owner) || cancellation.isCancelled) {
      throw const RequestFailure('cancelled', '本次地址读取已结束。');
    }
  }

  void _checkConnection(DeviceSnapshot device, [String? connectionId]) {
    if (device.id != deviceId ||
        device.status != .connected ||
        (device.connectionId ?? '').isEmpty ||
        (connectionId != null && device.connectionId != connectionId)) {
      throw const RequestFailure('connection_changed', '设备连接已变化，请重新获取地址。');
    }
  }
}

List<DeviceNetworkAddress> _addresses(DeviceNetworkInfo network) {
  final addresses = <String, DeviceNetworkAddress>{};
  for (final item in network.addresses) {
    if (item.address.isNotEmpty &&
        validateAddress(item.address) == null &&
        InternetAddress.tryParse(item.address.split('%').first) != null) {
      addresses.putIfAbsent(item.address, () => item);
    }
  }
  return addresses.values.toList(growable: false);
}

bool _matches(WirelessReceipt receipt, WirelessSwitchRequest request) =>
    receipt.deviceId == request.deviceId &&
    receipt.address == request.address &&
    receipt.port == request.port &&
    (receipt.connection == null ||
        receipt.connection!.deviceId == request.deviceId);

final class _WirelessSetupOwner {
  _WirelessSetupOwner(
    this.inspection,
    this.setup,
    this.management,
    this.reader,
  );
  final DeviceInspection inspection;
  final DeviceSetup setup;
  final DeviceManagement management;
  final DeviceReader reader;
  AdbCancellation? reading;
  _WirelessSwitch? attempt;
  bool disposed = false;
  int next = 0;

  void dispose() {
    disposed = true;
    reading?.cancel();
    final pending = attempt;
    if (pending == null) return;
    pending.accepting = false;
    pending.reading.cancel();
    if (pending.requested && pending.cancellation == null) {
      management.cancelConnectionAttempt(pending.id).ignore();
    }
  }
}

final class _WirelessSwitch {
  _WirelessSwitch(this.id);
  final String id;
  final reading = AdbCancellation();
  WirelessSwitchRequest? request;
  bool requested = false, accepting = true;
  Future<void>? cancellation;
}
