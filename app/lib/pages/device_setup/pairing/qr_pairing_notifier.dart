import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

import 'models/qr_pairing_state.dart';

part 'qr_pairing_notifier.g.dart';

@riverpod
class QrPairingNotifier extends _$QrPairingNotifier {
  late _QrPairingOwner _owner;

  @override
  QrPairingState build({String? deviceId, required Object scope}) {
    final owner = _owner = _QrPairingOwner(
      ref.watch(deviceSetupProvider),
      ref.watch(deviceManagementProvider),
    );
    ref.onDispose(owner.dispose);
    return const QrPairingState();
  }

  bool _current(_QrPairingOwner owner) =>
      ref.mounted &&
      !owner.disposed &&
      identical(_owner, owner) &&
      identical(ref.read(deviceSetupProvider), owner.setup) &&
      identical(ref.read(deviceManagementProvider), owner.management);

  bool _accepts(_QrPairingOwner owner, _QrAttempt attempt) =>
      _current(owner) && identical(owner.attempt, attempt) && attempt.accepting;

  Future<void> generate() async {
    final owner = _owner;
    if (!_current(owner) || state.busy) return;
    if (owner.attempt != null && !await cancel()) return;
    if (!_current(owner) || owner.attempt != null) return;
    final attempt = owner.attempt = _QrAttempt(
      'qr-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(owner)}-${owner.next++}',
    );
    state = const QrPairingState(phase: .generating);
    try {
      final session = await owner.setup.beginQrPairing(
        deviceId: deviceId,
        attemptId: attempt.id,
      );
      // 无论页面是否还在，都观察完成句柄，避免迟到的失败成为未处理异常。
      unawaited(_receive(owner, attempt, session));
      if (!_accepts(owner, attempt)) return;
      state = QrPairingState(
        phase: .waiting,
        payload: session.payload,
        expiresAt: session.expiresAt,
      );
      final remaining = session.expiresAt.difference(DateTime.now());
      attempt.expiry = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () {
          if (_accepts(owner, attempt)) {
            unawaited(_cancel(owner, attempt, expired: true));
          }
        },
      );
    } catch (error) {
      if (!_accepts(owner, attempt)) return;
      _fail(owner, attempt, error);
    }
  }

  Future<void> _receive(
    _QrPairingOwner owner,
    _QrAttempt attempt,
    QrPairingSession session,
  ) async {
    PairingReceipt? receipt;
    Object? failure;
    try {
      receipt = await session.result;
    } catch (error) {
      failure = error;
      if (error case DeviceSetupFailure(receipt: PairingReceipt known)
          when known.recorded) {
        receipt = known;
      }
    }
    if (!_accepts(owner, attempt)) return;
    attempt.expiry?.cancel();
    final cleanupRequired =
        failure is DeviceSetupFailure &&
        failure.code == 'setup_cleanup_unconfirmed';
    if (receipt case final paired? when paired.recorded) {
      if (deviceId != null && paired.deviceId != deviceId) {
        if (cleanupRequired) {
          attempt.accepting = false;
        } else {
          owner.attempt = null;
        }
        state = QrPairingState(
          phase: cleanupRequired ? .cleanupRequired : .failed,
          message: '配对结果不属于原设备，请重新检查。${cleanupRequired ? failure : ''}',
        );
        return;
      }
      if (cleanupRequired) {
        attempt.accepting = false;
      } else {
        owner.attempt = null;
      }
      state = QrPairingState(
        phase: cleanupRequired ? .cleanupRequired : .completed,
        receipt: paired,
        message: switch ((
          failure,
          paired.connected,
          paired.connectionFailure,
        )) {
          (final error?, _, _) => '配对已完成，资源释放尚未确认。$error',
          (_, true, _) => '配对与连接已完成。',
          (_, _, final issue?) => '已配对，尚未连接。${issue.message}',
          _ => '已配对，尚未连接',
        },
      );
      unawaited(ref.read(deviceListProvider.notifier).refresh());
    } else {
      _fail(owner, attempt, failure);
    }
  }

  void _fail(_QrPairingOwner owner, _QrAttempt attempt, Object? error) {
    attempt.expiry?.cancel();
    final cleanupRequired =
        error is DeviceSetupFailure &&
        error.code == 'setup_cleanup_unconfirmed';
    final expired = error is RequestFailure && error.code == 'expired';
    if (cleanupRequired) {
      attempt.accepting = false;
    } else {
      owner.attempt = null;
    }
    state = QrPairingState(
      phase: cleanupRequired
          ? .cleanupRequired
          : expired
          ? .expired
          : .failed,
      message: expired ? '二维码已过期，请重新生成。' : error?.toString() ?? '配对已结束，请重新生成。',
    );
  }

  Future<bool> cancel() {
    final owner = _owner;
    if (!_current(owner)) return Future.value(false);
    final attempt = owner.attempt;
    if (attempt == null) return Future.value(true);
    return _cancel(owner, attempt, expired: false);
  }

  Future<bool> _cancel(
    _QrPairingOwner owner,
    _QrAttempt attempt, {
    required bool expired,
  }) {
    if (attempt.cancellation case final pending?) return pending;
    attempt.accepting = false;
    attempt.expiry?.cancel();
    state = state.copyWith(
      phase: .cancelling,
      message: expired ? '二维码已过期，请重新生成。' : state.message,
    );
    return attempt.cancellation = _drain(owner, attempt, expired: expired);
  }

  Future<bool> _drain(
    _QrPairingOwner owner,
    _QrAttempt attempt, {
    required bool expired,
  }) async {
    try {
      await owner.management.cancelConnectionAttempt(attempt.id);
      if (!_current(owner) || !identical(owner.attempt, attempt)) return false;
      owner.attempt = null;
      state = state.copyWith(
        phase: expired ? .expired : .cancelled,
        payload: null,
        expiresAt: null,
        message: expired
            ? '二维码已过期，请重新生成。'
            : state.receipt?.recorded == true
            ? '扫码已取消，手机上的配对授权已保留。'
            : '扫码已取消，可重新生成。',
      );
      return true;
    } catch (error) {
      if (_current(owner) && identical(owner.attempt, attempt)) {
        state = state.copyWith(phase: .cleanupRequired, message: '$error');
      }
      return false;
    } finally {
      attempt.cancellation = null;
    }
  }
}

final class _QrPairingOwner {
  _QrPairingOwner(this.setup, this.management);
  final DeviceSetup setup;
  final DeviceManagement management;
  _QrAttempt? attempt;
  int next = 0;
  bool disposed = false;

  void dispose() {
    disposed = true;
    final pending = attempt;
    if (pending == null) return;
    pending.accepting = false;
    pending.expiry?.cancel();
    if (pending.cancellation == null) {
      management.cancelConnectionAttempt(pending.id).ignore();
    }
  }
}

final class _QrAttempt {
  _QrAttempt(this.id);
  final String id;
  bool accepting = true;
  Timer? expiry;
  Future<bool>? cancellation;
}
