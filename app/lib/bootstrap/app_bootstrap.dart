import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:scrcpy_connect/bootstrap/app_composition.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_local_directories.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';

/// 全部启动配置成功前由 bootstrap 拥有应用依赖，返回依赖后交给 provider scope。
Future<AppDependencies> bootstrapApp({
  Future<AppDependencies> Function()? createDependencies,
  DiagnosticLog? diagnostics,
  Future<Directory> Function()? prepareOutgoingDirectory,
}) async {
  final dependencies =
      await (createDependencies ?? () => _createDependencies(diagnostics))();
  try {
    final outgoing =
        await (prepareOutgoingDirectory ?? outgoingMediaDirectory)();
    await dependencies.cache.configure(outgoingDirectory: outgoing.path);
    return dependencies;
  } catch (error, stack) {
    try {
      await dependencies.close?.call();
    } catch (_) {
      // 即使清理失败，也保留最初可操作的启动错误。
    }
    Error.throwWithStackTrace(error, stack);
  }
}

Future<AppDependencies> _createDependencies(DiagnosticLog? diagnostics) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final session = await AppBootstrap.initialize(
    dataDirectory: await directory.resolveSymbolicLinks(),
    diagnostics: diagnostics,
  );
  return session.dependencies;
}

/// 启动并发门禁与尚未交付资源的所有者；完整依赖图交由应用运行时管理。
final class AppBootstrap {
  AppBootstrap._(this._composition);
  final AppComposition _composition;
  bool get _disposed => _composition.lifecycle.isDisposed;
  late final AppDependencies dependencies = _composition.dependencies(
    close: dispose,
  );

  Future<void> dispose() => _composition.lifecycle.dispose().then((_) {
    if (identical(_active, this)) _active = null;
  });

  static Future<AppBootstrap>? _initializing;
  static String? _initializingDirectory;
  static String? _initializingPolicyJson;
  static String? _initializingBinaryDirectory;
  static AppBootstrap? _active;
  // 组装尚未交付给 Session 时也保留精确分享所有者，关闭失败由下次启动重试。
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
    try {
      final session = await _assemble(host, dataDirectory, policy, diagnostics);
      // 此后所有资源交由会话关闭；启动活动失败也必须通过同一会话重试清理。
      _startingHost = null;
      _startingSharing = null;
      try {
        await session._composition.lifecycle.activate();
        _active = session;
        return session;
      } catch (error, stack) {
        _active = session;
        try {
          await session.dispose();
        } catch (_) {
          // 失败所有者留给下一次附着重试，原始启动异常仍是本次失败原因。
        }
        Error.throwWithStackTrace(error, stack);
      }
    } catch (error, stack) {
      try {
        await _closeStartingResources();
      } catch (_) {
        // 未确认关闭的原实例仍在静态登记中，后继启动必须先完成收尾。
      }
      Error.throwWithStackTrace(error, stack);
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
