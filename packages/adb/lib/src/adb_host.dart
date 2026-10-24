import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'api.dart';
import 'native/initialize.dart';
import 'native_client.dart';
import 'official_client.dart';
import 'official_server_readiness.dart';

/// 持有同一原生库内的服务器租约和连接；Child 不随 Dart isolate 消失。
class AdbHost {
  AdbHost._(this._bindings, this._identityPath, this._server);

  final NativeAdbApi _bindings;
  final String _identityPath;
  final AdbServerInfo? _server;
  late final AdbClient _client;
  Future<void>? _closing;

  AdbClient get client => _client;

  /// 仅投影当前登记事实；恢复权限来自原生 lease，端口与 PID 不授予关闭权。
  Map<String, Object?>? get nativeConfiguration {
    final server = _server;
    if (server == null) return null;
    final endpoint = Uri.parse('tcp://${server.launch.endpoint}');
    final home = server.launch.environment['ANDROID_USER_HOME'];
    final oneDevice = server.launch.arguments.indexOf('--one-device');
    return Map.unmodifiable({
      'serverId': server.serverId,
      'leaseId': server.leaseId,
      'host': endpoint.host,
      'port': endpoint.port,
      'executablePath': server.launch.executable,
      'keyDirectory': home == null ? null : p.dirname(home),
      'identityPath': _identityPath,
      'oneDevice': oneDevice < 0
          ? null
          : server.launch.arguments[oneDevice + 1],
    });
  }

  /// 官方服务器、准备命令和连接必须从启动前就使用同一份 bindings。
  static Future<AdbHost> prepare({
    required Directory dataDirectory,
    Directory? binaryDirectory,
    String? identityPath,
    String? oneDevice,
    NativeAdbApi? bindings,
    AdbAdmissionScopeInfo? admissionScope,
    Duration startupTimeout = const Duration(seconds: 15),
  }) async {
    final timeoutMs = adbTimeoutMillis(startupTimeout);
    if (oneDevice != null &&
        (oneDevice.isEmpty || oneDevice.contains(RegExp(r'[\x00\r\n]')))) {
      throw ArgumentError.value(oneDevice, 'oneDevice');
    }
    final api = bindings ?? await createNativeAdbApi();
    final identity = File(
      identityPath ?? p.join(dataDirectory.absolute.path, 'host_identity.pem'),
    ).absolute;
    if (identityPath != null &&
        await FileSystemEntity.type(identity.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw FileSystemException(
        'The selected ADB identity must already exist',
        identity.path,
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final host = AdbHost._(api, identity.path, null);
      host._client = NativeAdbClient(
        api,
        identity.path,
        admissionScope: admissionScope,
        ownsAdmissionScope: false,
      );
      return host;
    }
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      throw UnsupportedError('ADB is unavailable on this host platform');
    }
    if (api is! NativeAdbServerApi || api is! NativeAdbHandshakeApi) {
      throw const AdbException('owned_server_capability_unavailable');
    }
    if (api is! AdbIdentities) {
      throw const AdbException('identity_capability_unavailable');
    }
    if (admissionScope != null && api is! NativeAdbScopedServerApi) {
      throw const AdbException('scoped_server_capability_unavailable');
    }
    final identities = api as AdbIdentities;
    final inspected = await identities.inspectIdentity(identity.path);
    final servers = api as NativeAdbServerApi;
    final executable = p.join(
      binaryDirectory?.absolute.path ?? _packagedDirectory(),
      Platform.isWindows ? 'adb.exe' : 'adb',
    );
    if (!await File(executable).exists()) {
      throw FileSystemException(
        'Bundled official ADB executable is missing',
        executable,
      );
    }
    final serverRoot = Directory(
      p.join(dataDirectory.absolute.path, 'official_adb'),
    );
    await serverRoot.create(recursive: true);
    // 每个服务器独占 key home，不能覆盖仍存活服务器读取过的授权身份。
    final root = await serverRoot.createTemp('scope-');
    AdbServerInfo? registered;
    try {
      final home = await Directory(p.join(root.path, 'global')).create();
      final environment = <String, String>{
        'ANDROID_USER_HOME': home.path,
        'ADB_VENDOR_KEYS': identity.path,
        'ADB_MDNS_AUTO_CONNECT': '0',
        'ADB_LIBUSB': '1',
        'ADB_LOCAL_TRANSPORT_MAX_PORT': '0',
      };
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final launch = AdbServerLaunchSpec(
        executable: executable,
        arguments: [
          if (oneDevice != null) ...['--one-device', oneDevice],
          '-L',
          'tcp:$port',
          'server',
          'nodaemon',
        ],
        environment: environment,
        endpoint: '127.0.0.1:$port',
      );
      registered = admissionScope == null
          ? await servers.createServer(launch)
          : await (api as NativeAdbScopedServerApi).createScopedServer(
              launch,
              admissionScope.scopeId,
            );
      if (inspected == null) {
        // 缺失身份原子创建，已有身份只校验，不能并发 keygen 覆盖先完成的私钥。
        await identities.prepareIdentity(identity.path);
      }
      await identities.inspectIdentity(identity.path);
      final serverKey = File(p.join(home.path, 'adbkey'));
      await identity.copy(serverKey.path);
      if (!Platform.isWindows) {
        await _prepareCommand(
          servers,
          registered.leaseId,
          await _chmodExecutable(),
          ['600', serverKey.path],
          timeoutMs,
        );
      }
      final ready = await servers.startServer(registered.leaseId, timeoutMs);
      registered = ready;
      // ACK 证明精确 Child 已监听；协议探测另行证明该监听者已能处理 ADB 请求。
      await waitForOfficialAdbServer(
        port,
        hasExited: () => false,
        timeout: startupTimeout,
      );
      final host = AdbHost._(api, identity.path, ready);
      host._client = OfficialAdbClient(api, ready);
      if (admissionScope != null) {
        await (api as NativeAdbScopedServerApi).confirmScopedServer(
          ready.leaseId,
          admissionScope.scopeId,
        );
      }
      return host;
    } catch (_) {
      if (registered != null) {
        // 失败必须等待同一 Child 和命令确实结束；关闭失败时保留原生登记和 key home。
        await servers.closeServer(registered.leaseId);
        // 探测期间可能已被其他 isolate 认领；旧 lease 关闭无害，不代表新 owner 已排空。
        if ((await servers.listServers()).any(
          (entry) => entry.serverId == registered!.serverId,
        )) {
          rethrow;
        }
      }
      await _removeDirectory(root);
      rethrow;
    }
  }

  /// 仅接受原生登记的当前 lease；旧地图可以传入，但没有 lease 的端点配置不能恢复。
  static Future<AdbHost> restore({
    required Directory dataDirectory,
    Map<String, Object?>? nativeConfiguration,
    String? leaseId,
    Directory? binaryDirectory,
    NativeAdbApi? bindings,
    AdbAdmissionScopeInfo? admissionScope,
    Duration startupTimeout = const Duration(seconds: 15),
  }) async {
    adbTimeoutMillis(startupTimeout);
    final api = bindings ?? await createNativeAdbApi();
    if (api is! NativeAdbServerApi || api is! NativeAdbHandshakeApi) {
      throw const AdbException('owned_server_capability_unavailable');
    }
    if (admissionScope != null && api is! NativeAdbScopedServerApi) {
      throw const AdbException('scoped_server_capability_unavailable');
    }
    final requested = leaseId ?? nativeConfiguration?['leaseId'];
    if (requested is! String || requested.isEmpty) {
      throw const AdbException('invalid_host_configuration');
    }
    final servers = api as NativeAdbServerApi;
    final matches = (await servers.listServers())
        .where((entry) => entry.leaseId == requested)
        .toList();
    if (matches.length != 1 ||
        (matches.single.phase != AdbServerPhase.ready &&
            matches.single.phase != AdbServerPhase.exited)) {
      throw const AdbException('host_unavailable');
    }
    final previous = matches.single;
    final dataRoot = await dataDirectory.resolveSymbolicLinks();
    final expectedKeys = await Directory(p.join(dataRoot, 'official_adb'))
        .resolveSymbolicLinks();
    final home = previous.launch.environment['ANDROID_USER_HOME'];
    final identityPath = previous.launch.environment['ADB_VENDOR_KEYS'];
    if (home == null || identityPath == null) {
      throw const AdbException('invalid_host_configuration');
    }
    final actualKeys = await Directory(p.dirname(home)).resolveSymbolicLinks();
    if (p.dirname(actualKeys) != expectedKeys ||
        !p.basename(actualKeys).startsWith('scope-')) {
      throw const AdbException('host_directory_mismatch');
    }
    if (binaryDirectory != null &&
        await File(
              p.join(
                binaryDirectory.path,
                Platform.isWindows ? 'adb.exe' : 'adb',
              ),
            ).resolveSymbolicLinks() !=
            await File(previous.launch.executable).resolveSymbolicLinks()) {
      throw const AdbException('host_executable_mismatch');
    }
    if (!await File(identityPath).exists()) {
      throw const AdbException('host_resource_missing');
    }
    // 只比较并交换原租约；排队认领不能撤销刚刚交给别人的新租约。
    final claimed = admissionScope == null
        ? await servers.claimServer(previous.leaseId)
        : await (api as NativeAdbScopedServerApi).claimScopedServer(
            previous.leaseId,
            admissionScope.scopeId,
          );
    final restored = AdbHost._(api, identityPath, claimed);
    restored._client = OfficialAdbClient(api, claimed);
    if (admissionScope != null) {
      try {
        await (api as NativeAdbScopedServerApi).confirmScopedServer(
          claimed.leaseId,
          admissionScope.scopeId,
        );
      } catch (_) {
        // 确认失败仍须回收同一实际服务器；失败登记由原生保留以便重试。
        await restored.close();
        rethrow;
      }
    }
    return restored;
  }

  static Future<String> _chmodExecutable() async {
    for (final path in ['/usr/bin/chmod', '/bin/chmod']) {
      if (await File(path).exists()) return File(path).resolveSymbolicLinks();
    }
    throw const AdbException('private_file_permissions_unavailable');
  }

  static String _packagedDirectory() {
    final directory = p.dirname(Platform.resolvedExecutable);
    return Platform.isMacOS
        ? p.normalize(p.join(directory, '..', 'Resources', 'adb'))
        : p.join(directory, 'adb');
  }

  static Future<void> _prepareCommand(
    NativeAdbServerApi api,
    String leaseId,
    String executable,
    List<String> arguments,
    int timeoutMs,
  ) async {
    final id = await api.createServerCommand(
      leaseId,
      AdbServerCommandSpec(
        executable: executable,
        arguments: arguments,
        input: Uint8List(0),
        timeoutMs: timeoutMs,
        preparation: true,
      ),
    );
    try {
      final result = await api.runServerCommand(id);
      if (result.status != AdbServerCommandStatus.exited ||
          result.exitCode != 0) {
        throw AdbException(
          'host_preparation_failed',
          result.errorMessage ?? '',
        );
      }
    } finally {
      await api.closeServerCommand(id);
    }
  }

  Future<void> close() {
    if (_closing case final operation?) return operation;
    late final Future<void> operation;
    operation = _close().catchError((Object error, StackTrace stack) {
      if (identical(_closing, operation)) _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
    return _closing = operation;
  }

  Future<void> _close() async {
    await _client.close();
    final server = _server;
    if (server == null) return;
    final servers = _bindings as NativeAdbServerApi;
    await servers.closeServer(server.leaseId);
    final current = (await servers.listServers()).where(
      (entry) => entry.serverId == server.serverId,
    );
    if (current.isNotEmpty) return;
    final home = server.launch.environment['ANDROID_USER_HOME'];
    if (home != null) await _removeDirectory(Directory(p.dirname(home)));
  }

  static Future<void> _removeDirectory(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on PathNotFoundException {
      // 原生确认退出后，重复关闭可重复清理同一临时 key home。
    }
  }
}
