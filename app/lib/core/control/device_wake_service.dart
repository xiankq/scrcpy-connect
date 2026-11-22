import 'dart:async';

import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/device_keep_awake_changed.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 每设备共享的保持唤醒控制服务；窗口资格由控制窗口所有者提供，包含有界画质交接。
/// 不点亮屏幕、不修改永久超时；关闭须等待 SDK 的本机排空与精确主进程退出证明。
final class DeviceWakeService {
  DeviceWakeService({
    required this.scrcpy,
    required this.requireConnection,
    required this.hasWindowOwner,
    required this.keepAwakeEnabled,
    required this.onChanged,
    this.startupTimeout = const Duration(seconds: 12),
  }) {
    if (startupTimeout <= Duration.zero) {
      throw ArgumentError.value(startupTimeout, 'startupTimeout');
    }
  }

  final ScrcpyClient scrcpy;
  final DeviceConnection Function(String) requireConnection;
  final bool Function(String) hasWindowOwner;
  final bool Function(String deviceId) keepAwakeEnabled;
  final void Function(DeviceKeepAwakeChanged) onChanged;
  final Duration startupTimeout;
  final _current = <String, _KeepAwakeLease>{};
  final _leases = <_KeepAwakeLease>[];
  final _last = <String, KeepAwakeSnapshot>{};
  final _generations = <String, int>{};
  bool _closed = false;
  Future<void>? _closing;

  bool _enabled(String device) => keepAwakeEnabled(device);

  KeepAwakeSnapshot readWake(String deviceId) =>
      (_last[deviceId] ??
              KeepAwakeSnapshot.withoutLease(
                deviceId: deviceId,
                enabled: _enabled(deviceId),
                hasWindowOwner: hasWindowOwner(deviceId),
              ))
          .copyWith(
            keepActive: _enabled(deviceId),
            pendingCleanup: [
              for (final entry in _leases)
                if (entry.deviceId == deviceId && entry.retired) entry.state,
            ],
          );

  /// 设置或窗口资格改变后调用；首个等待点前撤销旧准入。
  /// 关闭失败保留精确捕获，下一次通知先重试旧清理，再允许同设备启动。
  Future<KeepAwakeSnapshot> sync(String deviceId) {
    if (_closed) {
      return Future.error(const RequestFailure('disposed', '保持唤醒所有者已关闭。'));
    }
    final wanted = _enabled(deviceId) && hasWindowOwner(deviceId);
    DeviceConnection? connection;
    Object? connectionFailure;
    StackTrace? connectionStack;
    if (wanted) {
      try {
        connection = requireConnection(deviceId);
      } catch (error, stack) {
        connectionFailure = error;
        connectionStack = stack;
      }
    }
    final existing = _current[deviceId];
    if (existing != null &&
        (!wanted || !identical(existing.connection, connection))) {
      _retire(existing);
    }
    if (connectionFailure != null) {
      return () async {
        await _drain(deviceId);
        Error.throwWithStackTrace(connectionFailure!, connectionStack!);
      }();
    }
    if (!wanted) {
      return _drain(deviceId).then((_) => readWake(deviceId));
    }
    if (_current[deviceId] case final current?) return current.result!;
    final generation = (_generations[deviceId] ?? 0) + 1;
    _generations[deviceId] = generation;
    final entry = _KeepAwakeLease(deviceId, connection!, generation);
    _leases.add(entry);
    _current[deviceId] = entry;
    entry.starting = _start(entry);
    entry.result = entry.starting!.then(
      (_) => readWake(deviceId),
      onError: (Object error, StackTrace stack) async {
        try {
          await _close(entry);
        } catch (cleanup, trace) {
          Error.throwWithStackTrace(
            RequestFailure('keep_active_cleanup', '保持唤醒服务尚未确认停止，请重试。', (
              cause: error,
              cleanup: cleanup,
              snapshot: entry.state,
            )),
            trace,
          );
        }
        Error.throwWithStackTrace(_applicationError(error), stack);
      },
    );
    _publish(entry);
    return entry.result!;
  }

  Future<void> windowsChanged(String deviceId) async => sync(deviceId);

  Future<void> settingsChanged(Iterable<String> deviceIds) async {
    final failures = <({String deviceId, Object cause})>[];
    await Future.wait([
      for (final device in deviceIds.toSet())
        () async {
          try {
            await sync(device);
          } catch (error) {
            failures.add((deviceId: device, cause: error));
          }
        }(),
    ]);
    if (failures.isNotEmpty) {
      throw RequestFailure(
        'keep_active_partial',
        '设置已保存，部分保持唤醒服务尚未应用。',
        List<({String deviceId, Object cause})>.unmodifiable(failures),
      );
    }
  }

  bool _eligible(_KeepAwakeLease entry) =>
      !_closed &&
      !entry.retired &&
      identical(_current[entry.deviceId], entry) &&
      _enabled(entry.deviceId) &&
      hasWindowOwner(entry.deviceId) &&
      identical(requireConnection(entry.deviceId), entry.connection);

  void _check(_KeepAwakeLease entry) {
    if (!_eligible(entry)) {
      final failure = entry.state.keepActiveError;
      throw RequestFailure(failure?.code ?? 'cancelled', '保持唤醒所需的窗口或连接已结束。');
    }
  }

  Future<void> _start(_KeepAwakeLease entry) async {
    final deadline = Timer(startupTimeout, () {
      entry.state = entry.state.copyWith(
        keepActiveError: KeepAwakeFailure(
          code: 'keep_active_timeout',
          reason: '保持唤醒控制通道未及时就绪。',
        ),
      );
      _retire(entry);
      _backgroundClose(entry);
    });
    try {
      await _drain(entry.deviceId);
      _check(entry);
      // 创建不丢弃 Future；迟到句柄必须先登记，再判断本代次是否仍有资格。
      try {
        entry.session = await scrcpy.createSession(
          entry.connection.device,
          options: const ScrcpyOptions(
            logLevel: ScrcpyLogLevel.warn,
            video: false,
            audio: false,
            control: true,
            keepActive: true,
            powerOn: false,
            powerOffOnClose: false,
            stayAwake: false,
            clipboardAutosync: false,
            cleanup: false,
          ),
        );
      } on ScrcpyCreationCleanupFailure catch (error) {
        entry.session = error.session;
        rethrow;
      }
      _check(entry);
      final session = entry.session!;
      entry.observer = session.events.listen(
        (event) {
          if (event is ScrcpyStopped && !entry.retired) {
            _ended(entry, event.reason ?? '保持唤醒控制服务已结束。');
          }
        },
        onError: (Object error) => _ended(entry, '$error'),
        onDone: () {
          if (!entry.retired) _ended(entry, '保持唤醒事件连接已结束。');
        },
      );
      final info = await session.startControl();
      _check(entry);
      if (info.id != session.id || !info.controlReady) {
        throw const RequestFailure('keep_active_protocol', '保持唤醒控制通道未接纳。');
      }
      entry.state = entry.state.copyWith(
        status: KeepAwakeStatus.active,
        keepActiveApplied: true,
        keepActiveLeaseActive: true,
        keepActiveError: null,
        keepActivePid: info.processId,
        keepActiveProcessStarted: info.processStarted,
      );
      _publish(entry);
    } catch (error) {
      entry.state = entry.state.copyWith(
        keepActiveError:
            entry.state.keepActiveError ??
            KeepAwakeFailure(code: _errorCode(error), reason: '$error'),
      );
      _retire(entry);
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  void _ended(_KeepAwakeLease entry, String reason) {
    if (entry.retired) return;
    entry.state = entry.state.copyWith(
      keepActiveError: KeepAwakeFailure(
        code: 'keep_active_ended',
        reason: reason,
      ),
    );
    _retire(entry);
    _backgroundClose(entry);
  }

  void _retire(_KeepAwakeLease entry) {
    if (entry.retired) return;
    entry.retired = true;
    if (identical(_current[entry.deviceId], entry)) {
      _current.remove(entry.deviceId);
    }
    entry.state = entry.state.copyWith(
      status: KeepAwakeStatus.stopping,
      keepActiveApplied: false,
      keepActiveLeaseActive: false,
      releasePending: true,
    );
    _publish(entry);
  }

  Future<void> _closeSession(_KeepAwakeLease entry) async {
    if (entry.session case final session?) {
      await session.close();
      await entry.observer?.cancel();
    }
  }

  void _backgroundClose(_KeepAwakeLease entry) {
    unawaited(_close(entry).catchError((Object _, StackTrace _) {}));
  }

  Future<void> _close(_KeepAwakeLease entry) {
    if (entry.closed) return Future.value();
    if (entry.closing case final closing?) return closing;
    _retire(entry);
    // 先撤捕获准入以唤醒控制等待，再等待创建和启动确实退出。
    final earlySession = entry.session;
    final early = _closeSession(entry);
    unawaited(early.catchError((Object _, StackTrace _) {}));
    final result = () async {
      try {
        // 原生关闭失败可能无法唤醒尚未完成的握手；先报告并保留重试权，
        // 不能让等待启动退出的关闭 Future 永久占住后续关闭入口。
        await early;
        try {
          await entry.starting;
        } catch (_) {
          // 启动结果由原命令报告，此处只承担精确清理。
        }
        if (!identical(entry.session, earlySession)) {
          await _closeSession(entry);
        }
        entry.closed = true;
        _leases.remove(entry);
        final previousFailure = entry.state.keepActiveError;
        if (previousFailure?.code == 'keep_active_cleanup') {
          entry.state = entry.state.copyWith(keepActiveError: null);
        }
        entry.state = entry.state.copyWith(
          status: KeepAwakeStatus.released,
          releasePending: false,
          localCleanupConfirmed: true,
          cleanupConfirmed: true,
          remoteExitVerified: entry.session != null,
          // keep_active 只定时报告用户活动；未使用永久超时或上游清理进程，不能虚报设置恢复。
          remoteRestoreVerified: false,
        );
        _publish(entry);
      } catch (error, stack) {
        entry.state = entry.state.copyWith(
          status: KeepAwakeStatus.cleanupUnconfirmed,
          releasePending: true,
          localCleanupConfirmed: false,
          keepActiveError: KeepAwakeFailure(
            code: 'keep_active_cleanup',
            reason: '$error',
          ),
        );
        _publish(entry);
        Error.throwWithStackTrace(
          RequestFailure('keep_active_cleanup', '保持唤醒服务尚未确认停止。', (
            snapshot: entry.state,
            cause: error,
          )),
          stack,
        );
      }
    }();
    return entry.closing = result.catchError((Object error, StackTrace stack) {
      entry.closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _drain(String device) async {
    await Future.wait([
      for (final entry in _leases.toList())
        if (entry.deviceId == device && entry.retired) _close(entry),
    ]);
  }

  Future<void> stopForConnection(String deviceId, DeviceConnection connection) {
    final selected = _leases
        .where(
          (entry) =>
              entry.deviceId == deviceId &&
              identical(entry.connection, connection),
        )
        .toList();
    for (final entry in selected) {
      _retire(entry);
    }
    return Future.wait(selected.map(_close));
  }

  Future<void> close() {
    if (_closing case final closing?) return closing;
    _closed = true;
    final entries = _leases.toList();
    for (final entry in entries) {
      _retire(entry);
    }
    final result = Future.wait(entries.map(_close));
    return _closing = result.then<void>((_) {}).catchError((
      Object error,
      StackTrace stack,
    ) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  void _publish(_KeepAwakeLease entry) {
    entry.state = entry.state.copyWith(
      deviceId: entry.deviceId,
      keepActive: _enabled(entry.deviceId),
      keepActiveLeaseId: entry.session?.id,
      keepActiveConnectionId: entry.connection.device.id,
    );
    // 旧连接的迟到清理可以发事件，但不能覆盖后继连接的设备投影。
    if (_generations[entry.deviceId] == entry.generation) {
      _last[entry.deviceId] = entry.state;
    }
    try {
      onChanged(DeviceKeepAwakeChanged(entry.state));
    } catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  }
}

final class _KeepAwakeLease {
  _KeepAwakeLease(this.deviceId, this.connection, this.generation)
    : state = KeepAwakeSnapshot(deviceId: deviceId);
  final String deviceId;
  final DeviceConnection connection;
  final int generation;
  KeepAwakeSnapshot state;
  ScrcpySession? session;
  StreamSubscription<ScrcpyEvent>? observer;
  Future<void>? starting;
  Future<KeepAwakeSnapshot>? result;
  Future<void>? closing;
  bool retired = false;
  bool closed = false;
}

String _errorCode(Object error) => switch (error) {
  RequestFailure(:final code) ||
  ScrcpyException(:final code) ||
  AdbException(:final code) => code,
  _ => 'keep_active_failed',
};
Object _applicationError(Object error) => switch (error) {
  ScrcpyException(:final code, :final message) ||
  AdbException(:final code, :final message) => RequestFailure(code, message),
  _ => error,
};
