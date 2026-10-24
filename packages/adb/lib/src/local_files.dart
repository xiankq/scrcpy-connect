import 'dart:async';
import 'dart:typed_data';

import 'api.dart' show AdbCancellation, adbTimeoutMillis;

/// 本机文件类型；符号链接不会作为普通文件自动跟随。
enum LocalFileKind { file, directory, symlink, other }

enum LocalFileErrorCode {
  invalidArgument,
  scopeClosed,
  notFound,
  busy,
  cancelled,
  timedOut,
  byteLimit,
  entryLimit,
  sourceChanged,
  targetChanged,
  conflict,
  resultUnknown,
  cleanupUnconfirmed,
  unsupported,
  io,
}

/// 保留实际已复制字节和目标可能已改变的事实，取消不等于回滚。
class LocalFileException implements Exception {
  const LocalFileException(
    this.code,
    this.message, {
    this.bytesCopied = 0,
    this.partialDestinationPossible = false,
  });
  final LocalFileErrorCode code;
  final String message;
  final int bytesCopied;
  final bool partialDestinationPossible;
  @override
  String toString() => 'LocalFileException(${code.name}, $message)';
}

/// 本机对象身份；无符号字段保留完整 64 位精度。
final class LocalFileIdentity {
  const LocalFileIdentity({
    required this.device,
    required this.inode,
    required this.size,
    required this.modifiedSeconds,
    required this.modifiedNanos,
    required this.kind,
  });
  final BigInt device, inode, size;
  final int modifiedSeconds, modifiedNanos;
  final LocalFileKind kind;
}

final class LocalFileStat {
  const LocalFileStat({required this.identity, this.freeBytes});
  final LocalFileIdentity identity;
  final BigInt? freeBytes;
}

final class LocalFileEntry {
  LocalFileEntry({required List<int> name, required this.identity})
    : name = Uint8List.fromList(name).asUnmodifiableView();
  final Uint8List name;
  final LocalFileIdentity identity;
}

/// 有界目录列举结果；超过调用方 maxEntries 时抛 entryLimit。
///
/// 各项身份用于后续操作核验，不承诺目录内所有文件内容的原子快照。
final class LocalFileList {
  LocalFileList({
    required this.identity,
    required Iterable<LocalFileEntry> entries,
  }) : entries = List.unmodifiable(entries);
  final LocalFileIdentity identity;
  final List<LocalFileEntry> entries;
}

enum LocalFileEndpointKind { path, part, descriptor }

/// 路径保留原始字节；描述符在原生 create 阶段复制，调用方仍须持有原始租约。
final class LocalFileEndpoint {
  LocalFileEndpoint.path(List<int> path)
    : kind = LocalFileEndpointKind.path,
      pathBytes = Uint8List.fromList(path).asUnmodifiableView(),
      descriptor = null;

  /// 本次复制独占创建的未发布片段；未 commit 的 close 会精确清理原对象。
  LocalFileEndpoint.part(List<int> path)
    : kind = LocalFileEndpointKind.part,
      pathBytes = Uint8List.fromList(path).asUnmodifiableView(),
      descriptor = null;

  /// 借入描述符：来源可为流；目标必须为空、可 seek 且可同步的普通文件。
  /// 原始描述符由调用方持有，须在 copy 或 scope 确认关闭后才能释放。
  const LocalFileEndpoint.fd(int fd)
    : kind = LocalFileEndpointKind.descriptor,
      pathBytes = null,
      descriptor = fd;
  final LocalFileEndpointKind kind;
  final Uint8List? pathBytes;
  final int? descriptor;
}

final class LocalFileCopyRequest {
  const LocalFileCopyRequest({
    required this.source,
    required this.target,
    required this.maxBytes,
    required this.timeoutMs,
    this.sourceOffset = 0,
    this.length,
    this.expectedSource,
  });
  final LocalFileEndpoint source, target;
  final int maxBytes, timeoutMs, sourceOffset;
  final int? length;
  final LocalFileIdentity? expectedSource;
}

final class LocalFileCopyResult {
  const LocalFileCopyResult({
    required this.bytes,
    required this.identity,
    required this.sourceIdentity,
  });
  final int bytes;
  final LocalFileIdentity identity, sourceIdentity;
}

/// 供不同原生宿主实现的窄传输接口；不暴露生成类型、文档命令或应用预算。
abstract interface class NativeLocalFilesApi {
  Future<String> openScope(
    String scopeKey,
    List<Uint8List> allowedRoots,
    int closeTimeoutMs,
  );
  Future<void> closeScope(String scopeId, int timeoutMs);
  Future<LocalFileStat> stat(String scopeId, Uint8List path);
  Future<LocalFileList> list(String scopeId, Uint8List path, int maxEntries);
  Future<void> mkdir(String scopeId, Uint8List path, bool exclusive);
  Future<void> remove(
    String scopeId,
    Uint8List path,
    LocalFileIdentity expectedIdentity,
  );
  Future<String> createCopy(String scopeId, LocalFileCopyRequest request);
  Future<LocalFileCopyResult> runCopy(String copyId);
  Future<void> cancelCopy(String copyId);
  Future<void> closeCopy(String copyId, int timeoutMs);
  Future<LocalFileIdentity> commit(
    String scopeId,
    String copyId,
    Uint8List destination,
    LocalFileIdentity expectedIdentity,
  );
}

/// 管理本机目录能力与复制租约；关闭后永久停止准入，未确认清理可以重试。
final class LocalFiles {
  LocalFiles(this._api);
  final NativeLocalFilesApi _api;
  final _scopes = <LocalFileScope>{};
  final _opening = <Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<LocalFileScope> openScope({
    required String scopeKey,
    required List<Uint8List> allowedRoots,
    Duration closeTimeout = const Duration(seconds: 7),
  }) {
    _checkOpen(_closed);
    if (scopeKey.isEmpty || scopeKey.contains('\u0000')) {
      throw ArgumentError.value(scopeKey, 'scopeKey');
    }
    final closeTimeoutMs = adbTimeoutMillis(closeTimeout);
    final roots = [for (final root in allowedRoots) _path(root)];
    return _tracked(_opening, () async {
      final id = await _api.openScope(scopeKey, roots, closeTimeoutMs);
      final scope = LocalFileScope._(_api, id, _scopes.remove);
      _scopes.add(scope);
      if (_closed) {
        await scope.close();
        _checkOpen(true);
      }
      return scope;
    });
  }

  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      // 已经开始的 scope 登记必须真实返回；迟到登记会立即进入关闭流程。
      await Future.wait(_opening.toList());
      await _releaseAll([for (final scope in _scopes.toList()) scope.close()]);
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

final class LocalFileScope {
  LocalFileScope._(this._api, this._id, this._onClosed);
  final NativeLocalFilesApi _api;
  final String _id;
  final void Function(LocalFileScope) _onClosed;
  final _pending = <Future<void>>{};
  final _copies = <LocalFileCopy>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<T> _operation<T>(Future<T> Function() action) {
    _checkOpen(_closed);
    return _tracked(_pending, action);
  }

  Future<LocalFileStat> stat(Uint8List path) =>
      _operation(() => _api.stat(_id, _path(path)));
  Future<LocalFileList> list(Uint8List path, {required int maxEntries}) {
    if (maxEntries < 1 || maxEntries > 0xffffffff) {
      throw ArgumentError.value(maxEntries, 'maxEntries');
    }
    return _operation(() => _api.list(_id, _path(path), maxEntries));
  }

  Future<void> mkdir(Uint8List path, {bool exclusive = true}) =>
      _operation(() => _api.mkdir(_id, _path(path), exclusive));
  Future<void> remove(
    Uint8List path, {
    required LocalFileIdentity expectedIdentity,
  }) => _operation(() => _api.remove(_id, _path(path), expectedIdentity));

  /// 复制并保留提交或清理租约；来源描述符可为流，非零偏移仅适用于普通文件。
  /// 目标可为独占创建的片段，或为空、可 seek 且可同步的普通文件描述符。
  /// 调用方必须明确提供字节上限和期限；外部流式写目标会返回 unsupported。
  Future<LocalFileCopy> copy({
    required LocalFileEndpoint source,
    required LocalFileEndpoint target,
    required int maxBytes,
    required Duration timeout,
    LocalFileIdentity? expectedSource,
    int sourceOffset = 0,
    int? length,
    AdbCancellation? cancellation,
  }) {
    _checkOpen(_closed);
    _checkCancellation(cancellation);
    if (source.kind == LocalFileEndpointKind.part ||
        target.kind == LocalFileEndpointKind.path ||
        maxBytes < 0 ||
        sourceOffset < 0 ||
        (length != null && length < 0)) {
      throw ArgumentError('Invalid local copy endpoints or limits');
    }
    final request = LocalFileCopyRequest(
      source: source,
      target: target,
      maxBytes: maxBytes,
      timeoutMs: adbTimeoutMillis(timeout),
      expectedSource: expectedSource,
      sourceOffset: sourceOffset,
      length: length,
    );
    return _operation(() async {
      final id = await _api.createCopy(_id, request);
      final copy = LocalFileCopy._(_api, id, this, target.descriptor != null);
      _copies.add(copy);
      final unwatch = cancellation?.onCancel(() {
        unawaited(copy.close().catchError((Object _) {}));
      });
      try {
        _checkOpen(_closed);
        _checkCancellation(cancellation);
        copy._result = await _api.runCopy(id);
        if (_closed || (cancellation?.isCancelled ?? false)) {
          throw LocalFileException(
            _closed
                ? LocalFileErrorCode.scopeClosed
                : LocalFileErrorCode.cancelled,
            '复制已完成，但调用方已经撤销交付。',
            bytesCopied: copy.bytes,
            partialDestinationPossible:
                target.descriptor != null && copy.bytes > 0,
          );
        }
        return copy;
      } catch (error, stack) {
        try {
          await copy.close();
        } catch (cleanup, cleanupStack) {
          final original = error is LocalFileException ? error : null;
          final release = cleanup is LocalFileException ? cleanup : null;
          final originalBytes = original?.bytesCopied ?? 0;
          final releaseBytes = release?.bytesCopied ?? 0;
          // 清理失败不能抹掉原复制已经产生的字节与外部写入事实。
          Error.throwWithStackTrace(
            LocalFileException(
              release?.code ?? LocalFileErrorCode.cleanupUnconfirmed,
              '复制回收尚未确认：$cleanup；原复制结果：$error',
              bytesCopied: originalBytes > releaseBytes
                  ? originalBytes
                  : releaseBytes,
              partialDestinationPossible:
                  (original?.partialDestinationPossible ?? false) ||
                  (release?.partialDestinationPossible ?? false),
            ),
            cleanupStack,
          );
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        unwatch?.call();
      }
    });
  }

  /// 发布精确片段；成功或结果未知后，不可把同一片段重新发布到其他位置。
  Future<LocalFileIdentity> commit(
    LocalFileCopy copy,
    Uint8List destination, {
    required LocalFileIdentity expectedIdentity,
  }) {
    if (!identical(copy._scope, this) || copy._closed) {
      throw const LocalFileException(
        LocalFileErrorCode.scopeClosed,
        '复制租约不属于当前有效 scope。',
      );
    }
    return _operation(
      () => _api.commit(_id, copy._id, _path(destination), expectedIdentity),
    );
  }

  /// 先取消原生 worker，再等全部迟到登记与真实流释放；失败保留同一所有者供重试。
  Future<void> close({Duration timeout = const Duration(seconds: 7)}) {
    final timeoutMs = adbTimeoutMillis(timeout);
    _closed = true;
    return _closing ??= _close(timeoutMs);
  }

  Future<void> _close(int timeoutMs) async {
    try {
      // native 未确认排空时立即交还失败和重试权，不能无界等待仍阻塞的 run。
      await _api.closeScope(_id, timeoutMs);
      await Future.wait(_pending.toList()).timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () => throw const LocalFileException(
          LocalFileErrorCode.cleanupUnconfirmed,
          '原生已释放资源，但迟到调用回执尚未完整收回。',
        ),
      );
      // 原生 scope 回执已经覆盖所有 copy 的取消、排空和未发布片段清理。
      for (final copy in _copies.toList()) {
        copy._released();
      }
      _onClosed(this);
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

/// 复制完成后的片段/描述符租约；保留到 commit 与平台结果核验完成，再 close。
final class LocalFileCopy {
  LocalFileCopy._(this._api, this._id, this._scope, this._externalTarget);
  final NativeLocalFilesApi _api;
  final String _id;
  final LocalFileScope _scope;
  final bool _externalTarget;
  LocalFileCopyResult? _result;
  LocalFileCopyResult get result => _result!;
  int get bytes => result.bytes;
  LocalFileIdentity get identity => result.identity;
  LocalFileIdentity get sourceIdentity => result.sourceIdentity;
  bool _closed = false;
  Future<void>? _closing;

  /// 未发布 path 精确删除；provider 描述符仅释放复制件，不删除外部文档。
  Future<void> close({Duration timeout = const Duration(seconds: 7)}) {
    final timeoutMs = adbTimeoutMillis(timeout);
    _closed = true;
    return _closing ??= _close(timeoutMs);
  }

  Future<void> _close(int timeoutMs) async {
    try {
      // close 自身也撤销 worker；通知失败不覆盖最终已经确认的 drain 回执。
      final notification = Future<void>.sync(() => _api.cancelCopy(_id))
          .catchError((Object _) {});
      await _api.closeCopy(_id, timeoutMs);
      await notification;
      _released();
    } catch (error, stack) {
      _closing = null;
      final failure = error is LocalFileException ? error : null;
      final knownBytes = _result?.bytes ?? 0;
      final failedBytes = failure?.bytesCopied ?? 0;
      // close 没有确认排空时，调用方不能释放借入的原描述符或忘记重试权。
      Error.throwWithStackTrace(
        LocalFileException(
          LocalFileErrorCode.cleanupUnconfirmed,
          '本机复制租约尚未确认释放：$error',
          bytesCopied: knownBytes > failedBytes ? knownBytes : failedBytes,
          partialDestinationPossible:
              (failure?.partialDestinationPossible ?? false) ||
              (_externalTarget && knownBytes > 0),
        ),
        stack,
      );
    }
  }

  void _released() {
    _closed = true;
    _scope._copies.remove(this);
    _closing ??= Future<void>.value();
  }
}

Uint8List _path(List<int> value) {
  if (value.isEmpty || value.contains(0)) {
    throw ArgumentError('Invalid local path');
  }
  return Uint8List.fromList(value).asUnmodifiableView();
}

void _checkOpen(bool closed) {
  if (closed) {
    throw const LocalFileException(
      LocalFileErrorCode.scopeClosed,
      '本机文件作用域已关闭。',
    );
  }
}

void _checkCancellation(AdbCancellation? cancellation) {
  if (cancellation?.isCancelled ?? false) {
    throw const LocalFileException(LocalFileErrorCode.cancelled, '本机复制已取消。');
  }
}

Future<T> _tracked<T>(Set<Future<void>> pending, Future<T> Function() action) {
  final done = Completer<void>();
  pending.add(done.future);
  return Future<T>.sync(action).whenComplete(() {
    pending.remove(done.future);
    done.complete();
  });
}

Future<void> _releaseAll(List<Future<void>> operations) async {
  Object? failure;
  StackTrace? trace;
  await Future.wait([
    for (final operation in operations)
      () async {
        try {
          await operation;
        } catch (error, stack) {
          failure ??= error;
          trace ??= stack;
        }
      }(),
  ]);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}
