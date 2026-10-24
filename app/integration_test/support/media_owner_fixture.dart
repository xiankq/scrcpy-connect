import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';
import 'package:scrcpy_connect/connection/connection_policy.dart';
import 'package:scrcpy_connect/connection/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/media/capture/app_launch_store.dart';
import 'package:scrcpy_connect/media/capture/device_audio_source_coordinator.dart';
import 'package:scrcpy_connect/media/capture/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/media/capture/session_coordinator.dart';
import 'package:scrcpy_connect/platform/native/bundled_servers.dart';

/// 真实媒体测试共同持有的连接与业务所有者；播放器由各测试独立持有。
/// 不提供产品命令路由，也不替代应用启动与恢复策略。
final class MediaOwnerFixture {
  MediaOwnerFixture._(this._host, this._queries, this._launches) {
    videoSource = ScrcpyCaptureAdapter(scrcpy.api);
    sessions = SessionCoordinator(
      scrcpy: scrcpy,
      requireConnection: _requireConnection,
      launches: _launches,
      serverQueries: _queries,
      emit: (_, _, _) {},
      onAudioEligibilityChanged: (id) {
        // eligibilityChanged 在返回 Future 前同步撤销资格；随后保留真实排空责任。
        final task = audio.eligibilityChanged(id);
        final settled = task.then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            _eligibilityFailures.add((error, stack));
          },
        );
        _eligibilityTasks.add(settled);
        unawaited(
          settled.then<void>((_) {
            _eligibilityTasks.remove(settled);
          }),
        );
      },
    );
    audio = DeviceAudioSourceCoordinator(
      requireConnection: _requireConnection,
      scrcpy: scrcpy,
      hasAudioOwner: sessions.hasAudioOwner,
      emit: (_, _, _) {},
    );
  }

  static const _deviceId = '670cd207-a717-4e4d-af9e-e98581731b75';
  // 启动失败也不能丢失精确关闭权；下次打开先重试这批测试资源。
  static final _retiring = <MediaOwnerFixture>{};
  final ScrcpyNativeHost _host;
  final ScrcpyServerQueries _queries;
  final AppLaunchStore _launches;
  DeviceConnection? _connection;
  final _eligibilityTasks = <Future<void>>{};
  final _eligibilityFailures = <(Object, StackTrace)>[];
  bool _closed = false, _disconnected = false, _released = false;
  Future<void>? _closing;

  String get deviceId => _deviceId;
  DeviceConnection get connection =>
      _connection ??
      (throw const ApplicationCommandException(
        'disconnected',
        '测试宿主尚未取得真实连接。',
      ));
  ScrcpyClient get scrcpy => _host.scrcpy;
  late final SessionCoordinator sessions;
  late final DeviceAudioSourceCoordinator audio;
  late final ScrcpyCaptureAdapter videoSource;

  static Future<MediaOwnerFixture> open({
    required String dataDirectory,
    required String address,
    ConnectionPolicy policy = const ConnectionPolicy(),
  }) async {
    policy.validate();
    if (address.isEmpty || address.contains(RegExp(r'[\x00\r\n]'))) {
      throw ArgumentError.value(address, 'address');
    }
    for (final previous in _retiring.toList()) {
      await previous.close();
    }
    final directory = Directory(dataDirectory).absolute;
    await directory.create(recursive: true);
    final servers = await BundledServers().prepare(directory);
    // 公开 SDK 负责原子创建及校验；已有 E2E 私钥绝不被测试覆盖。
    final queries = ScrcpyServerQueries(
      serverBytes: servers.scrcpyBytes,
      timeout: policy.probeTimeout,
    );
    final launches = await AppLaunchStore.open(directory: directory);
    final host = await createNativeScrcpyHost(
      serverBytes: servers.scrcpyBytes,
      identityPath: p.join(directory.path, 'host_identity.pem'),
      dataDirectory: directory,
      binaryDirectory: _binaryDirectory(),
    );
    final fixture = MediaOwnerFixture._(host, queries, launches);
    try {
      _retiring.add(fixture);
      final device = await host.adb.connect(
        address,
        authorize: policy.requestAuthorization,
        timeout: policy.connectTimeout,
        directOptions: Platform.isAndroid || Platform.isIOS
            ? policy.directConnectOptions(burstMode: false)
            : null,
      );
      fixture._connection = DeviceConnection(client: host.adb, device: device);
      _retiring.remove(fixture);
      return fixture;
    } catch (error, stack) {
      // 关闭失败交还精确错误并保留原对象；不能启动另一个宿主掩盖未释放资源。
      await fixture.close();
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Directory? _binaryDirectory() {
    if (Platform.isAndroid || Platform.isIOS) return null;
    const configured = String.fromEnvironment('CONNECT_E2E_ADB_DIRECTORY');
    if (configured.isNotEmpty) return Directory(configured);
    final controlled = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
    if (controlled != null && controlled.isNotEmpty) {
      return File(controlled).absolute.parent;
    }
    var root = Directory.current.absolute;
    while (true) {
      final candidate = Directory(
        p.join(root.path, '.dart_tool', 'adb', Platform.operatingSystem),
      );
      if (File(p.join(candidate.path, Platform.isWindows ? 'adb.exe' : 'adb'))
          .existsSync()) {
        return candidate;
      }
      if (root.parent.path == root.path) return null;
      root = root.parent;
    }
  }

  DeviceConnection _requireConnection(String id) {
    if (id != deviceId || _closed || _disconnected) {
      throw const ApplicationCommandException('disconnected', '这次测试的精确连接已撤销。');
    }
    return connection;
  }

  /// 包数来自同库原生来源；不能据此声称像素已呈现或声音可闻。
  Future<Map<String, dynamic>> sourceStatus(String nativeSourceId) async {
    _requireConnection(deviceId);
    for (final session in await sessions.snapshots()) {
      if (session['videoSourceId'] != nativeSourceId) continue;
      final captureRef = session['captureRef'] as String;
      final status = await scrcpy.sourceStatus(
        connection.device,
        captureRef: captureRef,
        sourceId: nativeSourceId,
      );
      _requireConnection(deviceId);
      if (status.captureRef != captureRef ||
          status.sourceId != nativeSourceId ||
          status.kind != ScrcpySourceKind.video) {
        throw const ApplicationCommandException('stale_capture', '测试视频来源已被替换。');
      }
      return {
        'relayId': nativeSourceId,
        'sourceId': nativeSourceId,
        'captureRef': captureRef,
        'kind': status.kind.name,
        'codec': status.codec,
        'generation': status.generation,
        'status': status.status.name,
        'packets': status.packets,
        'bytes': status.bytes,
      };
    }
    return Map<String, dynamic>.from(await audio.sourceStatus(nativeSourceId));
  }

  /// 调用方先释放自己的播放器；所有捕获排空后才释放连接及私有服务器。
  Future<void> close() {
    if (_released) return Future.value();
    _closed = true;
    _retiring.add(this);
    return _closing ??= _close().whenComplete(() {
      _closing = null;
    });
  }

  Future<void> _close() async {
    final failures = <(Object, StackTrace)>[];
    // 尝试全部独立媒体所有者，但任何失败都禁止提前断开其借用连接。
    for (final close in [audio.close, sessions.close, _queries.close]) {
      try {
        await close();
      } catch (error, stack) {
        failures.add((error, stack));
      }
    }
    while (_eligibilityTasks.isNotEmpty) {
      await Future.wait(_eligibilityTasks.toList());
    }
    failures.addAll(_eligibilityFailures);
    _eligibilityFailures.clear();
    if (failures.isNotEmpty) {
      Error.throwWithStackTrace(failures.first.$1, failures.first.$2);
    }
    if (!_disconnected) {
      if (_connection case final exact?) {
        await exact.client.disconnect(exact.device);
      }
      _disconnected = true;
    }
    await _host.close();
    _released = true;
    _retiring.remove(this);
  }
}
