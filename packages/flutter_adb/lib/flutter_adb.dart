/// Selects Rust's direct mobile transport or an owned official desktop server.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'src/api.dart';
import 'src/native_client.dart';
import 'src/official_client.dart';
import 'src/readiness.dart';

export 'src/api.dart';
export 'src/native_client.dart' show NativeAdbClient;

/// The app owns this object for the entire native Runtime lifetime. Closing it
/// ends only its own official ADB server, never a user's server on port 5037.
class FlutterAdb {
  FlutterAdb._(
    this.nativeConfiguration,
    this._process,
    this._exitCode,
    this._identityPath,
  );

  final Map<String, Object?>? nativeConfiguration;
  final Process? _process;
  final Future<int>? _exitCode;
  Future<void>? _closing;
  bool _closed = false;
  bool _serverExited = false;
  final String _identityPath;
  AdbClient? _client;

  /// Connections and services are available after bindNative.
  AdbClient get client =>
      _client ??
      (throw StateError('Native ADB bindings have not been attached'));

  void bindNative(NativeAdbApi bindings) {
    if (_closed) throw StateError('ADB backend is closed');
    if (_client case final OfficialAdbClient official) {
      official.bindNative(bindings);
    } else if (_client == null) {
      _client = NativeAdbClient(bindings, _identityPath);
    } else {
      throw StateError('ADB backend already attached');
    }
  }

  /// [binaryDirectory] is an explicit package/test override; PATH is never used
  /// to silently select another ADB version or fall back to direct desktop ADB.
  static Future<FlutterAdb> prepare({
    required Directory dataDirectory,
    Directory? binaryDirectory,
    Duration startupTimeout = const Duration(seconds: 15),
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return FlutterAdb._(
        null,
        null,
        null,
        p.join(dataDirectory.absolute.path, 'host_identity.pem'),
      );
    }
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      throw UnsupportedError('ADB is unavailable on this host platform');
    }
    final executable = p.join(
      binaryDirectory?.path ?? _packagedDirectory(),
      Platform.isWindows ? 'adb.exe' : 'adb',
    );
    if (!await File(executable).exists()) {
      throw FileSystemException(
        'Bundled official ADB executable is missing',
        executable,
      );
    }
    final root = Directory(p.join(dataDirectory.absolute.path, 'official_adb'));
    final home = Directory(p.join(root.path, 'global'));
    await home.create(recursive: true);
    // Keep the same key as Rust's identity owner. Official ADB creates a PKCS#1
    // PEM which the mobile identity implementation can also read after restore.
    final identity = File(
      p.join(dataDirectory.absolute.path, 'host_identity.pem'),
    );
    final environment = <String, String>{
      'ANDROID_USER_HOME': home.path,
      'ADB_VENDOR_KEYS': identity.path,
      'ADB_MDNS_AUTO_CONNECT': '0',
      'ADB_LIBUSB': '1',
      'ADB_LOCAL_TRANSPORT_MAX_PORT': '0',
    };
    if (!await identity.exists()) {
      await _run(
        executable,
        ['keygen', identity.path],
        environment,
        startupTimeout,
      );
    }
    final serverKey = File(p.join(home.path, 'adbkey'));
    await identity.copy(serverKey.path);
    if (!Platform.isWindows) {
      await _run(
        'chmod',
        ['600', serverKey.path, identity.path],
        const {},
        startupTimeout,
      );
    }
    // Bind/release before spawning. If another process wins the port race, our
    // child exits and startup fails; we never adopt or kill that other process.
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final process = await Process.start(executable, [
      '-L',
      'tcp:$port',
      'server',
      'nodaemon',
    ], environment: environment);
    final exitCode = process.exitCode;
    var exited = false;
    unawaited(exitCode.then((_) => exited = true));
    // Native logs may include device data. Drain streams without retaining or
    // forwarding their unrestricted text into application diagnostics.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final host = FlutterAdb._(
      {
        'host': '127.0.0.1',
        'port': port,
        'executablePath': executable,
        'keyDirectory': root.path,
      },
      process,
      exitCode,
      identity.path,
    );
    unawaited(exitCode.then((_) => host._serverExited = true));
    host._client = OfficialAdbClient(
      executable,
      port,
      environment,
      () => !exited && !host._closed,
    );
    try {
      await waitForOfficialAdbServer(
        port,
        hasExited: () => exited,
        timeout: startupTimeout,
      );
      return host;
    } catch (_) {
      await host.close();
      rethrow;
    }
  }

  static String _packagedDirectory() {
    final executableDirectory = p.dirname(Platform.resolvedExecutable);
    return Platform.isMacOS
        ? p.normalize(p.join(executableDirectory, '..', 'Resources', 'adb'))
        : p.join(executableDirectory, 'adb');
  }

  static Future<void> _run(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
    Duration timeout,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
    );
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    try {
      if (await process.exitCode.timeout(timeout) != 0) {
        throw StateError('Official ADB preparation failed');
      }
    } catch (_) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(const Duration(seconds: 2));
      }
      rethrow;
    }
  }

  Future<void> close() {
    if (_closing case final operation?) return operation;
    _closed = true;
    late final Future<void> operation;
    operation = _close().catchError((Object error, StackTrace stack) {
      if (identical(_closing, operation)) _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
    _closing = operation;
    return operation;
  }

  Future<void> _close() async {
    try {
      await _client?.close().timeout(const Duration(seconds: 2));
    } finally {
      final process = _process;
      if (process != null && !_serverExited) {
        // Ask this owned numeric endpoint to exit normally first. -H prevents
        // adb from starting a replacement daemon if this one has just exited.
        try {
          await _run(
            nativeConfiguration!['executablePath'] as String,
            [
              '-H',
              '127.0.0.1',
              '-P',
              '${nativeConfiguration!['port']}',
              'kill-server',
            ],
            const {},
            const Duration(seconds: 2),
          );
          await _exitCode!.timeout(const Duration(seconds: 2));
        } catch (_) {
          if (!_serverExited) {
            process.kill();
            try {
              await _exitCode!.timeout(const Duration(seconds: 2));
            } on TimeoutException {
              process.kill(ProcessSignal.sigkill);
              await _exitCode!.timeout(const Duration(seconds: 2));
            }
          }
        }
      }
    }
  }
}
