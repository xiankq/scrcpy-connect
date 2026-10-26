import 'dart:async';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';

/// 应用按闲置时间解释协议事实；探针只拥有自己的流，不拥有设备连接。
/// 退休复用设备所有者；本模块不建立连接，也不保存第二份在线状态。
final class DeviceHealthCoordinator {
  DeviceHealthCoordinator({
    required this.current,
    required this.retire,
    this.policy = const ConnectionPolicy(),
    this.onError,
    Duration Function()? elapsed,
  }) : _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter {
    if (policy.monitorInterval <= Duration.zero ||
        policy.healthIdle <= Duration.zero ||
        policy.healthProbeTimeout <= Duration.zero ||
        policy.healthFailureLimit < 1) {
      throw ArgumentError('健康监测时间和失败次数必须为正值。');
    }
  }

  final DeviceConnection? Function(String) current;
  final Future<void> Function(
    String deviceId,
    DeviceConnection connection, {
    required String reason,
  })
  retire;
  final ConnectionPolicy policy;
  final void Function(Object, StackTrace)? onError;
  final Duration Function() _elapsed;
  final _entries = Map<DeviceConnection, _HealthEntry>.identity();
  Timer? _timer;
  bool _closed = false;
  Future<void>? _closing;

  /// 精确对象重复登记无副作用；后继不会继承旧连接的探针或失败计数。
  void start(String deviceId, DeviceConnection connection) {
    if (_closed) throw StateError('健康监测已关闭。');
    if (!identical(current(deviceId), connection)) return;
    if (_entries.containsKey(connection)) return;
    for (final entry in _entries.values.toList()) {
      if (entry.deviceId == deviceId && entry.active) {
        unawaited(
          stopConnection(deviceId, entry.connection).catchError(_report),
        );
      }
    }
    _entries[connection] = _HealthEntry(deviceId, connection, _elapsed());
    _timer ??= Timer.periodic(policy.monitorInterval, (_) {
      unawaited(checkNow().catchError(_report));
    });
  }

  /// 前台恢复可立即核对；同一连接最多一个任务，不同设备并行。
  Future<void> checkNow() async {
    await Future.wait<void>([
      for (final entry in _entries.values.toList()) _check(entry),
    ]);
  }

  Future<void> _check(_HealthEntry entry) {
    if (entry.checking case final pending?) return pending;
    final completion = Completer<void>();
    entry.checking = completion.future;
    unawaited(
      () async {
        try {
          if (entry.reason != null) {
            await _retire(entry);
            return;
          }
          if (!_authorized(entry)) {
            await stopConnection(entry.deviceId, entry.connection);
            return;
          }
          // poll 只包含事实读取与探针释放。退休回调可能反向调用 stopConnection，
          // 因此必须先撤下 poll 的等待责任，才能进入设备退休队列。
          final polling = entry.polling = _poll(entry);
          String? reason;
          try {
            reason = await polling;
          } finally {
            entry.polling = null;
          }
          if (reason != null && _authorized(entry)) {
            entry.active = false;
            entry.reason = reason;
            await _retire(entry);
          }
        } finally {
          entry.checking = null;
        }
      }().then<void>(completion.complete, onError: completion.completeError),
    );
    return completion.future;
  }

  bool _authorized(_HealthEntry entry) =>
      !_closed &&
      entry.active &&
      identical(current(entry.deviceId), entry.connection);

  Future<String?> _poll(_HealthEntry entry) async {
    // 旧探针清理失败时必须先重试，不能再开一个探针掩盖原关闭责任。
    await _releaseProbe(entry);
    if (!_authorized(entry)) return null;
    final connection = entry.connection;
    final facts = await connection.client.services.connectionFacts(
      connection.device,
    );
    if (!_authorized(entry)) return null;
    final identityFailure = _verifyIdentity(entry, facts);
    if (identityFailure != null) return identityFailure;
    if (facts.closed) return 'transport_closed';
    final now = _elapsed();
    if (facts.inboundActivity case final activity?) {
      if (entry.activity != activity) {
        entry.activity = activity;
        entry.lastActivity = now;
        entry.failures = 0;
      }
    }
    if (!policy.healthEnabled || now - entry.lastActivity < policy.healthIdle) {
      return null;
    }
    AdbOpenProbe probe;
    try {
      probe = await connection.client.services.createOpenProbe(
        connection.device,
        service: 'sync:',
        timeout: policy.healthProbeTimeout,
      );
    } on AdbOpenProbeCleanupFailure catch (failure) {
      entry.probe = failure.probe;
      rethrow;
    }
    entry.probe = probe;
    if (!_authorized(entry)) {
      await _releaseProbe(entry);
      return null;
    }
    AdbOpenProbeFacts result;
    try {
      result = await probe.result;
    } finally {
      await _releaseProbe(entry);
    }
    if (!_authorized(entry)) return null;
    // 探测期间原生句柄可能被外部接管；Dart 对象相等不能替代物理连接事实。
    final after = await connection.client.services.connectionFacts(
      connection.device,
    );
    if (!_authorized(entry)) return null;
    final afterIdentityFailure = _verifyIdentity(entry, after);
    if (afterIdentityFailure != null) return afterIdentityFailure;
    if (after.closed) return 'transport_closed';
    // 官方层仅表示 smart socket 的响应；两层的有效拒绝都证明收到过响应。
    final activity = after.inboundActivity ?? result.inboundActivity;
    final activityChanged = entry.activity != activity;
    if (activityChanged) {
      entry.activity = activity;
      entry.lastActivity = _elapsed();
      entry.failures = 0;
    }
    switch (result.outcome) {
      case AdbOpenProbeOutcome.okay:
      case AdbOpenProbeOutcome.rejected:
        entry.activity = activity;
        entry.lastActivity = _elapsed();
        entry.failures = 0;
      case AdbOpenProbeOutcome.transportClosed:
        return 'transport_closed';
      case AdbOpenProbeOutcome.timedOut:
        if (result.openWritten && !activityChanged) {
          entry.failures++;
          if (entry.failures >= policy.healthFailureLimit) {
            return 'health_response_timeout';
          }
        }
      case AdbOpenProbeOutcome.notWritten:
      case AdbOpenProbeOutcome.localCapacity:
      case AdbOpenProbeOutcome.cancelled:
      case AdbOpenProbeOutcome.io:
      case AdbOpenProbeOutcome.protocol:
        // 没有可靠的对端无响应证据；本机拥塞、取消或协议错误不累计网络失败。
        break;
    }
    return null;
  }

  String? _verifyIdentity(_HealthEntry entry, AdbConnectionFacts facts) {
    final identity = facts.connectionId;
    if (identity == null || identity.isEmpty) {
      return 'health_connection_identity_unavailable';
    }
    if (entry.physicalId != null && entry.physicalId != identity) {
      return 'health_connection_identity_changed';
    }
    entry.physicalId = identity;
    return null;
  }

  void _remove(_HealthEntry entry) {
    _entries.remove(entry.connection);
    if (_entries.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _releaseProbe(_HealthEntry entry) async {
    if (entry.probe case final probe?) {
      await probe.close();
      if (identical(entry.probe, probe)) entry.probe = null;
    }
  }

  Future<void> _retire(_HealthEntry entry) async {
    await retire(entry.deviceId, entry.connection, reason: entry.reason!);
    _remove(entry);
  }

  /// 同步撤销本连接探测准入，随后等待迟到创建、结果与精确关闭实际退出。
  /// 失败保留条目及 probe，重试不会影响同设备后继或其他设备。
  Future<void> stopConnection(String deviceId, DeviceConnection connection) {
    final entry = _entries[connection];
    if (entry == null || entry.deviceId != deviceId) return Future.value();
    entry.active = false;
    if (entry.stopping case final pending?) return pending;
    final completion = Completer<void>();
    entry.stopping = completion.future;
    unawaited(
      () async {
            Object? failure;
            StackTrace? trace;
            // close 先通知 native 取消，否则仅等待 result 可能直到完整探测期限才结束。
            try {
              await _releaseProbe(entry);
            } catch (error, stack) {
              failure ??= error;
              trace ??= stack;
            }
            await entry.polling?.then<void>(
              (_) {},
              onError: (Object _, StackTrace _) {},
            );
            try {
              await _releaseProbe(entry);
            } catch (error, stack) {
              failure ??= error;
              trace ??= stack;
            }
            if (failure != null) Error.throwWithStackTrace(failure, trace!);
            if (entry.reason == null) _remove(entry);
          }()
          .then<void>(completion.complete, onError: completion.completeError)
          .whenComplete(() => entry.stopping = null),
    );
    return completion.future;
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    return _closing =
        Future.wait<void>([
          for (final entry in _entries.values.toList())
            () async {
              await stopConnection(entry.deviceId, entry.connection);
              // 失败退休的离线投影与精确清理仍由原模块负责，不能在关闭时丢失。
              if (entry.reason != null) await _check(entry);
            }(),
        ]).catchError((Object error, StackTrace stack) {
          _closing = null;
          Error.throwWithStackTrace(error, stack);
        });
  }

  void _report(Object error, StackTrace stack) => onError?.call(error, stack);
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}

final class _HealthEntry {
  _HealthEntry(this.deviceId, this.connection, this.lastActivity);
  final String deviceId;
  final DeviceConnection connection;
  bool active = true;
  String? activity;
  String? physicalId;
  Duration lastActivity;
  int failures = 0;
  AdbOpenProbe? probe;
  Future<String?>? polling;
  Future<void>? checking;
  Future<void>? stopping;
  String? reason;
}
