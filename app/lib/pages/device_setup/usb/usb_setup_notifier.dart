import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

import 'models/usb_setup_state.dart';

part 'usb_setup_notifier.g.dart';

/// 页面只负责确认与呈现；本次尝试的准入、取消和迟到回执由同一所有者管理。
@riverpod
class UsbSetupNotifier extends _$UsbSetupNotifier {
  late _UsbSetupOwner _owner;

  @override
  UsbSetupState build({String? deviceId, required Object scope}) {
    final owner = _owner = _UsbSetupOwner(
      ref.watch(deviceSetupProvider),
      ref.watch(deviceManagementProvider),
    );
    ref.onDispose(owner.dispose);
    return const UsbSetupState();
  }

  bool _current(_UsbSetupOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(_owner, owner) &&
      identical(ref.read(deviceSetupProvider), owner.setup) &&
      identical(ref.read(deviceManagementProvider), owner.management);

  Future<void> check({String? serial, String? usbDeviceId}) async {
    final owner = _owner;
    if (!_current(owner) || owner.attempt != null) return;
    final attempt = owner.attempt = _UsbAttempt(
      'usb-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(owner)}-${owner.next++}',
    );
    state = const UsbSetupState(phase: .checking);
    bool accepts() =>
        _current(owner) &&
        identical(owner.attempt, attempt) &&
        attempt.accepting;
    try {
      final result = await owner.setup.connectUsb(
        attemptId: attempt.id,
        deviceId: deviceId,
        serial: serial,
        usbDeviceId: usbDeviceId,
        connect: serial != null || usbDeviceId != null,
      );
      if (!accepts()) return;
      if (deviceId != null &&
          result.deviceId != null &&
          result.deviceId != deviceId) {
        throw const RequestFailure(
          'device_identity_mismatch',
          'USB连接结果不属于原设备，请重新检查。',
        );
      }
      owner.attempt = null;
      state = UsbSetupState(phase: .completed, result: result);
      await ref.read(deviceListProvider.notifier).refresh();
    } catch (error) {
      if (!accepts()) return;
      if (error case DeviceSetupFailure(
        code: 'setup_cleanup_unconfirmed',
        :final receipt,
      )) {
        attempt.accepting = false;
        final known = receipt is UsbSetupResult ? receipt : null;
        final matches =
            deviceId == null ||
            known?.deviceId == null ||
            known?.deviceId == deviceId;
        state = UsbSetupState(
          phase: .cleanupRequired,
          result: matches ? known : null,
          message: matches
              ? '上一次 USB 连接还没有完全结束。请先检查当前状态。'
              : '连接到了另一台手机。请检查 USB 线连接的是哪台手机。',
        );
      } else {
        owner.attempt = null;
        state = UsbSetupState(
          phase: .failed,
          message: failureMessage(
            error,
            fallback: '无法通过 USB 连接。请解锁手机，确认 USB 调试已开启。',
          ),
        );
      }
    }
  }

  Future<void> cancel() async {
    final owner = _owner;
    final attempt = owner.attempt;
    if (!_current(owner) || attempt == null) return;
    if (attempt.cancellation case final pending?) return pending;
    // 先停止接纳结果，再等待回收；取消等待期间返回的成功不能覆盖取消状态。
    attempt.accepting = false;
    state = state.copyWith(phase: .cancelling, message: null);
    final pending = _cancel(owner, attempt);
    attempt.cancellation = pending;
    await pending;
  }

  Future<void> _cancel(_UsbSetupOwner owner, _UsbAttempt attempt) async {
    try {
      await owner.management.cancelConnectionAttempt(attempt.id);
      if (!_current(owner) || !identical(owner.attempt, attempt)) return;
      owner.attempt = null;
      state = state.copyWith(phase: .cancelled, message: '检查已取消。');
      await ref.read(deviceListProvider.notifier).refresh();
    } catch (error) {
      if (_current(owner) && identical(owner.attempt, attempt)) {
        state = state.copyWith(
          phase: .cleanupRequired,
          message: failureMessage(error, fallback: '暂时无法取消 USB 检查。请点「重试取消」。'),
        );
      }
    } finally {
      attempt.cancellation = null;
    }
  }
}

final class _UsbSetupOwner {
  _UsbSetupOwner(this.setup, this.management);
  final DeviceSetup setup;
  final DeviceManagement management;
  _UsbAttempt? attempt;
  int next = 0;
  bool disposed = false;

  void dispose() {
    disposed = true;
    final pending = attempt;
    if (pending == null) return;
    pending.accepting = false;
    if (pending.cancellation == null) {
      // 核心模块继续持有尚未释放的资源；离页只结束此处的结果接纳。
      management.cancelConnectionAttempt(pending.id).ignore();
    }
  }
}

final class _UsbAttempt {
  _UsbAttempt(this.id);
  final String id;
  bool accepting = true;
  Future<void>? cancellation;
}
