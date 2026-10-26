part of 'api.dart';

/// 文件助手为调用方明确注入的、与设备 ABI 对应的可执行字节。
final class AdbFileHelper {
  AdbFileHelper(this.abi, List<int> bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String abi;
  final Uint8List bytes;
}

enum AdbFileExecutionKind {
  stat,
  list,
  copy,
  mkdir,
  rename,
  delete,
  commit,
  releasePart,
}

/// 不将秒级设备时间伪装成纳秒精度；比较快照时也必须比较精度标志。
final class AdbFileExecutionStamp {
  const AdbFileExecutionStamp({
    this.identity,
    required this.mode,
    required this.size,
    required this.modifiedSeconds,
    required this.modifiedNanos,
    required this.nanosecondPrecision,
  });
  final String? identity;
  final int mode, size, modifiedSeconds, modifiedNanos;
  final bool nanosecondPrecision;
}

/// 原始绝对路径在构造时复制；不做 Unicode 替换或 shell 展开。
/// copy 的 path 是源、destination 是暂存目标；push 决定传输方向。
/// 本机 commit/releasePart 必须携带 copy 完成时返回的精确 partId。
final class AdbFileExecutionRequest {
  AdbFileExecutionRequest({
    required this.kind,
    required List<int> path,
    List<int> destination = const [],
    this.local = false,
    this.followStorageAlias = false,
    this.limit = 10000,
    this.push = false,
    this.replace = false,
    this.expected,
    this.partId = '',
    this.scopeId = '',
  }) : path = Uint8List.fromList(path).asUnmodifiableView(),
       destination = Uint8List.fromList(destination).asUnmodifiableView();
  final AdbFileExecutionKind kind;
  final Uint8List path, destination;
  final bool local, followStorageAlias, push, replace;
  final int limit;
  final AdbFileExecutionStamp? expected;
  final String partId;

  /// 空串明确不使用作用域；非空句柄由原生核验，旧代请求不会退回无作用域执行。
  final String scopeId;

  AdbFileExecutionRequest _inScope(String id) => AdbFileExecutionRequest(
    kind: kind,
    path: path,
    destination: destination,
    local: local,
    followStorageAlias: followStorageAlias,
    limit: limit,
    push: push,
    replace: replace,
    expected: expected,
    partId: partId,
    scopeId: id,
  );
}

final class AdbFileExecutionEntry {
  AdbFileExecutionEntry({
    required List<int> name,
    this.stamp,
    this.errorCode,
    this.errorMessage,
    this.errno,
  }) : name = Uint8List.fromList(name).asUnmodifiableView();
  final Uint8List name;
  final AdbFileExecutionStamp? stamp;
  final String? errorCode, errorMessage;
  final int? errno;
}

/// 单个执行事实；done 才是已确认结果，result_unknown 必须交给调用方核对。
final class AdbFileExecutionEvent {
  AdbFileExecutionEvent({
    required this.kind,
    List<AdbFileExecutionEntry> entries = const [],
    this.stamp,
    this.transferred = 0,
    this.truncated = false,
    this.saveMode,
    this.partId,
    this.errorCode,
    this.errorMessage,
    this.errno,
  }) : entries = List.unmodifiable(entries);
  final String kind;
  final List<AdbFileExecutionEntry> entries;
  final AdbFileExecutionStamp? stamp;
  final int transferred;
  final bool truncated;
  final String? saveMode, partId, errorCode, errorMessage;
  final int? errno;
}

/// 由同一原生宿主实现；独立于旧服务接口，旧适配器可明确不提供宽文件能力。
abstract interface class NativeAdbFileApi {
  Future<void> initializeFileHelpers(List<AdbFileHelper> helpers);
  Future<String> fileExecute(
    String connectionId,
    AdbFileExecutionRequest request,
    int timeoutMs,
  );
  Future<AdbFileExecutionEvent?> fileNext(String operationId);
  Future<void> fileCancel(String operationId);
}

/// 同一宿主内的文件执行代际，不要求不提供此能力的旧适配器实现。
abstract interface class NativeAdbFileScopeApi {
  Future<String> fileScopeAttach(String ownerKey);
  Future<void> fileScopeClose(String scopeId);
}

/// 原子核验准入后交接文件域；准入撤销须等待所属文件执行真正排空。
abstract interface class NativeAdbScopedFileScopeApi
    implements NativeAdbFileScopeApi {
  Future<String> fileScopeAttachScoped(
    String ownerKey,
    String admissionScopeId,
  );
}

/// 以稳定拥有者名称重新附着时，原生先撤销旧代，再排空其 worker 与本机流。
/// 成功返回新句柄后才可清理旧暂存目录；不关闭设备 Client，也不证明远端操作回滚。
final class AdbFileScope extends _AdbResource {
  AdbFileScope._(super._owner, this._api, this.id, this._ownerKey);
  final NativeAdbFileScopeApi _api;
  final String id;
  final String _ownerKey;
  bool _closed = false, _released = false;
  Future<void>? _closing;

  void _checkOpen() {
    _owner._checkOpen();
    if (_closed) throw const AdbException('file_scope_closed');
  }

  AdbFiles files(AdbDevice device) {
    _checkOpen();
    return AdbFiles._(_owner, device, this);
  }

  /// 清理失败后保持撤销状态并保留精确句柄，显式再次 close 可重试。
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await _api.fileScopeClose(id);
      _released = true;
      _onClosed();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

/// 一个文件 worker 的取消所有权。事件单订阅且按消费拉取，暂停不会无限缓存。
/// close 排空本机 worker/流，不能证明远端变更回滚或远端进程已经退出。
final class AdbFileSession extends _AdbOperation {
  AdbFileSession._(
    this._api,
    this.id,
    super._owner,
    this._connectionId,
    this._request,
    this._scope,
  );
  final NativeAdbFileApi _api;
  final String id;
  final String _connectionId;
  final AdbFileExecutionRequest _request;
  final AdbFileScope? _scope;
  Future<AdbFileExecutionEvent?>? _pendingRead;
  String? _unclaimedPart, _releaseWorker;
  bool _releaseConfirmed = false, _restartRelease = false;
  bool _reading = false, _closed = false;
  Future<void>? _closing;

  Stream<AdbFileExecutionEvent> get events async* {
    if (_reading) throw const AdbException('file_operation_has_a_reader');
    if (_closed) throw const AdbException('file_operation_closed');
    _reading = true;
    try {
      while (true) {
        if (_closed) throw const AdbException('cancelled');
        final read = _pendingRead = _api.fileNext(id);
        final event = await read;
        _pendingRead = null;
        // 关闭会等待此读取并接管迟到 part；拒绝事件不会丢失精确回收权。
        if (_closed) {
          _retainUnclaimedPart(event);
          throw const AdbException('cancelled');
        }
        if (event == null) {
          throw const AdbException('result_unknown', '文件执行未返回终态回执。');
        }
        if (event.errorCode case final code?) {
          throw AdbException(code, event.errorMessage ?? '');
        }
        yield event;
        if (event.kind == 'done') break;
      }
    } finally {
      await close();
    }
  }

  /// 失败保留所有权和重试入口，不把未确认的回收当成已关闭。
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    final read = _pendingRead;
    _unsubscribe?.call();
    _unsubscribe = null;
    try {
      // 先唤醒阻塞读取，再等待其交接；原生 next 交出的 part 已不归 fileCancel 回收。
      await _api.fileCancel(id);
      if (read != null) {
        AdbFileExecutionEvent? event;
        try {
          event = await read;
        } catch (_) {
          // 读取错误由事件消费者处理；关闭仍负责已经登记的原生资源。
        }
        _retainUnclaimedPart(event);
      }
      await _releaseUnclaimedPart();
      _onClosed();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }

  void _retainUnclaimedPart(AdbFileExecutionEvent? event) {
    if (event case AdbFileExecutionEvent(
      kind: 'done',
      partId: final String part,
    )) {
      _unclaimedPart = part;
    }
  }

  Future<void> _releaseUnclaimedPart() async {
    final part = _unclaimedPart;
    if (part == null) return;
    final scope = _scope;
    if (scope != null) {
      final retiring = scope._closing;
      if (retiring != null) await retiring;
      if (scope._released) {
        // 原生 scope 关闭已确认其全部 part 回收，不能向已撤销作用域重新准入清理。
        if (_releaseWorker case final worker?) await _api.fileCancel(worker);
        _unclaimedPart = null;
        _releaseWorker = null;
        _releaseConfirmed = false;
        _restartRelease = false;
        return;
      }
    }
    if (_restartRelease) {
      // 上次读取失败，先确认旧清理 worker 已回收，再重发幂等的精确 releasePart。
      await _api.fileCancel(_releaseWorker!);
      _releaseWorker = null;
      _restartRelease = false;
    }
    final worker = _releaseWorker ??= await _api.fileExecute(
      _connectionId,
      AdbFileExecutionRequest(
        kind: AdbFileExecutionKind.releasePart,
        path: _request.destination,
        local: true,
        partId: part,
        scopeId: _request.scopeId,
      ),
      15000,
    );
    if (!_releaseConfirmed) {
      try {
        while (true) {
          final event = await _api.fileNext(worker);
          if (event == null) throw const AdbException('result_unknown');
          if (event.errorCode case final code?) {
            throw AdbException(code, event.errorMessage ?? '');
          }
          if (event.kind == 'done') break;
        }
        _releaseConfirmed = true;
      } catch (_) {
        // 保留 part 和 worker，显式 close 重试前不能撤销所有权。
        _restartRelease = true;
        rethrow;
      }
    }
    await _api.fileCancel(worker);
    _unclaimedPart = null;
    _releaseWorker = null;
    _releaseConfirmed = false;
  }
}

/// 文件事实与单次执行，不包含递归任务、缓存预算、分享交付或设备业务身份。
final class AdbFiles {
  AdbFiles._(this._services, this.device, [this._scope]);
  final AdbServices _services;
  final AdbDevice device;
  final AdbFileScope? _scope;

  Future<AdbFileSession> execute(
    AdbFileExecutionRequest request, {
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) => _services._start(() async {
    _services._checkOpen();
    final scope =
        _scope ??
        _services._fileScopes
            .where((scope) => scope.id == request.scopeId)
            .firstOrNull;
    // 显式传入本 facade 的 scopeId 仍共享同一关闭确认，不能另造无所属的清理路径。
    scope?._checkOpen();
    if (_scope case final scope?) {
      if (request.scopeId.isNotEmpty && request.scopeId != scope.id) {
        throw const AdbException('file_scope_mismatch');
      }
      request = request._inScope(scope.id);
    }
    cancellation?.check();
    final binding = _services._bindings();
    if (binding is! NativeAdbFileApi) {
      throw const AdbException('file_capability_unavailable');
    }
    final api = binding as NativeAdbFileApi;
    final connection = await _services._resolve(device);
    _services._checkOpen();
    scope?._checkOpen();
    cancellation?.check();
    final id = await api.fileExecute(
      connection.id,
      request,
      adbTimeoutMillis(timeout),
    );
    // 先登记精确关闭权；迟到取消失败仍由 facade 保留并重试。
    return _services._ownFile(
      api,
      id,
      cancellation,
      scope,
      connection.id,
      request,
    );
  });

  Future<AdbFileExecutionStamp> stat(
    List<int> path, {
    bool local = false,
    bool followStorageAlias = false,
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    final session = await execute(
      AdbFileExecutionRequest(
        kind: AdbFileExecutionKind.stat,
        path: path,
        local: local,
        followStorageAlias: followStorageAlias,
      ),
      timeout: timeout,
      cancellation: cancellation,
    );
    AdbFileExecutionStamp? stamp;
    await for (final event in session.events) {
      if (event.stamp case final value?) stamp = value;
    }
    return stamp ?? (throw const AdbException('missing_file_metadata'));
  }
}

/// 本机事实仍保留原始名称与 lstat 语义，不要求创建 ADB 连接。
final class AdbLocalFileFacts {
  AdbLocalFileFacts(
    List<AdbFileExecutionEntry> entries, {
    required this.truncated,
  }) : entries = List.unmodifiable(entries);
  final List<AdbFileExecutionEntry> entries;
  final bool truncated;
}

abstract interface class NativeAdbLocalFileApi {
  Future<AdbFileExecutionStamp> localFileStat(Uint8List path);
  Future<AdbLocalFileFacts> localFileList(Uint8List path, int limit);
}

extension AdbLocalFiles on AdbServices {
  Future<AdbFileExecutionStamp> localFileStat(List<int> path) {
    _checkOpen();
    final bindings = _bindings();
    if (bindings is! NativeAdbLocalFileApi) {
      throw const AdbException('local_file_capability_unavailable');
    }
    return (bindings as NativeAdbLocalFileApi).localFileStat(
      Uint8List.fromList(path),
    );
  }

  Future<AdbLocalFileFacts> localFileList(List<int> path, {int limit = 10000}) {
    _checkOpen();
    if (limit < 1 || limit > 10000) throw ArgumentError.value(limit, 'limit');
    final bindings = _bindings();
    if (bindings is! NativeAdbLocalFileApi) {
      throw const AdbException('local_file_capability_unavailable');
    }
    return (bindings as NativeAdbLocalFileApi).localFileList(
      Uint8List.fromList(path),
      limit,
    );
  }
}
