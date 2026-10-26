import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart' as adb;
import 'package:path/path.dart' as p;

import 'package:scrcpy_connect/services/files/file_executor.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

/// 组合公开 ADB 文件能力；任务、缓存和业务设备身份仍由应用持有。
final class AdbFileExecutor
    implements
        FileExecutor,
        FileMutationExecutor,
        FileReadExecutor,
        ScopedFileExecutor {
  AdbFileExecutor({
    required this._localFiles,
    required this.resolveConnection,
    required this.fileScopeId,
    required this.fileScopeKey,
  }) : _executionOwner = null {
    if (fileScopeId.isEmpty) {
      throw ArgumentError.value(fileScopeId, 'fileScopeId', '必须先接管文件执行 scope。');
    }
    if (fileScopeKey.isEmpty) {
      throw ArgumentError.value(
        fileScopeKey,
        'fileScopeKey',
        '必须使用真实执行域的稳定 key。',
      );
    }
  }
  AdbFileExecutor._owned(
    AdbFileExecutor parent,
    DeviceConnection connection,
    _AdbExecutionOwner owner,
  ) : _localFiles = parent._localFiles,
      resolveConnection = ((_) async => connection),
      fileScopeId = parent.fileScopeId,
      fileScopeKey = parent.fileScopeKey,
      _executionOwner = owner;
  final _AdbExecutionOwner? _executionOwner;
  bool _cleaningParts = false;
  bool _closed = false;
  Future<void>? _closing;

  void _checkOpen() {
    if (_closed) throw const FileFailure('cancelled', '文件执行器已经关闭准入。');
  }

  /// 撤销全部新便捷执行，排空其精确会话和未发布 part；失败可沿同对象重试。
  /// 读取批次与变更批次仍由它们自己的业务所有者负责关闭。
  Future<void> close() {
    _closed = true;
    if (_closing case final pending?) return pending;
    final result = () async {
      final connections = Set<DeviceConnection>.identity()
        ..addAll(_executions.keys)
        ..addAll(_parts.values.map((part) => part.$1));
      Object? failure;
      StackTrace? failureStack;
      for (final connection in connections) {
        try {
          await stopForConnection(connection);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    }();
    return _closing = result.catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  @override
  Future<FileReadBatch> beginRead(
    String device, {
    required FileCancellation cancellation,
  }) async {
    _checkOpen();
    cancellation.check();
    final connection = await resolveConnection(device);
    cancellation.check();
    _checkOpen();
    return _AdbReadBatch(this, connection, device, cancellation);
  }

  final adb.AdbServices _localFiles;
  final Future<DeviceConnection> Function(String) resolveConnection;
  @override
  final String fileScopeId;
  @override
  final String fileScopeKey;
  final _parts = <(String, String), (DeviceConnection, String)>{};

  @override
  Future<FileMutationBatch> beginMutation(
    String device, {
    required FileCancellation cancellation,
  }) async {
    _checkOpen();
    cancellation.check();
    final connection = await resolveConnection(device);
    // 解析连接期间的取消不能在后继连接上重新发起本次变更。
    cancellation.check();
    _checkOpen();
    return _AdbMutationBatch(this, connection, cancellation);
  }

  FileStamp _stamp(adb.AdbFileExecutionStamp value) => FileStamp(
    identity: value.identity,
    mode: value.mode,
    size: value.size,
    modifiedSeconds: value.modifiedSeconds,
    modifiedNanos: value.modifiedNanos,
    modifiedResolutionNanos: value.nanosecondPrecision ? 1 : 1000000000,
  );
  FileFailure _failure(adb.AdbException error) =>
      FileFailure(error.code, error.message);

  final _executions = Map<DeviceConnection, Set<_AdbExecutionOwner>>.identity();
  final _stoppingConnections = Expando<bool>('已撤销文件执行准入');
  final _connectionClosings = Map<DeviceConnection, Future<void>>.identity();

  /// 同步撤销此精确连接的便捷执行准入，等待已创建和迟到交付的原会话释放。
  /// 失败保留登记供同对象重试；不会关闭此连接上的共享 services。
  Future<void> stopForConnection(DeviceConnection connection) {
    _stoppingConnections[connection] = true;
    final pending = _connectionClosings[connection];
    if (pending != null) return pending;
    final result = () async {
      Object? failure;
      StackTrace? failureStack;
      for (final owner
          in _executions[connection]?.toList() ?? <_AdbExecutionOwner>[]) {
        try {
          await owner.close();
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      // worker 先全部退出，再释放它们已交付的原生 part；禁止按路径删除。
      for (final entry in _parts.entries.toList()) {
        if (!identical(entry.value.$1, connection)) continue;
        await _releaseStoppedPart(entry.key, entry.value);
      }
    }();
    return _connectionClosings[connection] = result.whenComplete(() {
      _connectionClosings.remove(connection);
    });
  }

  Stream<adb.AdbFileExecutionEvent> _execute(
    DeviceConnection connection,
    adb.AdbFileExecutionRequest request,
    FileCancellation cancellation, {
    bool cleanup = false,
  }) async* {
    final standalone = _executionOwner == null;
    if (standalone && !cleanup) _checkOpen();
    if (standalone && !cleanup && _stoppingConnections[connection] == true) {
      throw const FileFailure('cancelled', '原连接已撤销文件执行准入。');
    }
    late final _AdbExecutionOwner owner;
    if (standalone) {
      owner = _AdbExecutionOwner(
        connection,
        onReleased: () {
          final owners = _executions[connection];
          owners?.remove(owner);
          if (owners != null && owners.isEmpty) _executions.remove(connection);
        },
      );
      // 同步登记后才允许原生创建，连接停止不能漏掉迟到交付的会话。
      (_executions[connection] ??= {}).add(owner);
    } else {
      owner = _executionOwner;
    }
    Object? failure;
    StackTrace? failureStack;
    try {
      await for (final event in owner.execute(
        request,
        cancellation,
        cleanup: _cleaningParts || cleanup,
      )) {
        yield event;
      }
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      if (standalone) {
        try {
          await owner.close();
        } catch (error, stack) {
          failure = FileExecutionCleanupFailure(
            owner,
            failure == null ? error : (execution: failure, cleanup: error),
          );
          failureStack = stack;
        }
      }
      // async* 不能先转发错误，再由 finally 追加第二个错误。
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  Future<void> _releaseStoppedPart(
    (String, String) key,
    (DeviceConnection, String) held,
  ) async {
    var confirmed = false;
    await for (final event in _execute(
      held.$1,
      _request(
        adb.AdbFileExecutionKind.releasePart,
        key.$2,
        local: true,
        partId: held.$2,
      ),
      FileCancellation(),
      cleanup: true,
    )) {
      if (event.kind == 'done' && event.saveMode != null) {
        confirmed = true;
        // 远端已经确认释放，后续失败仅保留同一清理 worker，不能重复发操作。
        if (_parts[key] == held) _parts.remove(key);
      }
    }
    if (!confirmed) {
      throw const FileFailure('result_unknown', '未取得原暂存句柄的完整释放回执。');
    }
  }

  adb.AdbFileExecutionRequest _request(
    adb.AdbFileExecutionKind kind,
    String path, {
    String destination = '',
    bool local = false,
    bool followStorageAlias = false,
    int limit = 10000,
    bool push = false,
    bool replace = false,
    adb.AdbFileExecutionStamp? expected,
    String partId = '',
  }) => adb.AdbFileExecutionRequest(
    kind: kind,
    path: utf8.encode(path),
    destination: utf8.encode(destination),
    local: local,
    followStorageAlias: followStorageAlias,
    limit: limit,
    push: push,
    replace: replace,
    expected: expected,
    partId: partId,
    scopeId: fileScopeId,
  );

  @override
  Future<FileStamp> stat(
    String device,
    String path, {
    required bool local,
    bool followStorageAlias = false,
    required FileCancellation cancellation,
  }) async {
    _checkOpen();
    cancellation.check();
    try {
      if (local) {
        final value = await _localFiles.localFileStat(utf8.encode(path));
        cancellation.check();
        return _stamp(value);
      }
      FileStamp? stamp;
      await for (final event in _execute(
        await resolveConnection(device),
        _request(
          adb.AdbFileExecutionKind.stat,
          path,
          followStorageAlias: followStorageAlias,
        ),
        cancellation,
      )) {
        cancellation.check();
        if (event.stamp case final value?) stamp = _stamp(value);
      }
      return stamp ??
          (throw const FileFailure('invalid_metadata', '未取得文件元数据。'));
    } on adb.AdbException catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<DirectoryFacts> list(
    String device,
    String path, {
    required bool local,
    required int limit,
    required FileCancellation cancellation,
  }) async {
    _checkOpen();
    cancellation.check();
    final entries = <FileEntryFact>[];
    void add(List<adb.AdbFileExecutionEntry> values) {
      entries.addAll(
        values.map(
          (entry) => FileEntryFact(
            nameBytes: entry.name,
            stamp: entry.stamp == null ? null : _stamp(entry.stamp!),
            error: entry.errorCode == null
                ? null
                : FileFailure(entry.errorCode!, entry.errorMessage ?? ''),
          ),
        ),
      );
      if (entries.length > limit) {
        throw const FileFailure('invalid_metadata', '目录结果超过请求上限。');
      }
    }

    try {
      if (local) {
        final facts = await _localFiles.localFileList(
          utf8.encode(path),
          limit: limit,
        );
        cancellation.check();
        add(facts.entries);
        return DirectoryFacts(entries, truncated: facts.truncated);
      }
      var truncated = false;
      await for (final event in _execute(
        await resolveConnection(device),
        _request(adb.AdbFileExecutionKind.list, path, limit: limit),
        cancellation,
      )) {
        cancellation.check();
        add(event.entries);
        if (event.kind == 'done') truncated = event.truncated;
      }
      return DirectoryFacts(entries, truncated: truncated);
    } on adb.AdbException catch (error) {
      throw _failure(error);
    }
  }

  bool _sameSnapshot(FileStamp expected, FileStamp observed) {
    final resolution = expected.modifiedResolutionNanos;
    if (!const [1, 1000, 1000000000].contains(resolution) ||
        observed.modifiedResolutionNanos > resolution) {
      return false;
    }
    return expected.mode == observed.mode &&
        expected.size == observed.size &&
        expected.modifiedSeconds == observed.modifiedSeconds &&
        expected.modifiedNanos ~/ resolution ==
            observed.modifiedNanos ~/ resolution;
  }

  @override
  Future<int> copy(
    String device,
    String source,
    String temporary, {
    required bool push,
    required FileStamp expected,
    required FileCancellation cancellation,
    required void Function(int) onProgress,
  }) async {
    _checkOpen();
    cancellation.check();
    final key = (device, temporary);
    if (_parts.containsKey(key)) {
      throw const FileFailure('temporary_handle_conflict', '此暂存路径仍有未释放的描述符。');
    }
    final owner = await resolveConnection(device);
    cancellation.check();
    try {
      // 按旧快照声明的精度核对，再把本次更精确的 SDK 事实交给原生严格校验传输前后。
      final actual = push
          ? await _localFiles.localFileStat(utf8.encode(source))
          : await _remoteStamp(owner, source, cancellation);
      cancellation.check();
      if (!_sameSnapshot(expected, _stamp(actual))) {
        throw const FileFailure('source_changed', '源文件与选择快照不同或无法按原精度核验。');
      }
      int? transferred;
      await for (final event in _execute(
        owner,
        _request(
          adb.AdbFileExecutionKind.copy,
          source,
          destination: temporary,
          push: push,
          expected: actual,
        ),
        cancellation,
      )) {
        if (event.partId case final part?) _parts[key] = (owner, part);
        cancellation.check();
        if (event.kind == 'progress') onProgress(event.transferred);
        if (event.kind == 'done') transferred = event.transferred;
      }
      if (transferred == null) {
        throw const FileFailure('result_unknown', '传输结束但缺少最终字节回执。');
      }
      if (!push && !_parts.containsKey(key)) {
        throw const FileFailure('result_unknown', '传输完成但缺少精确暂存句柄。');
      }
      return transferred;
    } on adb.AdbException catch (error) {
      throw _failure(error);
    }
  }

  Future<adb.AdbFileExecutionStamp> _remoteStamp(
    DeviceConnection owner,
    String source,
    FileCancellation cancellation,
  ) async {
    adb.AdbFileExecutionStamp? stamp;
    await for (final event in _execute(
      owner,
      _request(adb.AdbFileExecutionKind.stat, source),
      cancellation,
    )) {
      cancellation.check();
      if (event.stamp case final value?) stamp = value;
    }
    return stamp ?? (throw const FileFailure('invalid_metadata', '未取得源文件快照。'));
  }

  @override
  Future<String> mutate(
    String device,
    String action,
    String path, {
    String destination = '',
    bool local = false,
    bool replace = false,
    required FileCancellation cancellation,
  }) async {
    _checkOpen();
    cancellation.check();
    if (local && action == 'mkdir') {
      try {
        if (!p.isAbsolute(path) || path.contains('\u0000')) {
          throw const FileFailure('invalid_path', '本机路径必须为绝对路径。');
        }
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const FileFailure('conflict', '创建目录时出现同名目标。');
        }
        await Directory(path).create();
        cancellation.check();
        return 'directoryCreated';
      } on FileSystemException catch (error) {
        throw FileFailure('io_error', error.message);
      }
    }
    final kind = switch (action) {
      'mkdir' => adb.AdbFileExecutionKind.mkdir,
      'rename' => adb.AdbFileExecutionKind.rename,
      'delete' => adb.AdbFileExecutionKind.delete,
      'commit' => adb.AdbFileExecutionKind.commit,
      'releasePart' => adb.AdbFileExecutionKind.releasePart,
      _ => throw const FileFailure('unsupported', '不支持的文件变更。'),
    };
    final key = (device, path);
    final held = _parts[key];
    if (local &&
        (kind == adb.AdbFileExecutionKind.commit ||
            kind == adb.AdbFileExecutionKind.releasePart) &&
        held == null) {
      if (kind == adb.AdbFileExecutionKind.releasePart) return 'released';
      throw const FileFailure('source_changed', '暂存句柄已失效，不能重新按路径打开。');
    }
    final owner = held?.$1 ?? await resolveConnection(device);
    String? receipt;
    await for (final event in _execute(
      owner,
      _request(
        kind,
        path,
        destination: destination,
        local: local,
        replace: replace,
        partId: held?.$2 ?? '',
      ),
      cancellation,
    )) {
      cancellation.check();
      if (event.kind == 'done') {
        receipt = event.saveMode;
        if (receipt != null &&
            (kind == adb.AdbFileExecutionKind.releasePart ||
                local && kind == adb.AdbFileExecutionKind.commit)) {
          _parts.remove(key);
        }
      }
    }
    if (receipt == null) {
      throw const FileFailure('result_unknown', '没有取得文件操作回执，请核对目标。');
    }
    if (kind == adb.AdbFileExecutionKind.releasePart ||
        (local && kind == adb.AdbFileExecutionKind.commit)) {
      _parts.remove(key);
    }
    return receipt;
  }
}

final class _AdbMutationBatch implements FileMutationBatch {
  _AdbMutationBatch(this.executor, this.connection, this.cancellation) {
    _unlisten = cancellation.onCancel(() {
      unawaited(
        close().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    });
  }

  final AdbFileExecutor executor;
  final DeviceConnection connection;
  final FileCancellation cancellation;
  final _sessions = <adb.AdbFileSession>{};
  Future<void>? _executing, _closing;
  late final void Function() _unlisten;
  bool _closed = false;

  @override
  Future<String> mutate(
    String action,
    String path, {
    String destination = '',
    FileStamp? expected,
  }) {
    cancellation.check();
    if (_closed) throw const FileFailure('cancelled', '文件变更已停止。');
    if (_executing != null) {
      throw const FileFailure('busy', '同一批文件变更必须逐项执行。');
    }
    final result = Completer<String>();
    final finished = Completer<void>();
    _executing = finished.future;
    unawaited(() async {
      try {
        result.complete(await _mutate(action, path, destination, expected));
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _executing = null;
        finished.complete();
      }
    }());
    return result.future;
  }

  Future<String> _mutate(
    String action,
    String path,
    String destination,
    FileStamp? expected,
  ) async {
    final kind = switch (action) {
      'mkdir' => adb.AdbFileExecutionKind.mkdir,
      'rename' => adb.AdbFileExecutionKind.rename,
      'delete' => adb.AdbFileExecutionKind.delete,
      _ => throw const FileFailure('unsupported', '不支持的文件变更。'),
    };
    if (action != 'mkdir' && expected?.identity == null) {
      throw const FileFailure('source_changed', '缺少所选文件的身份，请重新选择。');
    }
    adb.AdbFileSession? session;
    try {
      // 不把取消交给创建后的检查：迟到句柄必须先由本批登记，关闭失败才能精确重试。
      session = await connection.client.services
          .files(connection.device)
          .execute(
            executor._request(
              kind,
              path,
              destination: destination,
              expected: expected == null
                  ? null
                  : adb.AdbFileExecutionStamp(
                      identity: expected.identity,
                      mode: expected.mode,
                      size: expected.size,
                      modifiedSeconds: expected.modifiedSeconds,
                      modifiedNanos: expected.modifiedNanos,
                      nanosecondPrecision:
                          expected.modifiedResolutionNanos == 1,
                    ),
            ),
          );
      _sessions.add(session);
      cancellation.check();
      if (_closed) throw const FileFailure('cancelled', '文件变更已停止。');
      String? receipt;
      await for (final event in session.events) {
        cancellation.check();
        if (event.kind == 'done') receipt = event.saveMode;
      }
      cancellation.check();
      if (receipt == null) {
        throw const FileFailure('result_unknown', '未取得变更回执，请核对目标，不会自动重放。');
      }
      return receipt;
    } on adb.AdbException catch (error) {
      throw executor._failure(error);
    } finally {
      if (session != null) await _release(session);
    }
  }

  Future<void> _release(adb.AdbFileSession session) async {
    try {
      await session.close();
      _sessions.remove(session);
    } catch (error) {
      throw FileFailure('mutation_cleanup_unconfirmed', '文件变更资源尚未确认释放：$error');
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    _unlisten();
    return _closing ??= _close().whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _close() async {
    // 先关闭已交付句柄唤醒读取，再等待创建或执行交出迟到资源；不关闭共享 services。
    final running = _executing;
    Object? failure;
    for (final session in _sessions.toList()) {
      try {
        await _release(session);
      } catch (error) {
        failure = error;
      }
    }
    // 原生取消失败时读取可能仍阻塞；保留同一句柄并立即报告，不能永远等待读取终态。
    if (failure != null) throw failure;
    await running;
    for (final session in _sessions.toList()) {
      try {
        await _release(session);
      } catch (error) {
        failure = error;
      }
    }
    if (_sessions.isNotEmpty && failure != null) throw failure;
  }
}

/// 本对象在调用原生 create 前登记执行，关闭失败保留原 SDK 会话和迟到创建责任。
final class _AdbExecutionOwner implements FileExecutionResource {
  _AdbExecutionOwner(this.connection, {this.onReleased});
  final DeviceConnection connection;
  final void Function()? onReleased;
  final _sessions = <adb.AdbFileSession>{};
  final _readers = Map<adb.AdbFileSession, _AdbExecutionReader>.identity();
  final _pending = <Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  Stream<adb.AdbFileExecutionEvent> execute(
    adb.AdbFileExecutionRequest request,
    FileCancellation cancellation, {
    bool cleanup = false,
  }) async* {
    cancellation.check();
    if (_closed && !cleanup) throw const FileFailure('cancelled', '文件执行已停止。');
    final finished = Completer<void>();
    _pending.add(finished.future);
    adb.AdbFileSession? session;
    final cancellationCleanupFailed = Completer<Object>();
    final unlisten = cancellation.onCancel(() {
      unawaited(
        close().then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            if (!cancellationCleanupFailed.isCompleted) {
              cancellationCleanupFailed.complete(error);
            }
          },
        ),
      );
    });
    Object? failure;
    StackTrace? failureStack;
    try {
      // 不传创建后取消令牌：先保存实际迟到句柄，再检查本批准入。
      session = await connection.client.services
          .files(connection.device)
          .execute(request);
      _sessions.add(session);
      cancellation.check();
      if (_closed && !cleanup) throw const FileFailure('cancelled', '文件执行已停止。');
      final reader = _readers[session] = _AdbExecutionReader(session.events);
      unawaited(
        cancellationCleanupFailed.future.then<void>((error) {
          reader.interrupt(FileExecutionCleanupFailure(this, error));
        }),
      );
      while (await reader.moveNext()) {
        yield reader.current;
        cancellation.check();
      }
      cancellation.check();
    } catch (error, stack) {
      failure = error is adb.AdbException
          ? FileFailure(error.code, error.message)
          : error;
      failureStack = stack;
    } finally {
      unlisten();
      try {
        if (session != null) await _release(session);
      } catch (error, stack) {
        failure = FileExecutionCleanupFailure(
          this,
          failure == null ? error : (execution: failure, cleanup: error),
        );
        failureStack = stack;
      } finally {
        _pending.remove(finished.future);
        finished.complete();
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  Future<void> _release(adb.AdbFileSession session) async {
    try {
      await session.close();
      await _readers[session]?.close();
      _readers.remove(session);
      _sessions.remove(session);
    } catch (error) {
      throw FileFailure('file_cleanup_unconfirmed', '文件执行尚未实际退出：$error');
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _close().whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _close() async {
    Object? failure;
    for (final session in _sessions.toList()) {
      try {
        await _release(session);
      } catch (error) {
        failure ??= error;
      }
    }
    // 取消失败可能仍阻塞事件读取；不能等它自行结束后再报告回收失败。
    if (failure != null) throw failure;
    await Future.wait(_pending.toList());
    for (final session in _sessions.toList()) {
      try {
        await _release(session);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
    onReleased?.call();
  }
}

/// 原生 next 可以在取消失败后仍阻塞；读取者随原会话保留，不能随公开流结束遗弃。
final class _AdbExecutionReader {
  _AdbExecutionReader(Stream<adb.AdbFileExecutionEvent> events)
    : _iterator = StreamIterator(events);
  final StreamIterator<adb.AdbFileExecutionEvent> _iterator;
  Future<bool>? _moving;
  Completer<bool>? _waiting;
  Object? _interrupted;
  adb.AdbFileExecutionEvent get current => _iterator.current;

  void interrupt(Object error) {
    _interrupted ??= error;
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.completeError(error);
  }

  Future<bool> moveNext() {
    if (_interrupted case final error?) return Future.error(error);
    final waiting = _waiting = Completer<bool>();
    final moving = _moving = _iterator.moveNext();
    // 真实读取始终被观察并保留；取消只提前结束公开等待，不撤掉在途 next。
    unawaited(
      moving.then<void>(
        (value) {
          if (!waiting.isCompleted) waiting.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!waiting.isCompleted) waiting.completeError(error, stack);
        },
      ),
    );
    return waiting.future;
  }

  Future<void> close() async {
    try {
      await _moving;
    } catch (_) {
      // 原读取异常由执行回执保存；这里仅确认已在途读取实际结束。
    }
    await _iterator.cancel();
  }
}

final class _AdbReadBatch implements FileReadBatch {
  _AdbReadBatch(
    AdbFileExecutor parent,
    DeviceConnection connection,
    this.device,
    this.cancellation,
  ) : _owner = _AdbExecutionOwner(connection) {
    _executor = AdbFileExecutor._owned(parent, connection, _owner);
    _unlisten = cancellation.onCancel(() {
      unawaited(
        close().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    });
  }
  final String device;
  final FileCancellation cancellation;
  final _AdbExecutionOwner _owner;
  late final AdbFileExecutor _executor;
  late final void Function() _unlisten;
  bool _closed = false;
  Future<void>? _closing;

  void _check() {
    cancellation.check();
    if (_closed) throw const FileFailure('cancelled', '预览读取已停止。');
  }

  @override
  Future<FileStamp> stat(String path) {
    _check();
    return _executor.stat(
      device,
      path,
      local: false,
      cancellation: cancellation,
    );
  }

  @override
  Future<int> copy(
    String source,
    String temporary, {
    required FileStamp expected,
    required void Function(int) onProgress,
  }) {
    _check();
    return _executor.copy(
      device,
      source,
      temporary,
      push: false,
      expected: expected,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> commit(String temporary, String destination) async {
    _check();
    await _executor.mutate(
      device,
      'commit',
      temporary,
      destination: destination,
      local: true,
      cancellation: cancellation,
    );
  }

  @override
  Future<void> close() {
    _closed = true;
    _unlisten();
    return _closing ??= _close().whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _close() async {
    await _owner.close();
    _executor._cleaningParts = true;
    try {
      for (final key in _executor._parts.keys.toList()) {
        await _executor.mutate(
          device,
          'releasePart',
          key.$2,
          local: true,
          cancellation: FileCancellation(),
        );
      }
      await _owner.close();
    } finally {
      _executor._cleaningParts = false;
    }
  }
}
