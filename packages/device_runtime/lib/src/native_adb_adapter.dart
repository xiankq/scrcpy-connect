import 'package:flutter_adb/flutter_adb.dart';

import 'rust/adb_api.dart' as native;

/// Maps generated typed Rust functions to flutter_adb's independent service API.
final class NativeAdbAdapter implements NativeAdbApi {
  const NativeAdbAdapter();
  Future<T> _nativeCall<T>(Future<T> call) async {
    try {
      return await call;
    } catch (error) {
      if (error is AdbException) rethrow;
      throw AdbException('native_adb', error.toString());
    }
  }

  AdbDevice _device(native.AdbDeviceInfo info) => AdbDevice(
    id: info.id,
    serial: info.serial,
    state: info.state,
    features: List.unmodifiable(info.features),
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
    int timeoutMs,
  ) async => _device(
    await _nativeCall(
      native.adbConnectServer(
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
      officialServer: value.officialServer,
      closed: value.closed,
      features: List.unmodifiable(value.features),
      transportId: value.transportId?.toInt(),
      protocolVersion: value.protocolVersion,
      maxPayload: value.maxPayload,
      burstMode: value.burstMode,
    );
  }

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
    int timeoutMs,
  ) async => _device(
    await _nativeCall(
      native.adbConnectTcp(
        address: address,
        identityPath: identityPath,
        requireTls: requireTls,
        authorize: authorize,
        timeoutMs: timeoutMs,
      ),
    ),
  );
  @override
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial,
    String identityPath,
    bool authorize,
    int timeoutMs,
  ) async => _device(
    await _nativeCall(
      native.adbConnectUsbFd(
        fd: fd,
        serial: serial,
        identityPath: identityPath,
        authorize: authorize,
        timeoutMs: timeoutMs,
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
    int timeoutMs,
  ) => _nativeCall(
    native.adbPair(
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
  Future<String> transfer(
    String id,
    String remotePath,
    String localPath,
    bool push,
    int maxBytes,
    int permissions,
    int modifiedSeconds,
    int timeoutMs,
  ) => _nativeCall(
    native.adbTransfer(
      connectionId: id,
      remotePath: remotePath,
      localPath: localPath,
      push: push,
      maxBytes: BigInt.from(maxBytes),
      permissions: permissions,
      modifiedSeconds: modifiedSeconds,
      timeoutMs: timeoutMs,
    ),
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
}
