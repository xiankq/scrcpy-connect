part of 'api.dart';

abstract base class _AdbResource {
  _AdbResource(this._owner);
  final AdbServices _owner;

  void _onClosed() => _owner._resources.remove(this);
  Future<void> close();
}

abstract base class _AdbOperation extends _AdbResource {
  _AdbOperation(super._owner);

  void Function()? _unsubscribe;
}

/// 单个原生操作；事件采用单订阅和拉取模式。
/// 最多允许一个在途写入且每次至多 64 KiB，读写独立推进；close 取消并排空本操作，不关闭连接。
final class AdbServiceSession extends _AdbOperation {
  AdbServiceSession._(this._api, this.id, super._owner);
  final NativeAdbApi _api;
  final String id;
  bool _reading = false, _writing = false, _closed = false;
  Future<void>? _closing;
  StreamIterator<List<int>>? _input;
  Stream<NativeAdbEvent> get events async* {
    if (_reading) throw const AdbException('service_has_a_reader');
    if (_closed) throw const AdbException('service_closed');
    _reading = true;
    try {
      while (true) {
        if (_closed) throw const AdbException('cancelled');
        final event = await _api.next(id);
        // 原生返回不等于 Dart 已接纳；取消在 await 续体前生效时，丢弃迟到回执。
        if (_closed) throw const AdbException('cancelled');
        if (event == null) {
          throw const AdbException('result_unknown', '服务未返回终态回执。');
        }
        yield event;
        if (event.done) break;
      }
    } finally {
      await close();
    }
  }

  Future<void> _send(AdbServiceInput input) async {
    if (_closed) throw const AdbException('service_closed');
    if (_writing) throw const AdbException('service_has_a_writer');
    if (input.bytes.length > 65536) throw const AdbException('input_limit');
    _writing = true;
    try {
      await _api.write(id, input);
    } finally {
      _writing = false;
    }
  }

  Future<void> write(Uint8List bytes) =>
      _send(AdbServiceInput(AdbInputKind.bytes, bytes: bytes));
  Future<void> addStream(Stream<List<int>> source) async {
    if (_closed) throw const AdbException('service_closed');
    if (_input != null) throw const AdbException('service_has_an_input_stream');
    final iterator = StreamIterator(source);
    _input = iterator;
    try {
      // close() 取消此单一迭代器；不能逐包添加待完成的关闭监听，以保持长传输资源有界。
      while (await iterator.moveNext()) {
        if (_closed) throw const AdbException('service_closed');
        final bytes = iterator.current;
        for (var start = 0; start < bytes.length; start += 65536) {
          final end = start + 65536 < bytes.length
              ? start + 65536
              : bytes.length;
          await write(Uint8List.fromList(bytes.sublist(start, end)));
        }
      }
      if (_closed) throw const AdbException('service_closed');
    } finally {
      await iterator.cancel();
      if (identical(_input, iterator)) _input = null;
    }
  }

  Future<void> closeStdin() => _send(AdbServiceInput(AdbInputKind.closeStdin));
  Future<void> resize(int rows, int columns) {
    if (rows <= 0 || rows > 65535 || columns <= 0 || columns > 65535) {
      throw ArgumentError('Invalid terminal size');
    }
    return _send(
      AdbServiceInput(AdbInputKind.resize, rows: rows, columns: columns),
    );
  }

  /// 完成流式 SYNC push 的输入文件；原始 ADB 操作没有通用半关闭，shell 使用 closeStdin。
  Future<void> finish() => _send(AdbServiceInput(AdbInputKind.finish));
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    try {
      await Future.wait<void>([
        _api.cancel(id),
        if (_input case final iterator?) iterator.cancel(),
      ]);
      _onClosed();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

/// 已有 ADB 协议，不负责产品浏览、传输日志、身份持久化或重试、重连策略。
final class AdbServices {
  AdbServices(this._bindings, this._resolve, this._check);
  final NativeAdbApi Function() _bindings;
  final Future<AdbDevice> Function(AdbDevice) _resolve;
  final void Function() _check;
  final Set<_AdbResource> _resources = {};
  Iterable<AdbFileScope> get _fileScopes =>
      _resources.whereType<AdbFileScope>();
  final Map<String, Future<void>> _fileScopeTransitions = {};
  final Set<Future<Object?>> _starting = {};
  bool _closed = false;
  Future<void>? _closing;
  void _checkOpen() {
    _check();
    if (_closed) throw const AdbException('closed');
  }

  /// 创建请求一开始就登记；直到迟到句柄已登记并尝试回收才释放此等待。
  Future<T> _start<T>(Future<T> Function() create) {
    late final Future<T> opening;
    opening = Future<T>.sync(() {
      _checkOpen();
      return create();
    }).whenComplete(() => _starting.remove(opening));
    _starting.add(opening);
    return opening;
  }

  Future<T> _own<T extends _AdbOperation>(
    T operation,
    AdbCancellation? cancellation, {
    void Function()? checkScope,
    Object Function(Object)? cleanupFailure,
  }) async {
    // 先登记关闭权；失败的回收不能丢失于迟到创建的异常路径。
    _resources.add(operation);
    try {
      _checkOpen();
      checkScope?.call();
      cancellation?.check();
    } catch (_) {
      try {
        await operation.close();
      } catch (error) {
        if (cleanupFailure != null) throw cleanupFailure(error);
        rethrow;
      }
      rethrow;
    }
    if (cancellation != null) {
      operation._unsubscribe = cancellation.onCancel(() {
        unawaited(
          operation.close().catchError((Object _) {
            // 所有权仍在集合中，由显式 close 或 facade.close 核对和重试。
          }),
        );
      });
    }
    return operation;
  }

  Future<AdbServiceSession> _ownService(
    NativeAdbApi api,
    String id,
    AdbCancellation? cancellation,
  ) => _own(AdbServiceSession._(api, id, this), cancellation);

  /// 创建兼容旧版 shell 协议的精确会话；与显式 shell v2/PTY 入口共享关闭责任。
  Future<AdbServiceSession> openShell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) => _start(() async {
    cancellation?.check();
    final timeoutMs = adbTimeoutMillis(timeout);
    final resolved = await _resolve(device);
    _checkOpen();
    cancellation?.check();
    final api = _bindings();
    return _ownService(
      api,
      await api.shell(resolved.id, command, timeoutMs),
      cancellation,
    );
  });

  /// 普通 shell 与显式服务共用本登记，统一转换输出和退出事件。
  Stream<AdbShellEvent> shellEvents(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    final session = await openShell(
      device,
      command,
      timeout: timeout,
      cancellation: cancellation,
    );
    await for (final event in session.events) {
      switch (event.kind) {
        case 'stdout':
          yield AdbShellEvent(AdbShellChannel.stdout, event.bytes);
        case 'stderr':
          yield AdbShellEvent(AdbShellChannel.stderr, event.bytes);
        case 'exit':
          yield AdbShellEvent(
            AdbShellChannel.exit,
            Uint8List(0),
            exitCode: event.exitCode,
          );
        default:
          throw const AdbException('invalid_native_shell_event');
      }
    }
  }

  Future<AdbFileSession> _ownFile(
    NativeAdbFileApi api,
    String id,
    AdbCancellation? cancellation,
    AdbFileScope? scope,
    String connectionId,
    AdbFileExecutionRequest request,
  ) => _own(
    AdbFileSession._(api, id, this, connectionId, request, scope),
    cancellation,
    checkScope: scope?._checkOpen,
  );

  /// 释放此 facade 的操作；设备连接仍由调用方持有。
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    Object? failure;
    StackTrace? trace;
    Future<void> release(Future<void> operation) async {
      try {
        await operation;
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }

    try {
      final resources = _resources.toSet();
      await Future.wait<void>([
        for (final resource in resources) release(resource.close()),
      ]);
      await Future.wait<void>([
        for (final opening in _starting.toList())
          opening.then<void>((_) {}, onError: (Object _) {}),
      ]);
      await Future.wait<void>([
        for (final resource in _resources.difference(resources))
          release(resource.close()),
      ]);
      if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    } catch (_) {
      // 仍登记的资源可继续回收；关闭准入独立于本次回收 Future，失败也不会重新开放。
      _closing = null;
      rethrow;
    }
  }

  Future<AdbConnectionFacts> connectionFacts(AdbDevice device) async {
    _checkOpen();
    return _bindings().connectionFacts((await _resolve(device)).id);
  }

  /// 探测单次服务 OPEN，不消费服务数据，也不产生重试、阈值或连接健康政策。
  /// 取消只关闭本次探针；调用方仍须显式 close 确认回收，失败可用同句柄重试。
  /// 创建迟到且无法回收时抛 [AdbOpenProbeCleanupFailure]，保留其中的 probe 精确重试。
  Future<AdbOpenProbe> createOpenProbe(
    AdbDevice device, {
    required String service,
    required Duration timeout,
    AdbCancellation? cancellation,
  }) => _start(() async {
    cancellation?.check();
    validateAdbPath(service);
    if (utf8.encode(service).length > 65535) {
      throw ArgumentError.value(service, 'service');
    }
    final timeoutMs = adbTimeoutMillis(timeout);
    final bindings = _bindings();
    if (bindings is! NativeAdbOpenProbeApi) {
      throw const AdbException('unsupported', '原生适配器不支持 OPEN 探测。');
    }
    final api = bindings as NativeAdbOpenProbeApi;
    final connection = await _resolve(device);
    _checkOpen();
    cancellation?.check();
    final id = await api.createOpenProbe(connection.id, service, timeoutMs);
    final probe = AdbOpenProbe._(api, id, this);
    return _own(
      probe,
      cancellation,
      cleanupFailure: (error) => AdbOpenProbeCleanupFailure(probe, error),
    );
  });

  Future<AdbServiceSession> _service(
    AdbDevice device,
    AdbServiceRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) => _start(() async {
    _checkOpen();
    cancellation?.check();
    if (request.maxOutput <= 0 || request.maxOutput > 16 * 1024 * 1024) {
      throw ArgumentError.value(request.maxOutput, 'maxOutput');
    }
    final api = _bindings();
    final connection = await _resolve(device);
    _checkOpen();
    cancellation?.check();
    final id = await api.service(
      connection.id,
      request,
      adbTimeoutMillis(timeout),
    );
    return _ownService(api, id, cancellation);
  });

  Future<AdbServiceSession> open(
    AdbDevice device,
    String service, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) {
    validateAdbPath(service);
    return _service(
      device,
      AdbServiceRequest(AdbServiceKind.raw, service: service),
      timeout,
      cancellation,
    );
  }

  Future<AdbServiceSession> connectSocket(
    AdbDevice device,
    AdbSocket socket, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) => open(
    device,
    socket.service,
    timeout: timeout,
    cancellation: cancellation,
  );
  Future<AdbServiceSession> exec(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) => _service(
    device,
    AdbServiceRequest(AdbServiceKind.exec, service: command),
    timeout,
    cancellation,
  );

  /// 要求 shell_v2；旧式非交互 shell 仍使用 AdbClient.shell。
  Future<AdbServiceSession> shell(
    AdbDevice device,
    String command, {
    bool pty = false,
    int maxPacket = 65536,
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) => _service(
    device,
    AdbServiceRequest(
      pty ? AdbServiceKind.shellPty : AdbServiceKind.shellRaw,
      service: command,
      maxOutput: maxPacket,
    ),
    timeout,
    cancellation,
  );
  Future<AdbServiceSession> abb(
    AdbDevice device,
    List<String> arguments, {
    bool exec = false,
    int maxPacket = 65536,
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) => _service(
    device,
    AdbServiceRequest(
      exec ? AdbServiceKind.abbExec : AdbServiceKind.abb,
      arguments: List.unmodifiable(arguments),
      maxOutput: maxPacket,
    ),
    timeout,
    cancellation,
  );
  Stream<AdbShellEvent> cmd(
    AdbDevice device,
    List<String> arguments, {
    int maxOutput = 1024 * 1024,
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    final session = await _service(
      device,
      AdbServiceRequest(
        AdbServiceKind.cmd,
        arguments: List.unmodifiable(arguments),
        maxOutput: maxOutput,
      ),
      timeout,
      cancellation,
    );
    await for (final event in session.events) {
      yield AdbShellEvent(
        switch (event.kind) {
          'stdout' => AdbShellChannel.stdout,
          'stderr' => AdbShellChannel.stderr,
          'exit' => AdbShellChannel.exit,
          _ => throw const AdbException('invalid_shell_event'),
        },
        event.bytes,
        exitCode: event.exitCode,
      );
    }
  }

  Future<Uint8List> _response(
    AdbDevice device,
    AdbServiceRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) async {
    final session = await _service(device, request, timeout, cancellation);
    final bytes = BytesBuilder(copy: false);
    await for (final event in session.events) {
      bytes.add(event.bytes);
    }
    return bytes.takeBytes();
  }

  Future<Uint8List> serviceResponse(
    AdbDevice device,
    String service, {
    int maxOutput = 8192,
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) => _response(
    device,
    AdbServiceRequest(
      AdbServiceKind.response,
      service: service,
      maxOutput: maxOutput,
    ),
    timeout,
    cancellation,
  );
  Future<Uint8List> tcpip(
    AdbDevice device,
    int port, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) {
    if (port <= 0 || port > 65535) throw ArgumentError.value(port, 'port');
    return _response(
      device,
      AdbServiceRequest(AdbServiceKind.tcpIp, service: '$port'),
      timeout,
      cancellation,
    );
  }

  Future<Uint8List> usb(
    AdbDevice device, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) => _response(
    device,
    const AdbServiceRequest(AdbServiceKind.usb),
    timeout,
    cancellation,
  );

  /// 只确认请求，不等待启动或重新连接。
  Future<void> reboot(
    AdbDevice device, {
    AdbRebootTarget target = AdbRebootTarget.system,
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    await _response(
      device,
      AdbServiceRequest(
        AdbServiceKind.reboot,
        service: target == AdbRebootTarget.system ? '' : target.name,
      ),
      timeout,
      cancellation,
    );
  }

  Stream<List<int>> trackJdwp(
    AdbDevice device, {
    int maximum = 1024,
    Duration timeout = const Duration(hours: 1),
    AdbCancellation? cancellation,
  }) async* {
    final session = await _service(
      device,
      AdbServiceRequest(AdbServiceKind.trackJdwp, maxOutput: maximum),
      timeout,
      cancellation,
    );
    await for (final event in session.events) {
      if (event.facts case final value?) yield value.pids;
    }
  }

  Future<List<int>> jdwp(
    AdbDevice device, {
    int maximum = 1024,
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    final session = await _service(
      device,
      AdbServiceRequest(AdbServiceKind.jdwp, maxOutput: maximum),
      timeout,
      cancellation,
    );
    await for (final event in session.events) {
      if (event.facts case final value?) return value.pids;
    }
    throw const AdbException('missing_jdwp_snapshot');
  }

  AdbSync sync(AdbDevice device) => AdbSync._(this, device);

  /// 宽元数据、快照核验传输和精确暂存句柄；使用此宿主已经持有的连接。
  AdbFiles files(AdbDevice device) => AdbFiles._(this, device);

  /// 相同名称的重新附着先排空旧代文件执行；失败不准入新代，也不重连设备。
  Future<AdbFileScope> attachFileScope(
    String ownerKey, {
    AdbAdmissionScopeInfo? admissionScope,
  }) => _start(() async {
    _checkOpen();
    final previous = _fileScopeTransitions[ownerKey];
    final released = Completer<void>();
    _fileScopeTransitions[ownerKey] = released.future;
    try {
      // 同一 facade 不让异步回执乱序退休新句柄；跨 isolate 的最终栅栏仍在原生。
      if (previous != null) await previous;
      _checkOpen();
      return await _attachFileScope(ownerKey, admissionScope: admissionScope);
    } finally {
      released.complete();
      if (identical(_fileScopeTransitions[ownerKey], released.future)) {
        _fileScopeTransitions.remove(ownerKey);
      }
    }
  });

  Future<AdbFileScope> _attachFileScope(
    String ownerKey, {
    AdbAdmissionScopeInfo? admissionScope,
  }) async {
    final binding = _bindings();
    if (binding is! NativeAdbFileScopeApi) {
      throw const AdbException('file_scope_capability_unavailable');
    }
    final api = binding as NativeAdbFileScopeApi;
    if (admissionScope != null &&
        (binding is! NativeAdbScopedFileScopeApi ||
            binding is! NativeAdbAdmissionApi)) {
      throw const AdbException('scoped_file_capability_unavailable');
    }
    final id = admissionScope == null
        ? await api.fileScopeAttach(ownerKey)
        : await (binding as NativeAdbScopedFileScopeApi).fileScopeAttachScoped(
            ownerKey,
            admissionScope.scopeId,
          );
    final scope = AdbFileScope._(this, api, id, ownerKey);
    _resources.add(scope);
    // 原生确认旧代排空后，才退休本地旧代；新句柄先登记以保留失败关闭权。
    for (final old
        in _fileScopes
            .where((old) => !identical(old, scope) && old._ownerKey == ownerKey)
            .toList()) {
      old._closed = true;
      old._released = true;
      _resources.remove(old);
    }
    try {
      _checkOpen();
      if (admissionScope != null) {
        final current = await (binding as NativeAdbAdmissionApi)
            .inspectAdmissionScope(admissionScope.scopeKey);
        _checkOpen();
        if (current?.scopeId != admissionScope.scopeId ||
            current?.accepting != true) {
          throw const AdbException('adb_admission_scope_stale');
        }
      }
    } catch (_) {
      await scope.close();
      rethrow;
    }
    return scope;
  }

  Future<AdbServiceFacts> _reverse(
    AdbDevice device,
    AdbReverseRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) => _start(() async {
    _checkOpen();
    cancellation?.check();
    final api = _bindings();
    final connection = await _resolve(device);
    _checkOpen();
    cancellation?.check();
    final id = await api.reverse(
      connection.id,
      request,
      adbTimeoutMillis(timeout),
    );
    final session = await _ownService(api, id, cancellation);
    await for (final event in session.events) {
      if (event.facts case final value?) return value;
    }
    throw const AdbException('missing_reverse_receipt');
  });

  Future<AdbReverseSocket> reverse(
    AdbDevice device,
    AdbReverseSocket socket,
    InternetAddress host,
    int port, {
    bool noRebind = true,
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    if (port <= 0 || port > 65535) throw ArgumentError.value(port, 'port');
    final address = host.type == InternetAddressType.IPv6
        ? '[${host.address}]:$port'
        : '${host.address}:$port';
    final value = await _reverse(
      device,
      AdbReverseRequest(
        AdbReverseKind.forward,
        deviceService: socket.service,
        hostAddress: address,
        noRebind: noRebind,
      ),
      timeout,
      cancellation,
    );
    return AdbReverseSocket._(
      value.deviceService ??
          (throw const AdbException('missing_reverse_binding')),
    );
  }

  Future<List<AdbReverseMapping>> reverseList(
    AdbDevice device, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async => (await _reverse(
    device,
    const AdbReverseRequest(AdbReverseKind.list),
    timeout,
    cancellation,
  )).mappings;
  Future<void> reverseRemove(
    AdbDevice device,
    AdbReverseSocket socket, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    await _reverse(
      device,
      AdbReverseRequest(AdbReverseKind.remove, deviceService: socket.service),
      timeout,
      cancellation,
    );
  }

  /// 此操作明确影响设备侧所有监听者，包括其他宿主。
  Future<void> reverseRemoveAll(
    AdbDevice device, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    await _reverse(
      device,
      const AdbReverseRequest(AdbReverseKind.removeAll),
      timeout,
      cancellation,
    );
  }
}

/// 无状态 SYNC facade；每次操作持有一个独立 sync 流。
/// 远程名称保持字节形式，递归和冲突策略由调用方负责。
final class AdbSync {
  AdbSync._(this._services, this.device);
  final AdbServices _services;
  final AdbDevice device;
  Future<AdbServiceSession> _open(
    AdbSyncRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) => _services._start(() async {
    _services._checkOpen();
    cancellation?.check();
    if (request.maxBytes < 0 ||
        request.maxEntries <= 0 ||
        request.maxEntries > 100000 ||
        request.permissions < 0 ||
        request.permissions > 511 ||
        request.modifiedSeconds < 0 ||
        request.modifiedSeconds > 0xffffffff) {
      throw ArgumentError('Invalid SYNC bounds');
    }
    final api = _services._bindings();
    final connection = await _services._resolve(device);
    _services._checkOpen();
    cancellation?.check();
    final id = await api.sync(
      connection.id,
      request,
      adbTimeoutMillis(timeout),
    );
    return _services._ownService(api, id, cancellation);
  });

  Future<AdbFileMetadata> stat(
    AdbPath path, {
    bool followLinks = true,
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) async {
    final session = await _open(
      AdbSyncRequest(
        followLinks ? AdbSyncKind.stat : AdbSyncKind.lstat,
        path.bytes,
      ),
      timeout,
      cancellation,
    );
    AdbFileMetadata? metadata;
    await for (final event in session.events) {
      if (event.facts?.metadata case final value?) metadata = value;
    }
    // 事件流只有确认 done 才能正常结束，不能把中间元数据当成执行成功。
    return metadata ?? (throw const AdbException('missing_file_metadata'));
  }

  Future<AdbFileMetadata> lstat(
    AdbPath path, {
    Duration timeout = const Duration(seconds: 15),
    AdbCancellation? cancellation,
  }) => stat(
    path,
    followLinks: false,
    timeout: timeout,
    cancellation: cancellation,
  );
  Stream<AdbDirectoryEntry> list(
    AdbPath path, {
    int maxEntries = 10000,
    Duration timeout = const Duration(seconds: 30),
    AdbCancellation? cancellation,
  }) async* {
    final session = await _open(
      AdbSyncRequest(AdbSyncKind.list, path.bytes, maxEntries: maxEntries),
      timeout,
      cancellation,
    );
    await for (final event in session.events) {
      for (final entry in event.facts?.entries ?? const <AdbDirectoryEntry>[]) {
        yield entry;
      }
    }
  }

  Stream<Uint8List> pull(
    AdbPath path, {
    int maxBytes = 1 << 40,
    AdbCompression compression = AdbCompression.none,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) async* {
    final session = await _open(
      AdbSyncRequest(
        AdbSyncKind.pull,
        path.bytes,
        maxBytes: maxBytes,
        compression: compression,
      ),
      timeout,
      cancellation,
    );
    await for (final event in session.events) {
      if (event.kind == 'data') yield event.bytes;
    }
  }

  /// 创建由调用方持有的流式上传会话，不关闭共享连接或其他服务。
  ///
  /// 本入口不接收取消令牌。调用方应在创建前检查取消，等待迟到的创建结果，
  /// 先保存会话再绑定令牌；随后并行读取 [AdbServiceSession.events] 与写入输入，
  /// 写完调用 [AdbServiceSession.finish]，以终态回执确认上传结果。
  /// 无论成功或失败，都必须在 finally 中精确关闭本会话；关闭失败时继续持有
  /// 会话并重试 [AdbServiceSession.close]，不能通过关闭共享 services 代偿。
  /// 关闭确认本机操作释放，不证明远端服务已经退出或撤销已写入内容。
  Future<AdbServiceSession> openPush(
    AdbPath path, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    int modifiedSeconds = 0,
    AdbCompression compression = AdbCompression.none,
    Duration timeout = const Duration(minutes: 30),
  }) => _open(
    AdbSyncRequest(
      AdbSyncKind.push,
      path.bytes,
      maxBytes: maxBytes,
      permissions: permissions,
      modifiedSeconds: modifiedSeconds,
      compression: compression,
    ),
    timeout,
    null,
  );

  Future<int> push(
    AdbPath path,
    Stream<List<int>> source, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    int modifiedSeconds = 0,
    AdbCompression compression = AdbCompression.none,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) async {
    final session = await _open(
      AdbSyncRequest(
        AdbSyncKind.push,
        path.bytes,
        maxBytes: maxBytes,
        permissions: permissions,
        modifiedSeconds: modifiedSeconds,
        compression: compression,
      ),
      timeout,
      cancellation,
    );
    var transferred = 0;
    // 并发读取完成结果，使远端失败能够解除输入生产者的等待；输入缓慢时原生输出仍须有界。
    final reading = () async {
      await for (final event in session.events) {
        if (event.done) transferred = event.transferred;
      }
    }();
    // 立即附着错误处理器，生产者停滞期间也不例外。
    final completion = reading.then<Object?>(
      (_) => null,
      onError: (Object e, StackTrace st) => (e, st),
    );
    try {
      await session.addStream(source);
      await session.finish();
      await reading;
      return transferred;
    } catch (error) {
      await session.close();
      final result = await completion;
      // 远端失败会关闭生产者，应呈现原始远端错误。
      if (error is AdbException && error.code == 'service_closed') {
        if (result case (final Object failure, final StackTrace stack)) {
          Error.throwWithStackTrace(failure, stack);
        }
      }
      rethrow;
    } finally {
      await session.close();
      await completion;
    }
  }

  Future<int> _file(
    AdbSyncRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) async {
    final session = await _open(request, timeout, cancellation);
    await for (final event in session.events) {
      if (event.done) return event.transferred;
    }
    throw const AdbException('missing_sync_receipt');
  }

  Future<int> pushFile(
    AdbPath path,
    File source, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    int? modifiedSeconds,
    AdbCompression compression = AdbCompression.none,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) async => _file(
    AdbSyncRequest(
      AdbSyncKind.pushFile,
      path.bytes,
      localPath: source.absolute.path,
      maxBytes: maxBytes,
      permissions: permissions,
      modifiedSeconds:
          modifiedSeconds ??
          (await source.lastModified()).millisecondsSinceEpoch ~/ 1000,
      compression: compression,
    ),
    timeout,
    cancellation,
  );
  Future<int> pullFile(
    AdbPath path,
    File destination, {
    int maxBytes = 1 << 40,
    AdbCompression compression = AdbCompression.none,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) => _file(
    AdbSyncRequest(
      AdbSyncKind.pullFile,
      path.bytes,
      localPath: destination.absolute.path,
      maxBytes: maxBytes,
      compression: compression,
    ),
    timeout,
    cancellation,
  );
}
