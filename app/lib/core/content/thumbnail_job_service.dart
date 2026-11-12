import 'dart:async';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/companion/companion_exception.dart';
import 'package:scrcpy_connect/core/content/thumbnail_jobs.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_paths.dart';

/// 与 CompanionService.request 相同的准入边界；请求绑定原连接及同一有序 RPC 通道。
typedef ThumbnailJobRequest = Future<Map<String, Object?>> Function(
  String device,
  String command,
  Map<String, Object?> params, {
  required bool allowStart,
  DeviceConnection? expectedConnection,
  AdbCancellation? cancellation,
});

/// 拥有远端媒体子任务，不拥有缓存、伴生服务、SDK Client 或连接。
/// 等待期限只撤销本次结果准入；未确认退出的任务始终保留同一取消责任供重试。
final class ThumbnailJobService implements ThumbnailJobs {
  ThumbnailJobService({
    required this.requireConnection,
    required this._request,
    this.operationTimeout = const Duration(seconds: 45),
    this.cleanupTimeout = const Duration(seconds: 6),
  }) {
    adbTimeoutMillis(operationTimeout);
    adbTimeoutMillis(cleanupTimeout);
  }

  final DeviceConnection Function(String) requireConnection;
  final ThumbnailJobRequest _request;
  final Duration operationTimeout, cleanupTimeout;
  final _active = <String, _MediaJob>{};
  final _seen = <String, bool>{};
  final _retiredConnections = <DeviceConnection>{};
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<void> cancel(String deviceId, String operationId) async {
    _device(deviceId);
    final operation = _uuid(operationId);
    await _cancel('$deviceId:$operation');
  }

  @override
  Future<Json> run(ThumbnailJob request, {AdbCancellation? cancellation}) {
    final device = _device(request.deviceId);
    final operation = _uuid(request.operationId);
    final key = '$device:$operation';
    if (_closed) throw const RequestFailure('disposed', '媒体任务所有者已关闭。');
    cancellation?.check();
    final path = FilePaths.remote(request.path);
    final kind = request.kind.name;
    final size = request.maxSize;
    final owner = _uuid(request.ownerOperationId);
    final allowStart = request.allowStart;
    final execution = request.phase.name;
    if (size < 64 || size > 512) {
      throw const RequestFailure('invalid_argument', '媒体类型或尺寸无效。');
    }
    final previous = _seen[key];
    if (previous != null) {
      throw RequestFailure(
        previous ? 'cancelled' : 'operation_reused',
        '媒体操作已结束或取消，请使用新的标识。',
      );
    }
    if (_seen.length >= 65536) {
      throw const RequestFailure('operation_limit', '媒体操作标识已达到本次附着上限。');
    }
    if (_active.values.where((job) => job.device == device).length >= 16) {
      throw const RequestFailure('busy', '这台设备正在处理的媒体任务已达到上限。');
    }
    final connection = requireConnection(device);
    if (_retiredConnections.contains(connection)) {
      throw const RequestFailure('cancelled', '原连接已停止媒体任务准入。');
    }
    final job = _MediaJob(device, operation, key, connection);
    _seen[key] = false;
    _active[key] = job;
    return _run(
      job,
      'media.$execution',
      {
        'operationId': operation,
        'ownerOperationId': owner,
        'path': path,
        'kind': kind,
        'maxSize': size,
      },
      allowStart != false,
      cancellation,
    );
  }

  bool _current(_MediaJob job) {
    try {
      return !_closed &&
          !_retiredConnections.contains(job.connection) &&
          identical(requireConnection(job.device), job.connection);
    } catch (_) {
      return false;
    }
  }

  void _interrupt(_MediaJob job, String code, String message) {
    if (!job.interrupted.isCompleted) {
      job.interrupted.complete(
        _Reply.failure(RequestFailure(code, message), StackTrace.current),
      );
    }
  }

  Future<_Reply> _call(
    _MediaJob job,
    String command,
    Map<String, Object?> params, {
    required bool allowStart,
  }) async {
    try {
      // 不把页面取消令牌交给 RPC：它可能只结束等待，不能证明帧或远端进程未执行。
      final result = await _request(
        job.device,
        command,
        params,
        allowStart: allowStart,
        expectedConnection: job.connection,
      );
      // 原任务成功同样证明子进程已退出；即使结果已撤销，也保留清理事实。
      if (command == 'media.stat' || command == 'media.thumbnail') {
        job.reaped = true;
      }
      return _Reply.value(result);
    } catch (error, stack) {
      if (error is CompanionException && error.mediaReaped) {
        job.reaped = true;
      }
      return _Reply.failure(error, stack);
    }
  }

  Future<Map<String, Object?>> _run(
    _MediaJob job,
    String command,
    Map<String, Object?> params,
    bool allowStart,
    AdbCancellation? cancellation,
  ) async {
    final timer = Timer(operationTimeout, () {
      _interrupt(job, 'media_timeout', '媒体任务超过有界等待期限。');
    });
    final unsubscribe = cancellation?.onCancel(() {
      _interrupt(job, 'cancelled', '媒体任务已取消，不再发布本次结果。');
    });
    try {
      if (!job.interrupted.isCompleted) {
        job.execution = _call(job, command, params, allowStart: allowStart);
      }
      final reply = await Future.any([?job.execution, job.interrupted.future]);
      if (!_current(job)) {
        _interrupt(job, 'cancelled', '媒体任务所属连接已变化。');
      }
      if (reply.error == null && !job.interrupted.isCompleted) {
        // MediaJobs 仅在子进程退出、收尾完成后发送成功回执；不另造 reaped 字段。
        _release(job);
        return {...reply.value!, 'operationId': job.operation};
      }
      // allowStart:false 的部署前拒绝明确没有发出媒体帧，无需虚构一次远端回收。
      if (reply.error case CompanionException(code: 'observation_required')) {
        _release(job);
      } else {
        await _drain(job);
      }
      final failure = job.interrupted.isCompleted
          ? await job.interrupted.future
          : reply;
      _throw(failure);
    } finally {
      timer.cancel();
      unsubscribe?.call();
      if (!job.finished.isCompleted) job.finished.complete();
    }
  }

  void _release(_MediaJob job) {
    job.released = true;
    if (identical(_active[job.key], job)) _active.remove(job.key);
  }

  Future<void> _drain(_MediaJob job) {
    if (job.released) return Future.value();
    if (job.cleaning case final pending?) return pending;
    final result = _cleanup(job).catchError((Object error, StackTrace stack) {
      job.cleaning = null;
      Error.throwWithStackTrace(error, stack);
    });
    return job.cleaning = result;
  }

  Future<void> _cleanup(_MediaJob job) async {
    try {
      if (job.execution != null && !job.reaped) {
        // 服务端先记 seen，即使取消帧先到，也不能让相同 ID 的迟到启动越过它。
        final cancellation = job.cancelReply ??= _call(
          job,
          'media.thumbnail.cancel',
          {'operationId': job.operation},
          allowStart: false,
        );
        final reply = await Future.any<_Reply>([
          cancellation,
          job.execution!.then<_Reply>(
            (reply) => job.reaped ? reply : cancellation,
          ),
        ]).timeout(cleanupTimeout);
        if (reply.error != null || reply.value?['reaped'] != true) {
          job.cancelReply = null;
          if (!job.reaped) {
            throw const RequestFailure(
              'media_cleanup_unknown',
              '远端媒体进程尚未确认退出。',
            );
          }
        }
        job.reaped = true;
      }
      // 取消确认不能让仍在等待部署或写入的原请求失去本机责任。
      await job.execution?.timeout(cleanupTimeout);
      _release(job);
    } catch (_) {
      throw const RequestFailure(
        'media_cleanup_unknown',
        '媒体任务的远端退出或原请求收尾尚未核验，请重试停止。',
      );
    }
  }

  Future<void> _cancel(String key) async {
    final job = _active[key];
    if (job == null) {
      final fresh = !_seen.containsKey(key);
      if (fresh) {
        if (_seen.length >= 65536) {
          throw const RequestFailure('operation_limit', '媒体操作标识已达到本次附着上限。');
        }
        _seen[key] = true;
      }
      return;
    }
    _interrupt(job, 'cancelled', '媒体任务已取消，不再发布本次结果。');
    await _drain(job);
    await job.finished.future;
  }

  /// 同步撤销原连接准入，再等待其全部媒体任务；不停止后继连接或共享伴生服务。
  Future<void> stopForConnection(String device, DeviceConnection connection) {
    _retiredConnections.add(connection);
    final jobs = _active.values
        .where(
          (job) =>
              job.device == device && identical(job.connection, connection),
        )
        .toList();
    return _stop(jobs);
  }

  Future<void> _stop(List<_MediaJob> jobs) {
    for (final job in jobs) {
      _interrupt(job, 'cancelled', '媒体任务已停止，不再发布结果。');
    }
    return Future.wait(
      jobs.map((job) async {
        await _drain(job);
        await job.finished.future;
      }),
    );
  }

  /// 首次调用即撤准入；清理失败保留原任务和 Future，下次 close 只重试同一责任。
  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    final result = _stop(_active.values.toList())
        .catchError((Object error, StackTrace stack) {
          _closing = null;
          Error.throwWithStackTrace(error, stack);
        });
    return _closing = result;
  }
}

final class _MediaJob {
  _MediaJob(this.device, this.operation, this.key, this.connection);
  final String device, operation, key;
  final DeviceConnection connection;
  final interrupted = Completer<_Reply>();
  final finished = Completer<void>();
  Future<_Reply>? execution, cancelReply;
  Future<void>? cleaning;
  bool reaped = false, released = false;
}

final class _Reply {
  _Reply.value(this.value) : error = null, stack = null;
  _Reply.failure(this.error, this.stack) : value = null;
  final Map<String, Object?>? value;
  final Object? error;
  final StackTrace? stack;
}

Never _throw(_Reply reply) {
  final error = switch (reply.error!) {
    CompanionException(:final code, :final message) => RequestFailure(
      code,
      message,
    ),
    final error => error,
  };
  Error.throwWithStackTrace(error, reply.stack!);
}

String _device(String value) {
  if (value.isEmpty || value.contains('\u0000')) {
    throw const RequestFailure('invalid_argument', '媒体任务设备标识无效。');
  }
  return value;
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const RequestFailure('invalid_argument', '媒体操作标识必须是 UUID。');
  }
  return value.toLowerCase();
}
