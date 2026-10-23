import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'api.dart';

final class NativeAdbClient implements AdbClient {
  NativeAdbClient(this.api, this.identityPath);
  final NativeAdbApi api;
  final String identityPath;
  bool _closed = false;
  Future<void>? _closing;
  final Set<String> _connections = {};
  final Set<Future<AdbDevice>> _connecting = {};
  final Set<String> _operations = {};
  Future<AdbDevice> _ownConnection(Future<AdbDevice> opening) {
    late final Future<AdbDevice> owned;
    owned = () async {
      try {
        final device = await opening;
        if (_closed) {
          await api.disconnect(device.id);
          throw const AdbException('closed');
        }
        _connections.add(device.id);
        return device;
      } finally {
        _connecting.remove(owned);
      }
    }();
    _connecting.add(owned);
    return owned;
  }

  Future<void> _ownOperation(String id) async {
    if (_closed) {
      await api.cancel(id);
      throw const AdbException('closed');
    }
    _operations.add(id);
  }

  @override
  late final AdbServices services = AdbServices(() => api, (device) async {
    _check();
    return device;
  }, _check);
  @override
  AdbCapabilities get capabilities => AdbCapabilities(
    officialServer: false,
    suppressAuthorizationPrompt: true,
    forceTlsWithoutMdns: true,
    androidUsbFd: Platform.isAndroid,
  );
  void _check() {
    if (_closed) throw const AdbException('closed');
  }

  @override
  Future<List<AdbDevice>> devices() {
    _check();
    return api.devices();
  }

  @override
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
  }) {
    _check();
    return _ownConnection(
      api.connect(
        address,
        identityPath,
        requireTls,
        authorize,
        adbTimeoutMillis(timeout),
      ),
    );
  }

  /// Android permission acquisition remains the platform's responsibility.
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial, {
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
  }) {
    _check();
    return _ownConnection(
      api.connectUsbFd(
        fd,
        serial,
        identityPath,
        authorize,
        adbTimeoutMillis(timeout),
      ),
    );
  }

  @override
  Future<void> disconnect(AdbDevice device) {
    _check();
    _connections.remove(device.id);
    return api.disconnect(device.id);
  }

  @override
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    _check();
    return api.pair(address, password, identityPath, adbTimeoutMillis(timeout));
  }

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    _check();
    cancellation?.check();
    final id = await api.shell(device.id, command, adbTimeoutMillis(timeout));
    await _ownOperation(id);
    var finished = false;
    unawaited(
      cancellation?.whenCancelled.then((_) async {
        if (!finished) await api.cancel(id);
      }),
    );
    try {
      while (true) {
        cancellation?.check();
        final event = await api.next(id);
        if (event == null) break;
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
        if (event.done) break;
      }
    } catch (_) {
      cancellation?.check();
      rethrow;
    } finally {
      finished = true;
      _operations.remove(id);
      await api.cancel(id);
    }
  }

  @override
  Future<int> push(
    AdbDevice device,
    File source,
    String remotePath, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) async {
    final modified =
        (await source.lastModified()).millisecondsSinceEpoch ~/ 1000;
    return _transfer(
      device,
      remotePath,
      source,
      true,
      maxBytes,
      permissions,
      modified,
      timeout,
      cancellation,
    );
  }

  @override
  Future<int> pull(
    AdbDevice device,
    String remotePath,
    File destination, {
    int maxBytes = 1 << 40,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) => _transfer(
    device,
    remotePath,
    destination,
    false,
    maxBytes,
    420,
    0,
    timeout,
    cancellation,
  );
  Future<int> _transfer(
    AdbDevice device,
    String remotePath,
    File local,
    bool push,
    int maxBytes,
    int permissions,
    int modified,
    Duration timeout,
    AdbCancellation? cancellation,
  ) async {
    _check();
    cancellation?.check();
    validateAdbPath(remotePath);
    if (maxBytes < 0 || permissions < 0 || permissions > 511) {
      throw ArgumentError('Invalid ADB transfer limit or permissions');
    }
    final id = await api.transfer(
      device.id,
      remotePath,
      local.absolute.path,
      push,
      maxBytes,
      permissions,
      modified,
      adbTimeoutMillis(timeout),
    );
    await _ownOperation(id);
    var finished = false;
    unawaited(
      cancellation?.whenCancelled.then((_) async {
        if (!finished) await api.cancel(id);
      }),
    );
    try {
      final event = await api.next(id);
      cancellation?.check();
      if (event == null || event.kind != 'transfer' || !event.done) {
        throw const AdbException('incomplete_native_transfer');
      }
      return event.transferred;
    } catch (_) {
      cancellation?.check();
      rethrow;
    } finally {
      finished = true;
      _operations.remove(id);
      await api.cancel(id);
    }
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await Future.wait<void>([
        services.close(),
        ..._operations.toList().map(api.cancel),
      ]);
      _operations.clear();
    } finally {
      // Connect/pair have bounded deadlines rather than cancellable handles.
      // Await pending connects, including their post-close disconnect cleanup.
      await Future.wait(
        _connecting.toList().map((opening) async {
          try {
            final lateDevice = await opening;
            await api.disconnect(lateDevice.id);
          } catch (_) {
            /* Failed connection owns no handle. */
          }
        }),
      );
      await Future.wait(_connections.toList().map(api.disconnect));
      _connections.clear();
    }
  }
}
