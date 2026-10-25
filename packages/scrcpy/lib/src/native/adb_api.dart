import 'dart:typed_data';

import 'package:adb/adb.dart';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64Util;

import 'generated/third_party/interop_adb_api/api.dart' as native;

/// 将生成的 Rust 类型化函数适配为 adb 的独立能力接口。
base class FrbNativeAdbApi
    implements
        NativeAdbApi,
        NativeAdbHandshakeApi,
        NativeAdbAdmissionApi,
        NativeAdbConnectionApi,
        NativeAdbOpenProbeApi,
        NativeAdbServerApi,
        NativeAdbScopedServerApi,
        NativeAdbFileApi,
        NativeAdbFileScopeApi,
        NativeAdbScopedFileScopeApi,
        NativeAdbLocalFileApi,
        AdbIdentities {
  const FrbNativeAdbApi();

  AdbIdentityInfo _identity(native.AdbIdentityInfo value) => AdbIdentityInfo(
    fingerprint: value.fingerprint,
    fingerprintAlgorithm: value.fingerprintAlgorithm,
    fingerprintInput: value.fingerprintInput,
    bits: value.bits,
    exponent: value.exponent,
  );

  @override
  Future<void> prepareIdentity(String path) =>
      _nativeCall(native.adbInitializeIdentity(identityPath: path));
  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final value = await _nativeCall(
      native.adbInspectIdentity(identityPath: path),
    );
    return value == null ? null : _identity(value);
  }

  @override
  Future<AdbIdentityInfo> validateIdentity(String pem) async =>
      _identity(await _nativeCall(native.adbValidateIdentity(pem: pem)));
  @override
  Future<AdbIdentityCommitReceipt> replaceIdentity(
    String path,
    String pem, {
    String? expectedFingerprint,
  }) async {
    final receipt = await _nativeCall(
      native.adbReplaceIdentity(
        identityPath: path,
        pem: pem,
        expectedFingerprint: expectedFingerprint,
      ),
    );
    return AdbIdentityCommitReceipt(
      state: AdbIdentityCommitState.values.byName(receipt.state.name),
      identity: receipt.identity == null ? null : _identity(receipt.identity!),
      error: receipt.error,
    );
  }

  Future<T> _nativeCall<T>(Future<T> call) async {
    try {
      return await call;
    } catch (error) {
      if (error is AdbException) rethrow;
      if (error is native.AdbConnectionError) {
        final code = switch (error.code) {
          native.AdbConnectionErrorCode.invalidArgument => 'invalid_argument',
          native.AdbConnectionErrorCode.unsupported => 'unsupported',
          native.AdbConnectionErrorCode.admissionRejected =>
            'adb_admission_rejected',
          native.AdbConnectionErrorCode.identity => 'identity_error',
          native.AdbConnectionErrorCode.connectionRefused =>
            'connection_refused',
          native.AdbConnectionErrorCode.hostUnreachable => 'host_unreachable',
          native.AdbConnectionErrorCode.networkUnreachable =>
            'network_unreachable',
          native.AdbConnectionErrorCode.connectTimedOut => 'connect_timeout',
          native.AdbConnectionErrorCode.handshakeTimedOut =>
            'handshake_timeout',
          native.AdbConnectionErrorCode.cancelled => 'cancelled',
          native.AdbConnectionErrorCode.authorizationRequired => 'auth_failed',
          native.AdbConnectionErrorCode.protocol => 'protocol_error',
          native.AdbConnectionErrorCode.io => 'io_error',
          native.AdbConnectionErrorCode.pairingResultUnknown =>
            'pairing_result_unknown',
          native.AdbConnectionErrorCode.cleanupUnconfirmed =>
            'adb_cleanup_unconfirmed',
          native.AdbConnectionErrorCode.internal => 'native_adb',
        };
        throw AdbException(code, error.message);
      }
      if (error is native.AdbServerError) {
        final code = switch (error.code) {
          native.AdbServerErrorCode.invalidArgument => 'invalid_argument',
          native.AdbServerErrorCode.notFound => 'adb_server_not_found',
          native.AdbServerErrorCode.staleLease => 'stale_server_lease',
          native.AdbServerErrorCode.transportStateUnknown =>
            'official_connect_result_unknown',
          native.AdbServerErrorCode.closing => 'adb_server_closing',
          native.AdbServerErrorCode.cleanupUnconfirmed =>
            'adb_server_cleanup_unconfirmed',
          native.AdbServerErrorCode.io => 'adb_server_io',
        };
        throw AdbException(code, error.message);
      }
      throw AdbException('native_adb', error.toString());
    }
  }

  @override
  Future<String> createHandshake() => _nativeCall(native.adbHandshakeCreate());
  @override
  Future<void> cancelHandshake(String handshakeId) =>
      _nativeCall(native.adbHandshakeCancel(handshakeId: handshakeId));
  @override
  Future<void> closeHandshake(String handshakeId) =>
      _nativeCall(native.adbHandshakeClose(handshakeId: handshakeId));

  AdbAdmissionScopeInfo _admissionScope(native.AdbAdmissionScopeInfo value) =>
      AdbAdmissionScopeInfo(
        scopeKey: value.scopeKey,
        scopeId: value.scopeId,
        accepting: value.accepting,
      );
  @override
  Future<AdbAdmissionScopeInfo?> inspectAdmissionScope(String scopeKey) async {
    final value = await _nativeCall(
      native.adbAdmissionScopeInspect(scopeKey: scopeKey),
    );
    return value == null ? null : _admissionScope(value);
  }

  @override
  Future<AdbAdmissionScopeInfo> attachAdmissionScope(
    String scopeKey, {
    String? expectedScopeId,
    int timeoutMs = 7000,
  }) async => _admissionScope(
    await _nativeCall(
      native.adbAdmissionScopeAttach(
        scopeKey: scopeKey,
        expectedScopeId: expectedScopeId,
        timeoutMs: timeoutMs,
      ),
    ),
  );
  @override
  Future<void> closeAdmissionScope(String scopeId, {int timeoutMs = 7000}) =>
      _nativeCall(
        native.adbAdmissionScopeClose(scopeId: scopeId, timeoutMs: timeoutMs),
      );
  @override
  Future<String> createScopedHandshake(String scopeId) =>
      _nativeCall(native.adbScopedHandshakeCreate(scopeId: scopeId));
  @override
  Future<void> confirmHandshakeConnection(
    String handshakeId,
    String connectionId,
  ) => _nativeCall(
    native.adbHandshakeConnectionConfirm(
      handshakeId: handshakeId,
      connectionId: connectionId,
    ),
  );
  @override
  Future<AdbDevice> claimScopedConnection(
    String connectionId,
    String handshakeId,
  ) async => _device(
    await _nativeCall(
      native.adbScopedConnectionClaim(
        connectionId: connectionId,
        handshakeId: handshakeId,
      ),
    ),
  );

  @override
  Future<AdbDevice> claimConnection(String connectionId) async => _device(
    await _nativeCall(native.adbClaimConnection(connectionId: connectionId)),
  );

  native.AdbServerLaunchSpec _serverLaunch(AdbServerLaunchSpec value) =>
      native.AdbServerLaunchSpec(
        executable: value.executable,
        arguments: value.arguments,
        environment: value.environment,
        endpoint: value.endpoint,
      );

  AdbServerInfo _serverInfo(native.AdbServerInfo value) => AdbServerInfo(
    serverId: value.serverId,
    leaseId: value.leaseId,
    launch: AdbServerLaunchSpec(
      executable: value.launch.executable,
      arguments: value.launch.arguments,
      environment: value.launch.environment,
      endpoint: value.launch.endpoint,
    ),
    phase: AdbServerPhase.values.byName(value.phase.name),
    transportStateUnknown: value.transportStateUnknown,
    pid: value.pid,
    exitCode: value.exitCode,
  );

  @override
  Future<AdbServerInfo> createServer(AdbServerLaunchSpec launch) async =>
      _serverInfo(
        await _nativeCall(
          native.adbServerCreate(launch: _serverLaunch(launch)),
        ),
      );

  @override
  Future<AdbServerInfo> createScopedServer(
    AdbServerLaunchSpec launch,
    String scopeId,
  ) async => _serverInfo(
    await _nativeCall(
      native.adbServerCreateScoped(
        launch: _serverLaunch(launch),
        scopeId: scopeId,
      ),
    ),
  );

  @override
  Future<AdbServerInfo> claimScopedServer(
    String leaseId,
    String scopeId,
  ) async => _serverInfo(
    await _nativeCall(
      native.adbServerClaimScoped(leaseId: leaseId, scopeId: scopeId),
    ),
  );

  @override
  Future<void> confirmScopedServer(String leaseId, String scopeId) =>
      _nativeCall(
        native.adbServerConfirmScoped(leaseId: leaseId, scopeId: scopeId),
      );

  @override
  Future<AdbServerInfo> startServer(String leaseId, int timeoutMs) async =>
      _serverInfo(
        await _nativeCall(
          native.adbServerStart(leaseId: leaseId, timeoutMs: timeoutMs),
        ),
      );

  @override
  Future<List<AdbServerInfo>> listServers() async =>
      (await _nativeCall(native.adbServerList()))
          .map(_serverInfo)
          .toList(growable: false);

  @override
  Future<AdbServerInfo> claimServer(String leaseId) async =>
      _serverInfo(await _nativeCall(native.adbServerClaim(leaseId: leaseId)));

  @override
  Future<void> closeServer(String leaseId) =>
      _nativeCall(native.adbServerClose(leaseId: leaseId));

  @override
  Future<String> createServerCommand(
    String leaseId,
    AdbServerCommandSpec spec,
  ) => _nativeCall(
    native.adbServerCommandCreate(
      leaseId: leaseId,
      spec: native.AdbServerCommandSpec(
        executable: spec.executable,
        arguments: spec.arguments,
        input: spec.input,
        timeoutMs: spec.timeoutMs,
        mayCreateTransport: spec.mayCreateTransport,
        preparation: spec.preparation,
      ),
    ),
  );

  @override
  Future<AdbServerCommandResult> runServerCommand(String commandId) async {
    final value = await _nativeCall(
      native.adbServerCommandRun(commandId: commandId),
    );
    return AdbServerCommandResult(
      status: AdbServerCommandStatus.values.byName(value.status.name),
      exitCode: value.exitCode,
      stdout: value.stdout,
      stderr: value.stderr,
      errorMessage: value.errorMessage,
    );
  }

  @override
  Future<void> confirmServerCommand(String commandId) =>
      _nativeCall(native.adbServerCommandConfirm(commandId: commandId));
  @override
  Future<void> cancelServerCommand(String commandId) =>
      _nativeCall(native.adbServerCommandCancel(commandId: commandId));
  @override
  Future<void> closeServerCommand(String commandId) =>
      _nativeCall(native.adbServerCommandClose(commandId: commandId));
  @override
  Future<String> createServerHandshake(String leaseId) =>
      _nativeCall(native.adbServerHandshakeCreate(leaseId: leaseId));

  AdbDevice _device(native.AdbDeviceInfo info) => AdbDevice(
    id: info.id,
    serial: info.serial,
    state: info.state,
    features: List.unmodifiable(info.features),
    nativeOwner: this,
  );
  AdbFileMetadata _metadata(native.AdbFileMetadata value) =>
      AdbFileMetadata(value.mode, value.size.toInt(), value.modifiedSeconds);
  AdbServiceFacts _facts(native.AdbServiceFacts value) => AdbServiceFacts(
    metadata: value.metadata == null ? null : _metadata(value.metadata!),
    entries: value.entries
        .map(
          (entry) => AdbDirectoryEntry(entry.name, _metadata(entry.metadata)),
        )
        .toList(growable: false),
    pids: List.unmodifiable(value.pids),
    mappings: value.mappings
        .map((m) => AdbReverseMapping(m.serial, m.deviceService, m.hostService))
        .toList(growable: false),
    deviceService: value.deviceService,
  );
  @override
  Future<AdbDevice> connectServer(
    String serverAddress,
    String serial,
    int timeoutMs, {
    String? handshakeId,
  }) async => _device(
    await _nativeCall(
      native.adbConnectServer(
        handshakeId: handshakeId,
        serverAddress: serverAddress,
        serial: serial,
        timeoutMs: timeoutMs,
      ),
    ),
  );
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    final value = await _nativeCall(
      native.adbConnectionFacts(connectionId: id),
    );
    return AdbConnectionFacts(
      inboundActivity: value.inboundActivity,
      officialServer: value.officialServer,
      closed: value.closed,
      features: List.unmodifiable(value.features),
      connectionId: value.connectionId,
      serverAddress: value.serverAddress,
      serverId: value.serverId,
      admissionScopeKey: value.admissionScopeKey,
      transportId: value.transportId?.toInt(),
      protocolVersion: value.protocolVersion,
      maxPayload: value.maxPayload,
      burstMode: value.burstMode,
      handshake: AdbHandshakeKind.values.byName(value.handshake.name),
      configuredIdentity: value.configuredIdentity == null
          ? null
          : _identity(value.configuredIdentity!),
    );
  }

  @override
  Future<String> createOpenProbe(
    String connectionId,
    String service,
    int timeoutMs,
  ) => _nativeCall(
    native.adbOpenProbeCreate(
      connectionId: connectionId,
      service: service,
      timeoutMs: timeoutMs,
    ),
  );

  @override
  Future<AdbOpenProbeFacts> openProbeResult(String probeId) async {
    final facts = await _nativeCall(
      native.adbOpenProbeResult(probeId: probeId),
    );
    return AdbOpenProbeFacts(
      layer: AdbOpenProbeLayer.values.byName(facts.layer.name),
      openWritten: facts.openWritten,
      outcome: AdbOpenProbeOutcome.values.byName(facts.outcome.name),
      inboundActivity: facts.inboundActivity,
    );
  }

  @override
  Future<void> closeOpenProbe(String probeId, int timeoutMs) => _nativeCall(
    native.adbOpenProbeClose(probeId: probeId, timeoutMs: timeoutMs),
  );

  @override
  Future<String> service(String id, AdbServiceRequest request, int timeoutMs) =>
      _nativeCall(
        native.adbService(
          connectionId: id,
          timeoutMs: timeoutMs,
          request: native.AdbServiceRequest(
            kind: native.AdbServiceKind.values.byName(request.kind.name),
            service: request.service,
            arguments: request.arguments,
            maxOutput: request.maxOutput,
          ),
        ),
      );
  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) =>
      _nativeCall(
        native.adbSync(
          connectionId: id,
          timeoutMs: timeoutMs,
          request: native.AdbSyncRequest(
            kind: native.AdbSyncKind.values.byName(request.kind.name),
            path: request.path,
            localPath: request.localPath,
            maxBytes: BigInt.from(request.maxBytes),
            maxEntries: request.maxEntries,
            permissions: request.permissions,
            modifiedSeconds: request.modifiedSeconds,
            compression: native.AdbCompression.values.byName(
              request.compression.name,
            ),
          ),
        ),
      );
  @override
  Future<void> write(String id, AdbServiceInput input) => _nativeCall(
    native.adbWrite(
      operationId: id,
      input: native.AdbInput(
        kind: native.AdbInputKind.values.byName(input.kind.name),
        bytes: input.bytes,
        rows: input.rows,
        columns: input.columns,
      ),
    ),
  );
  @override
  Future<String> reverse(String id, AdbReverseRequest request, int timeoutMs) =>
      _nativeCall(
        native.adbReverse(
          connectionId: id,
          timeoutMs: timeoutMs,
          request: native.AdbReverseRequest(
            kind: native.AdbReverseKind.values.byName(request.kind.name),
            deviceService: request.deviceService,
            hostAddress: request.hostAddress,
            noRebind: request.noRebind,
          ),
        ),
      );
  @override
  Future<List<AdbDevice>> devices() async =>
      (await _nativeCall(native.adbDevices()))
          .map(_device)
          .toList(growable: false);
  @override
  Future<AdbDevice> connect(
    String address,
    String identityPath,
    bool requireTls,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) async => _device(
    await _nativeCall(
      native.adbConnectTcp(
        handshakeId: handshakeId,
        address: address,
        identityPath: identityPath,
        requireTls: requireTls,
        authorize: authorize,
        timeoutMs: timeoutMs,
        options: _connectionOptions(options),
      ),
    ),
  );
  @override
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial,
    String identityPath,
    bool authorize,
    int timeoutMs, {
    AdbConnectOptions options = const AdbConnectOptions(),
    String? handshakeId,
  }) async => _device(
    await _nativeCall(
      native.adbConnectUsbFd(
        handshakeId: handshakeId,
        fd: fd,
        serial: serial,
        identityPath: identityPath,
        authorize: authorize,
        timeoutMs: timeoutMs,
        options: _connectionOptions(options),
      ),
    ),
  );
  @override
  Future<void> disconnect(String id) =>
      _nativeCall(native.adbDisconnect(connectionId: id));
  @override
  Future<String> pair(
    String address,
    String password,
    String identityPath,
    int timeoutMs, {
    String? handshakeId,
  }) => _nativeCall(
    native.adbPair(
      handshakeId: handshakeId,
      address: address,
      password: password,
      identityPath: identityPath,
      timeoutMs: timeoutMs,
    ),
  );
  @override
  Future<String> shell(String id, String command, int timeoutMs) => _nativeCall(
    native.adbShell(connectionId: id, command: command, timeoutMs: timeoutMs),
  );
  @override
  Future<NativeAdbEvent?> next(String operationId) async {
    final event = await _nativeCall(
      native.adbServiceNext(operationId: operationId),
    );
    if (event == null) return null;
    return NativeAdbEvent(
      kind: event.kind,
      bytes: event.bytes,
      done: event.done,
      exitCode: event.exitCode,
      transferred: event.transferred.toInt(),
      facts: event.facts == null ? null : _facts(event.facts!),
    );
  }

  @override
  Future<void> cancel(String operationId) =>
      _nativeCall(native.adbCancel(operationId: operationId));
  @override
  Future<void> close() => _nativeCall(native.adbCloseAll());
  native.AdbFileExecutionStamp _nativeStamp(AdbFileExecutionStamp value) =>
      native.AdbFileExecutionStamp(
        mode: value.mode,
        size: BigInt.from(value.size),
        modifiedSeconds: PlatformInt64Util.from(value.modifiedSeconds),
        modifiedNanos: value.modifiedNanos,
        nanosecondPrecision: value.nanosecondPrecision,
      );
  AdbFileExecutionStamp _fileStamp(native.AdbFileExecutionStamp value) =>
      AdbFileExecutionStamp(
        mode: value.mode,
        size: value.size.toInt(),
        modifiedSeconds: value.modifiedSeconds.toInt(),
        modifiedNanos: value.modifiedNanos,
        nanosecondPrecision: value.nanosecondPrecision,
      );
  @override
  Future<void> initializeFileHelpers(List<AdbFileHelper> helpers) =>
      _nativeCall(
        native.adbInitializeFileHelpers(
          helpers: helpers
              .map(
                (helper) =>
                    native.AdbFileHelper(abi: helper.abi, bytes: helper.bytes),
              )
              .toList(growable: false),
        ),
      );
  @override
  Future<String> fileExecute(
    String connectionId,
    AdbFileExecutionRequest request,
    int timeoutMs,
  ) => _nativeCall(
    native.adbFileExecute(
      connectionId: connectionId,
      timeoutMs: timeoutMs,
      request: native.AdbFileExecutionRequest(
        scopeId: request.scopeId,
        kind: native.AdbFileExecutionKind.values.byName(request.kind.name),
        path: request.path,
        destination: request.destination,
        local: request.local,
        followStorageAlias: request.followStorageAlias,
        limit: request.limit,
        push: request.push,
        replace: request.replace,
        expected: request.expected == null
            ? null
            : _nativeStamp(request.expected!),
        partId: request.partId,
      ),
    ),
  );
  @override
  Future<AdbFileExecutionEvent?> fileNext(String operationId) async {
    final event = await _nativeCall(
      native.adbFileNext(operationId: operationId),
    );
    if (event == null) return null;
    return AdbFileExecutionEvent(
      kind: event.kind,
      entries: event.entries
          .map(
            (entry) => AdbFileExecutionEntry(
              name: entry.name,
              stamp: entry.stamp == null ? null : _fileStamp(entry.stamp!),
              errorCode: entry.errorCode,
              errorMessage: entry.errorMessage,
              errno: entry.errno,
            ),
          )
          .toList(growable: false),
      stamp: event.stamp == null ? null : _fileStamp(event.stamp!),
      transferred: event.transferred.toInt(),
      truncated: event.truncated,
      saveMode: event.saveMode,
      partId: event.partId,
      errorCode: event.errorCode,
      errorMessage: event.errorMessage,
      errno: event.errno,
    );
  }

  @override
  Future<void> fileCancel(String operationId) =>
      _nativeCall(native.adbFileCancel(operationId: operationId));

  @override
  Future<String> fileScopeAttach(String ownerKey) =>
      _nativeCall(native.adbFileScopeAttach(ownerKey: ownerKey));
  @override
  Future<String> fileScopeAttachScoped(
    String ownerKey,
    String admissionScopeId,
  ) => _nativeCall(
    native.adbFileScopeAttachScoped(
      ownerKey: ownerKey,
      scopeId: admissionScopeId,
    ),
  );
  @override
  Future<void> fileScopeClose(String scopeId) =>
      _nativeCall(native.adbFileScopeClose(scopeId: scopeId));
  @override
  Future<AdbFileExecutionStamp> localFileStat(Uint8List path) async {
    final event = await _nativeCall(native.adbLocalFileStat(path: path));
    if (event.errorCode case final code?) {
      throw AdbException(code, event.errorMessage ?? '');
    }
    final stamp = event.stamp;
    if (stamp == null) throw const AdbException('invalid_metadata');
    return _fileStamp(stamp);
  }

  @override
  Future<AdbLocalFileFacts> localFileList(Uint8List path, int limit) async {
    final event = await _nativeCall(
      native.adbLocalFileList(path: path, limit: limit),
    );
    if (event.errorCode case final code?) {
      throw AdbException(code, event.errorMessage ?? '');
    }
    return AdbLocalFileFacts(
      event.entries
          .map(
            (entry) => AdbFileExecutionEntry(
              name: entry.name,
              stamp: entry.stamp == null ? null : _fileStamp(entry.stamp!),
              errorCode: entry.errorCode,
              errorMessage: entry.errorMessage,
              errno: entry.errno,
            ),
          )
          .toList(growable: false),
      truncated: event.truncated,
    );
  }
}

/// 只映射明确执行参数，不读取产品偏好或补入应用默认值。
native.AdbConnectOptions _connectionOptions(AdbConnectOptions options) {
  options.validate();
  final keepalive = options.tcp.keepalive;
  return native.AdbConnectOptions(
    burstMode: options.burstMode,
    publicKeyComment: options.publicKeyComment,
    tcp: native.AdbTcpOptions(
      nodelay: options.tcp.nodelay,
      userTimeoutMs: options.tcp.userTimeout?.inMilliseconds,
      keepalive: keepalive == null
          ? null
          : native.AdbKeepaliveOptions(
              idleMs: keepalive.idle.inMilliseconds,
              intervalMs: keepalive.interval.inMilliseconds,
              retries: keepalive.retries,
            ),
    ),
  );
}
