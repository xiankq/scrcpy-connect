import 'package:scrcpy_connect/services/device_connection.dart';

import 'dart:async';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/models/application_request.dart';

final class _Attempt {
  _Attempt(this.generation);
  final int generation;
  final cancellation = AdbCancellation();
}

final class _Retirement {
  _Retirement(this.connection, {this.beforeCleanup});
  final DeviceConnection connection;
  Future<void> Function()? beforeCleanup;
  bool activitiesStopped = false;
  bool transportDisconnected = false;
}

final class _DeviceSlot {
  int generation = 0;
  _Attempt? attempt;
  DeviceConnection? admitted;
  final retiring = <_Retirement>[];
  Future<void> tail = Future.value();
}

/// 应用持有记录与精确 SDK 连接的对应关系，按设备串行替换与清理。
/// 失效同步撤销准入；迟到握手只能清理，不能发布为当前连接。
/// [stopActivities] 按传入的旧连接回收，可重试且不得停止后继连接的活动。
final class DeviceConnectionPool {
  DeviceConnectionPool({required this._stopActivities, this.onDisconnected});

  final Future<void> Function(String, DeviceConnection) _stopActivities;

  /// 实际断开后通知精确连接；通知失败不恢复关闭权，也不阻止其余退休资源排空。
  final void Function(String, DeviceConnection)? onDisconnected;
  final _slots = <String, _DeviceSlot>{};
  bool _closed = false;
  Future<void>? _closing;

  DeviceConnection? current(String recordId) => _slots[recordId]?.admitted;

  DeviceConnection require(String recordId) =>
      current(recordId) ??
      (throw const RequestFailure('disconnected', '这台设备当前没有可用连接。'));

  void _checkOpen() {
    if (_closed) {
      throw const RequestFailure('disposed', '连接所有者已关闭。');
    }
  }

  ({
    _DeviceSlot slot,
    int generation,
    void Function()? reportCancellationFailure,
  })
  _invalidate(String recordId, {bool retireCurrent = true}) {
    final slot = _slots.putIfAbsent(recordId, _DeviceSlot.new);
    final generation = ++slot.generation;
    if (retireCurrent) _retireCurrent(slot);
    void Function()? reportCancellationFailure;
    try {
      slot.attempt?.cancellation.cancel();
    } catch (error, stack) {
      // token 已通知全部监听；先完成撤权与资源回收，再向调用方报告监听失败。
      reportCancellationFailure = () => Error.throwWithStackTrace(error, stack);
    }
    return (
      slot: slot,
      generation: generation,
      reportCancellationFailure: reportCancellationFailure,
    );
  }

  void _retireCurrent(_DeviceSlot slot) {
    if (slot.admitted case final previous?) {
      slot.admitted = null;
      slot.retiring.add(_Retirement(previous));
    }
  }

  Future<T> _serial<T>(_DeviceSlot slot, Future<T> Function() action) {
    final result = slot.tail.then((_) => action());
    slot.tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _isCurrent(_DeviceSlot slot, _Attempt attempt) =>
      !_closed &&
      slot.generation == attempt.generation &&
      identical(slot.attempt, attempt) &&
      !attempt.cancellation.isCancelled;

  void _checkAttempt(_DeviceSlot slot, _Attempt attempt) {
    if (!_isCurrent(slot, attempt)) {
      throw const RequestFailure('cancelled', '本次连接已失效。');
    }
  }

  Future<void> _drain(
    String recordId,
    _DeviceSlot slot, {
    _Retirement? until,
  }) async {
    Object? notificationFailure;
    StackTrace? notificationStack;
    while (slot.retiring.isNotEmpty) {
      final retirement = slot.retiring.first;
      if (identical(retirement, until)) break;
      if (retirement.beforeCleanup case final prepare?) {
        await prepare();
        retirement.beforeCleanup = null;
      }
      if (!retirement.activitiesStopped) {
        await _stopActivities(recordId, retirement.connection);
        retirement.activitiesStopped = true;
      }
      if (!retirement.transportDisconnected) {
        // 只断开此句柄，不结束共享 Client、专属服务器或其他设备。
        await retirement.connection.client.disconnect(
          retirement.connection.device,
        );
        retirement.transportDisconnected = true;
      }
      // USB 原始平台句柄须活到 Rust 重复句柄及其驱动实际释放之后。
      // 平台释放失败不能丢失精确责任，也不能在重试时再次关闭 SDK 句柄。
      await retirement.connection.releasePlatformResources?.call();
      slot.retiring.removeAt(0);
      try {
        onDisconnected?.call(recordId, retirement.connection);
      } catch (error, stack) {
        notificationFailure ??= error;
        notificationStack ??= stack;
      }
    }
    if (notificationFailure != null) {
      Error.throwWithStackTrace(notificationFailure, notificationStack!);
    }
  }

  /// [open] 使用明确选定的身份创建连接；返回前失败时由它回收尚未交出的资源。
  /// [verify] 核验实际设备身份及应用代次，完成后才准入；不得发布连接事件。
  /// 核验必须观察同一取消信号，并在实际探测与本机收尾退出后返回。
  /// 所有者等待核验退出后才释放候选连接，不丢弃仍在工作的核验 Future。
  /// [beforeAdmit] 在旧连接及活动实际退出后执行；失败不恢复已经退休的旧连接。
  /// 此阶段同样必须等待实际操作收尾，完成并复核取消后才交付候选。
  Future<DeviceConnection> replace(
    String recordId, {
    required Future<DeviceConnection> Function(AdbCancellation cancellation)
    open,
    required Future<void> Function(
      DeviceConnection connection,
      AdbCancellation cancellation,
    )
    verify,
    Future<void> Function(DeviceConnection, AdbCancellation)? beforeAdmit,
  }) => _replace(
    recordId,
    open,
    verify,
    preserveCurrent: false,
    beforeAdmit: beforeAdmit,
  );

  /// 修改端点时先连接并核验候选；核验失败不撤销当前连接及其活动。
  /// 候选通过后才撤销旧准入，并等待旧活动与连接释放，之后交付新连接。
  /// [open]、[verify] 的取消与资源约束与 [replace] 相同。
  /// [beforeAdmit] 属于旧连接退休后的阶段，失败只能清理候选，不能复活原活动。
  /// [onRejected] 在候选核验失败或核验后失效时补偿尚未交付的配置。
  /// 补偿与后继请求共用设备队列；失败保留责任，重试成功前不准入后继候选。
  /// 开始退休原连接后不再调用补偿，也不承诺进程退出后的事务恢复。
  Future<DeviceConnection> reconfigure(
    String recordId, {
    required Future<DeviceConnection> Function(AdbCancellation cancellation)
    open,
    required Future<void> Function(
      DeviceConnection connection,
      AdbCancellation cancellation,
    )
    verify,
    Future<void> Function(DeviceConnection, AdbCancellation)? beforeAdmit,
    Future<void> Function(DeviceConnection candidate)? onRejected,
  }) => _replace(
    recordId,
    open,
    verify,
    preserveCurrent: true,
    beforeAdmit: beforeAdmit,
    onRejected: onRejected,
  );

  /// 撤销精确旧连接的准入，停止其活动后借用传输执行一次模式切换。
  /// 返回前确认 SDK 与平台资源释放；失败保留原退休阶段，清理重试不重放切换。
  /// 取消只通知执行中的 [change]，仍须等待它实际退出后才能断开传输。
  Future<T> retireForChange<T>(
    String recordId,
    DeviceConnection expected, {
    required Future<T> Function(DeviceConnection, AdbCancellation) change,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    cancellation?.check();
    if (!identical(current(recordId), expected)) {
      throw const RequestFailure('stale_connection', '目标连接已变化。');
    }
    final invalidation = _invalidate(recordId);
    final slot = invalidation.slot;
    final retirement = slot.retiring.firstWhere(
      (entry) => identical(entry.connection, expected),
    );
    final attempt = _Attempt(invalidation.generation);
    if (slot.generation == attempt.generation) slot.attempt = attempt;
    final unwatch = cancellation?.onCancel(attempt.cancellation.cancel);
    return _serial(slot, () async {
      var cleanupPermitted = false;
      try {
        // 前序候选与补偿也属于此设备；不能越过尚未确认的清理使用旧传输。
        await _drain(recordId, slot, until: retirement);
        cleanupPermitted = true;
        invalidation.reportCancellationFailure?.call();
        _checkAttempt(slot, attempt);
        try {
          await _stopActivities(recordId, expected);
          retirement.activitiesStopped = true;
        } catch (_) {
          // 活动未排空时不执行切换，也不能假定可以关闭它仍在使用的传输。
          cleanupPermitted = false;
          rethrow;
        }
        _checkAttempt(slot, attempt);
        return await change(expected, attempt.cancellation);
      } finally {
        try {
          if (cleanupPermitted) await _drain(recordId, slot);
        } finally {
          unwatch?.call();
          if (identical(slot.attempt, attempt)) slot.attempt = null;
        }
      }
    });
  }

  Future<DeviceConnection> _replace(
    String recordId,
    Future<DeviceConnection> Function(AdbCancellation) open,
    Future<void> Function(DeviceConnection, AdbCancellation) verify, {
    required bool preserveCurrent,
    Future<void> Function(DeviceConnection, AdbCancellation)? beforeAdmit,
    Future<void> Function(DeviceConnection candidate)? onRejected,
  }) {
    _checkOpen();
    final invalidation = _invalidate(recordId, retireCurrent: !preserveCurrent);
    final slot = invalidation.slot;
    final attempt = _Attempt(invalidation.generation);
    // 取消监听可以同步发起后继请求；旧请求不能取得它的新代次或覆盖它的 token。
    if (slot.generation == attempt.generation) slot.attempt = attempt;
    return _serial(slot, () async {
      DeviceConnection? candidate;
      var handoffStarted = false;
      try {
        await _drain(recordId, slot);
        invalidation.reportCancellationFailure?.call();
        _checkAttempt(slot, attempt);
        candidate = await open(attempt.cancellation);
        _checkAttempt(slot, attempt);
        await verify(candidate, attempt.cancellation);
        _checkAttempt(slot, attempt);
        if (preserveCurrent) {
          handoffStarted = true;
          _retireCurrent(slot);
          await _drain(recordId, slot);
          _checkAttempt(slot, attempt);
        }
        await beforeAdmit?.call(candidate, attempt.cancellation);
        _checkAttempt(slot, attempt);
        slot.admitted = candidate;
        return candidate;
      } catch (error, stack) {
        if (candidate != null && !identical(slot.admitted, candidate)) {
          final rejected = candidate;
          slot.retiring.add(
            _Retirement(
              rejected,
              beforeCleanup: !handoffStarted && onRejected != null
                  ? () => onRejected(rejected)
                  : null,
            ),
          );
          try {
            await _drain(recordId, slot);
          } catch (_) {
            // 保留精确旧句柄和阶段，后续替换必须先重试清理。
            throw const RequestFailure(
              'connection_cleanup_unconfirmed',
              '旧连接尚未确认释放，请先重试断开。',
            );
          }
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        if (identical(slot.attempt, attempt)) slot.attempt = null;
      }
    });
  }

  /// 调用本方法即同步阻止旧握手和旧连接继续准入；返回时本机清理已完成。
  Future<void> disconnect(String recordId) {
    final invalidation = _invalidate(recordId);
    return _serial(invalidation.slot, () async {
      await _drain(recordId, invalidation.slot);
      invalidation.reportCancellationFailure?.call();
    });
  }

  /// 撤回已经交付但业务尚未接纳的精确连接，不撤销后继握手或后继连接。
  /// 后继替换若已退休此句柄，沿同一队列等待它的原清理责任即可。
  Future<void> release(String recordId, DeviceConnection connection) {
    final slot = _slots[recordId];
    if (slot == null) return Future.value();
    if (identical(slot.admitted, connection)) _retireCurrent(slot);
    return _serial(slot, () => _drain(recordId, slot));
  }

  /// 身份或全局停止先一次撤准入，再并行等待不同设备的清理。
  Future<void> invalidate(Iterable<String> recordIds) {
    final slots = {for (final id in recordIds.toSet()) id: _invalidate(id)};
    return Future.wait([
      for (final entry in slots.entries)
        _serial(entry.value.slot, () async {
          await _drain(entry.key, entry.value.slot);
          entry.value.reportCancellationFailure?.call();
        }),
    ]);
  }

  /// 失败保留关闭权，可重试；已关闭的所有者不能重新准入连接。
  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    final operation = invalidate(_slots.keys.toList())
        .catchError((Object error, StackTrace stack) {
          _closing = null;
          Error.throwWithStackTrace(error, stack);
        });
    return _closing = operation;
  }
}
