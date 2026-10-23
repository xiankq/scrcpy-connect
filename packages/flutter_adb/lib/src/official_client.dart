import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'api.dart';
import 'native_client.dart';

/// Every command targets an explicitly owned server; numeric -H prevents adb
/// from auto-starting an unowned daemon when that server has exited.
final class OfficialAdbClient implements AdbClient {
  OfficialAdbClient(
    this.executable,
    this.port,
    this.environment,
    this.isServerAlive,
  );
  final String executable;
  final int port;
  final Map<String, String> environment;
  final bool Function() isServerAlive;
  final Set<Process> _commands = {};
  bool _closed = false;
  NativeAdbClient? _bound;
  NativeAdbClient get _nativeClient =>
      _bound ?? (throw const AdbException('native_bindings_missing'));
  final Map<String, Future<AdbDevice>> _connections = {};
  final Map<String, AdbDevice> _handles = {};
  void bindNative(NativeAdbApi bindings) {
    _check();
    if (_bound != null) throw StateError('ADB bindings already attached');
    _bound = NativeAdbClient(bindings, '');
  }

  void _check() {
    if (_closed || !isServerAlive()) throw const AdbException('server_closed');
  }

  @override
  late final AdbServices services = AdbServices(
    () => _nativeClient.api,
    _resolve,
    _check,
  );
  Future<AdbDevice> _resolve(AdbDevice device) async {
    _check();
    if (_handles.containsKey(device.id)) return _handles[device.id]!;
    if (device.id != device.serial) {
      throw const AdbException('unknown_connection');
    }
    // Selecting by serial happens once. Every subsequent stream uses this
    // fixed transport ID; a replacement transport must be explicitly connected.
    return _connections.putIfAbsent(device.serial, () async {
      try {
        final fixed = await _nativeClient.api.connectServer(
          '127.0.0.1:$port',
          device.serial,
          15000,
        );
        if (_closed) {
          await _nativeClient.api.disconnect(fixed.id);
          throw const AdbException('server_closed');
        }
        _handles[fixed.id] = fixed;
        return fixed;
      } catch (_) {
        _connections.remove(device.serial);
        rethrow;
      }
    });
  }

  @override
  AdbCapabilities get capabilities => const AdbCapabilities(
    officialServer: true,
    suppressAuthorizationPrompt: false,
    forceTlsWithoutMdns: false,
    androidUsbFd: false,
  );

  Future<Process> _start(List<String> arguments) async {
    if (_closed || !isServerAlive()) throw const AdbException('server_closed');
    final process = await Process.start(executable, [
      '-H',
      '127.0.0.1',
      '-P',
      '$port',
      ...arguments,
    ], environment: environment);
    if (_closed || !isServerAlive()) {
      await _terminate(process);
      throw const AdbException('server_closed');
    }
    _commands.add(process);
    unawaited(process.exitCode.then((_) => _commands.remove(process)));
    return process;
  }

  Future<({int exit, Uint8List stdout, Uint8List stderr})> _run(
    List<String> arguments,
    Duration timeout, {
    List<int>? input,
    AdbCancellation? cancellation,
  }) async {
    adbTimeoutMillis(timeout);
    cancellation?.check();
    final process = await _start(arguments);
    final out = BytesBuilder(), err = BytesBuilder();
    Object? failure;
    late StreamSubscription<List<int>> stdout, stderr;
    final outDone = Completer<void>(), errDone = Completer<void>();
    void add(BytesBuilder destination, List<int> bytes) {
      if (out.length + err.length + bytes.length > 1024 * 1024) {
        failure = const AdbException('output_limit');
        process.kill();
      } else {
        destination.add(bytes);
      }
    }

    stdout = process.stdout.listen(
      (b) => add(out, b),
      onDone: outDone.complete,
    );
    stderr = process.stderr.listen(
      (b) => add(err, b),
      onDone: errDone.complete,
    );
    try {
      if (input != null) process.stdin.add(input);
      await process.stdin.close();
      final result = await Future.any<int>([
        process.exitCode.timeout(timeout),
        if (cancellation != null)
          cancellation.whenCancelled.then<int>(
            (_) => throw const AdbException('cancelled'),
          ),
      ]);
      await Future.wait([outDone.future, errDone.future]);
      if (failure != null) throw failure!;
      return (exit: result, stdout: out.takeBytes(), stderr: err.takeBytes());
    } finally {
      await _terminate(process);
      await stdout.cancel();
      await stderr.cancel();
    }
  }

  @override
  Future<List<AdbDevice>> devices() async {
    final result = await _run(['devices', '-l'], const Duration(seconds: 10));
    if (result.exit != 0) throw const AdbException('devices_failed');
    final listed = LineSplitter.split(utf8.decode(result.stdout))
        .skip(1)
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final fields = line.trim().split(RegExp(r'\s+'));
          if (fields.length < 2) {
            throw const AdbException('invalid_devices_response');
          }
          return AdbDevice(
            id: fields.first,
            serial: fields.first,
            state: fields[1],
          );
        })
        .toList(growable: false);
    if (_bound == null) return listed;
    return Future.wait(
      listed.map(
        (device) =>
            device.state == 'device' ? _resolve(device) : Future.value(device),
      ),
    );
  }

  @override
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    validateAdbPath(address);
    // Official adb chooses its TLS handshake. It cannot suppress the Android
    // authorization dialog or offer an explicit plaintext downgrade policy.
    final target = requireTls ? await _tlsService(address, timeout) : address;
    if (!authorize) {
      final existing = (await devices()).where(
        (d) => d.serial == target && d.state == 'device',
      );
      if (existing.isNotEmpty) return existing.first;
      throw const AdbException('official_adb_cannot_suppress_authorization');
    }
    final result = await _run(['connect', target], timeout);
    final message = utf8.decode(result.stdout, allowMalformed: true).trim();
    if (result.exit != 0 ||
        (!message.startsWith('connected to ') &&
            !message.startsWith('already connected to '))) {
      throw const AdbException('connect_failed');
    }
    final previous = _connections.remove(target);
    if (previous != null) {
      final old = await previous;
      _handles.remove(old.id);
      await _nativeClient.api.disconnect(old.id);
    }
    final device = AdbDevice(id: target, serial: target, state: 'device');
    return _bound == null ? device : _resolve(device);
  }

  Future<String> _tlsService(String address, Duration timeout) async {
    final result = await _run(['mdns', 'services'], timeout);
    if (result.exit != 0) throw const AdbException('secure_mdns_unavailable');
    final services = <String>{};
    final endpoint = Uri.tryParse('tcp://$address');
    final candidates = <String>{};
    if (endpoint != null && endpoint.hasPort && endpoint.host.isNotEmpty) {
      for (final ip in await InternetAddress.lookup(endpoint.host)) {
        candidates.add('${ip.address}:${endpoint.port}');
      }
    }
    for (final line in LineSplitter.split(utf8.decode(result.stdout))) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length != 3 ||
          fields[1].replaceFirst(RegExp(r'\.$'), '') !=
              '_adb-tls-connect._tcp') {
        continue;
      }
      final fullname = '${fields[0]}._adb-tls-connect._tcp';
      if (candidates.contains(fields[2]) ||
          address.replaceFirst(RegExp(r'\.$'), '') == fullname) {
        services.add(fullname);
      }
    }
    if (services.length != 1) {
      throw const AdbException('secure_mdns_unavailable');
    }
    return services.single;
  }

  @override
  Future<void> disconnect(AdbDevice device) async {
    final pending = _connections.remove(device.serial);
    if (pending != null) {
      final fixed = await pending;
      _handles.remove(fixed.id);
      await _nativeClient.api.disconnect(fixed.id);
    }
    final result = await _run([
      'disconnect',
      device.serial,
    ], const Duration(seconds: 10));
    if (result.exit != 0) throw const AdbException('disconnect_failed');
  }

  @override
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    validateAdbPath(address);
    if (password.isEmpty ||
        password.contains('\n') ||
        password.contains('\r') ||
        password.length > 1024) {
      throw ArgumentError('Invalid pairing password');
    }
    final result = await _run(
      ['pair', address],
      timeout,
      input: utf8.encode('$password\n'),
    );
    final guid = RegExp(r'\[guid=([^\]]+)\]')
        .firstMatch(utf8.decode(result.stdout, allowMalformed: true))
        ?.group(1);
    if (result.exit != 0 || guid == null || guid.isEmpty) {
      throw const AdbException('pair_failed');
    }
    return guid;
  }

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    final fixed = await _resolve(device);
    yield* _nativeClient.shell(
      fixed,
      command,
      timeout: timeout,
      cancellation: cancellation,
    );
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
  }) async => _nativeClient.push(
    await _resolve(device),
    source,
    remotePath,
    maxBytes: maxBytes,
    permissions: permissions,
    timeout: timeout,
    cancellation: cancellation,
  );
  @override
  Future<int> pull(
    AdbDevice device,
    String remotePath,
    File destination, {
    int maxBytes = 1 << 40,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) async => _nativeClient.pull(
    await _resolve(device),
    remotePath,
    destination,
    maxBytes: maxBytes,
    timeout: timeout,
    cancellation: cancellation,
  );

  static Future<void> _terminate(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 2));
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    try {
      await services.close();
      await Future.wait(_commands.toList().map(_terminate));
      await Future.wait(
        _connections.values.map((future) async {
          try {
            await _nativeClient.api.disconnect((await future).id);
          } catch (_) {
            /* Already closed. */
          }
        }),
      );
    } finally {
      _connections.clear();
      _handles.clear();
    }
  }
}
