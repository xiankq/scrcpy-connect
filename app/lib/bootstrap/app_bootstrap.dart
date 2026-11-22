import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/bootstrap/app_composition.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_local_directories.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';

/// 完成启动与目录配置后交付功能绑定，配置失败仍由 bootstrap 关闭资源。
Future<AppBootstrap> bootstrapApp({
  Future<AppBootstrap> Function()? createSession,
  DiagnosticLog? diagnostics,
  Future<Directory> Function()? prepareOutgoingDirectory,
}) async {
  final session = await (createSession ?? () => _createSession(diagnostics))();
  try {
    final outgoing =
        await (prepareOutgoingDirectory ?? outgoingMediaDirectory)();
    await session.configureOutgoingDirectory(outgoing.path);
    return session;
  } catch (_) {
    try {
      await session.dispose();
    } catch (cleanup) {
      _recordCleanupFailure(diagnostics, 'outgoing_directory', cleanup);
    }
    rethrow;
  }
}

void _recordCleanupFailure(DiagnosticLog? log, String stage, Object error) {
  log?.record(
    DiagnosticArea.app,
    'bootstrap.cleanup.failed',
    level: LogLevel.error,
    fields: {'stage': stage, 'errorType': error.runtimeType.toString()},
  );
}

Future<AppBootstrap> _createSession(DiagnosticLog? diagnostics) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final session = await AppBootstrap.initialize(
    dataDirectory: await directory.resolveSymbolicLinks(),
    diagnostics: diagnostics,
  );
  return session;
}

/// 启动并发门禁与尚未交付宿主的所有者；功能资源由所属模块管理。
class AppBootstrap {
  AppBootstrap._(this._composition);
  final AppComposition _composition;
  bool get _disposed => _composition.lifecycle.isDisposed;
  late final List<Override> overrides = _composition.overrides(close: dispose);

  Future<void> configureOutgoingDirectory(String path) =>
      _composition.configureOutgoingDirectory(path);

  Future<void> dispose() => _composition.lifecycle.dispose().then((_) {
    if (identical(_active, this)) _active = null;
  });

  static Future<AppBootstrap>? _initializing;
  static String? _initializingDirectory;
  static String? _initializingPolicyJson;
  static String? _initializingBinaryDirectory;
  static AppBootstrap? _active;
  // 功能装配尚未完成时也保留精确分享所有者，关闭失败由下次启动重试。
  static FileShareService? _startingSharing;
  static NativeHost? _startingHost;

  static Future<AppBootstrap> initialize({
    required String dataDirectory,
    Directory? adbBinaryDirectory,
    ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
    DiagnosticLog? diagnostics,
  }) {
    if (_active case final existing? when !existing._disposed) {
      return Future.error(
        const RequestFailure(
          'application_already_initialized',
          '此引擎已有应用会话，请复用现有实例。',
        ),
      );
    }
    if (_initializing != null && _initializingDirectory != dataDirectory) {
      return Future.error(
        const RequestFailure(
          'runtime_directory_mismatch',
          '应用正在使用另一个私有目录，请重新启动应用。',
        ),
      );
    }
    final policyJson = jsonEncode(connectionPolicy.toJson());
    if (_initializing != null && _initializingPolicyJson != policyJson) {
      return Future.error(
        const RequestFailure(
          'runtime_connection_policy_mismatch',
          '应用正在使用另一套连接策略，请重新启动应用。',
        ),
      );
    }
    final binaryPath = adbBinaryDirectory?.absolute.path;
    if (_initializing != null &&
        binaryPath != null &&
        binaryPath != _initializingBinaryDirectory) {
      return Future.error(
        const RequestFailure(
          'runtime_adb_binary_mismatch',
          '应用正在使用另一套 ADB 执行产物初始化。',
        ),
      );
    }
    _initializingBinaryDirectory ??= binaryPath;
    _initializingPolicyJson = policyJson;
    _initializingDirectory = dataDirectory;
    return _initializing ??=
        _initialize(
          dataDirectory,
          connectionPolicy,
          diagnostics,
          adbBinaryDirectory,
        ).whenComplete(() {
          _initializing = null;
          _initializingDirectory = null;
          _initializingPolicyJson = null;
          _initializingBinaryDirectory = null;
        });
  }

  static Future<AppBootstrap> _initialize(
    String dataDirectory,
    ConnectionPolicy policy,
    DiagnosticLog? diagnostics,
    Directory? adbBinaryDirectory,
  ) async {
    final previous = _active;
    if (previous != null && previous._disposed) {
      // 新附着必须先等待旧协调器的原生释放，不能提前接管重试所有权。
      await previous.dispose();
    }
    await _closeStartingResources();
    final host = await NativeHost.attach(
      dataDirectory: dataDirectory,
      connectionPolicy: policy,
      adbBinaryDirectory: adbBinaryDirectory,
    );
    _startingHost = host;
    AppBootstrap? session;
    try {
      session = await _assemble(host, dataDirectory, policy, diagnostics);
      // 会话接管启动阶段取得的资源。
      _startingHost = null;
      _startingSharing = null;
      await session._composition.lifecycle.activate();
      _active = session;
      return session;
    } catch (_) {
      try {
        if (session == null) {
          await _closeStartingResources();
        } else {
          _active = session;
          await session.dispose();
        }
      } catch (cleanup) {
        _recordCleanupFailure(
          diagnostics,
          session == null ? 'assemble' : 'activate',
          cleanup,
        );
      }
      rethrow;
    }
  }

  /// 先关闭分享复制，再关闭承载宿主；失败时保留原登记供下次重试。
  static Future<void> _closeStartingResources() async {
    if (_startingSharing case final sharing?) {
      await sharing.close();
      _startingSharing = null;
    }
    if (_startingHost case final host?) {
      await host.close();
      _startingHost = null;
    }
  }

  static Future<AppBootstrap> _assemble(
    NativeHost host,
    String dataDirectory,
    ConnectionPolicy policy,
    DiagnosticLog? diagnostics,
  ) async => AppBootstrap._(
    await AppComposition.open(
      host,
      dataDirectory,
      policy,
      diagnostics,
      onSharingOpened: (sharing) => _startingSharing = sharing,
    ),
  );
}
