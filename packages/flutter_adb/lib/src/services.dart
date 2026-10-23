part of 'api.dart';

/// One native service. Events are single-subscription and pull-based. Exactly
/// one write may be pending, each at most 64 KiB; reads and writes progress
/// independently. close cancels and drains this service, not its connection.
final class AdbServiceSession {
  AdbServiceSession._(
    this._api,
    this.id,
    AdbCancellation? cancellation,
    this._onClosed,
  ) {
    if (cancellation != null) {
      unawaited(cancellation.whenCancelled.then((_) => close()));
    }
  }
  final NativeAdbApi _api;
  final String id;
  final void Function() _onClosed;
  bool _reading = false, _writing = false, _closed = false;
  Future<void>? _closing;
  StreamIterator<List<int>>? _input;
  Stream<NativeAdbEvent> get events async* {
    if (_reading) throw const AdbException('service_has_a_reader');
    if (_closed) throw const AdbException('service_closed');
    _reading = true;
    try {
      while (!_closed) {
        final event = await _api.next(id);
        if (event == null) break;
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
      // close() cancels this single iterator. Do not attach a pending close
      // Future listener for every packet: a long transfer must stay bounded.
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
      _input = null;
      await iterator.cancel();
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

  /// Completes the input file of a streaming SYNC push. A raw ADB service has
  /// no generic half-close; shell uses closeStdin instead.
  Future<void> finish() => _send(AdbServiceInput(AdbInputKind.finish));
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await Future.wait<void>([
        _api.cancel(id),
        if (_input case final iterator?) iterator.cancel(),
      ]);
    } finally {
      _onClosed();
    }
  }
}

/// Existing ADB service protocols, with no product browsing, transfer journals,
/// identity persistence, retries or reconnection policy.
final class AdbServices {
  AdbServices(this._bindings, this._resolve, this._check);
  final NativeAdbApi Function() _bindings;
  final Future<AdbDevice> Function(AdbDevice) _resolve;
  final void Function() _check;
  final Set<AdbServiceSession> _sessions = {};
  Future<void>? _closing;
  void _checkOpen() {
    _check();
    if (_closing != null) throw const AdbException('closed');
  }

  Future<AdbServiceSession> _own(
    NativeAdbApi api,
    String id,
    AdbCancellation? cancellation,
  ) async {
    try {
      _checkOpen();
    } catch (_) {
      await api.cancel(id);
      rethrow;
    }
    late final AdbServiceSession session;
    session = AdbServiceSession._(
      api,
      id,
      cancellation,
      () => _sessions.remove(session),
    );
    _sessions.add(session);
    return session;
  }

  /// Releases this facade's services; device connections remain caller-owned.
  Future<void> close() => _closing ??= Future.wait(
    _sessions.toList().map((session) => session.close()),
  );
  Future<AdbConnectionFacts> connectionFacts(AdbDevice device) async {
    _checkOpen();
    return _bindings().connectionFacts((await _resolve(device)).id);
  }

  Future<AdbServiceSession> _service(
    AdbDevice device,
    AdbServiceRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) async {
    _checkOpen();
    cancellation?.check();
    if (request.maxOutput <= 0 || request.maxOutput > 16 * 1024 * 1024) {
      throw ArgumentError.value(request.maxOutput, 'maxOutput');
    }
    final api = _bindings();
    final id = await api.service(
      (await _resolve(device)).id,
      request,
      adbTimeoutMillis(timeout),
    );
    return _own(api, id, cancellation);
  }

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

  /// shell_v2 is required. Legacy noninteractive shell remains AdbClient.shell.
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

  /// Acknowledges the request; it does not wait for boot or reconnect.
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
  Future<AdbServiceFacts> _reverse(
    AdbDevice device,
    AdbReverseRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) async {
    _checkOpen();
    cancellation?.check();
    final api = _bindings();
    final id = await api.reverse(
      (await _resolve(device)).id,
      request,
      adbTimeoutMillis(timeout),
    );
    final session = await _own(api, id, cancellation);
    await for (final event in session.events) {
      if (event.facts case final value?) return value;
    }
    throw const AdbException('missing_reverse_receipt');
  }

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

  /// Explicitly affects all device-side listeners, including other hosts.
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

/// Stateless SYNC service facade. Each operation opens one owned sync stream;
/// remote names remain bytes and callers own all recursion/conflict policy.
final class AdbSync {
  AdbSync._(this._services, this.device);
  final AdbServices _services;
  final AdbDevice device;
  Future<AdbServiceSession> _open(
    AdbSyncRequest request,
    Duration timeout,
    AdbCancellation? cancellation,
  ) async {
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
    final id = await api.sync(
      (await _services._resolve(device)).id,
      request,
      adbTimeoutMillis(timeout),
    );
    return _services._own(api, id, cancellation);
  }

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
    await for (final event in session.events) {
      if (event.facts?.metadata case final metadata?) return metadata;
    }
    throw const AdbException('missing_file_metadata');
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
    // Read completion concurrently: remote failure must unblock an input
    // producer, and native output remains bounded even when input is slow.
    final reading = () async {
      await for (final event in session.events) {
        if (event.done) transferred = event.transferred;
      }
    }();
    // Attach an error handler immediately, including while the producer stalls.
    // Closing signals addStream to cancel the producer before it asks for data.
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
      // A remote failure closes the producer; expose that original failure.
      // Errors raised by the caller's producer retain their own identity.
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
