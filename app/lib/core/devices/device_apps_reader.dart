import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/companion/companion_exception.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/models/device_record.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;

/// 安装清单读取 scrcpy；后台任务和图标读取伴生协议，不互相回退。
final class DeviceAppsReader implements DeviceApps {
  DeviceAppsReader({
    required this._requireConnection,
    required this._currentConnection,
    required this._connectionId,
    required this._serverQueries,
    required this._companion,
    required this._isDisposed,
    this.onFailure,
  });
  final DeviceConnection Function(String) _requireConnection;
  final DeviceConnection? Function(String) _currentConnection;
  final String? Function(String) _connectionId;
  final ScrcpyServerQueries _serverQueries;
  final CompanionService _companion;
  final bool Function() _isDisposed;
  final void Function(
    String label,
    String deviceId,
    Object error,
    int elapsedMs,
  )?
  onFailure;

  static final _package = RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$');
  static bool _validPackage(String package) =>
      package.isNotEmpty && package.length <= 255 && _package.hasMatch(package);

  Future<T> _read<T>(
    String label,
    String deviceId,
    AdbCancellation? cancellation,
    Future<T> Function(
      DeviceConnection connection,
      AdbCancellation cancellation,
    )
    read, {
    void Function()? validate,
  }) async {
    final clock = Stopwatch()..start();
    try {
      if (_isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
      if (deviceId.isEmpty || deviceId.contains('\u0000')) {
        throw const RequestFailure('invalid_device_id', '设备标识无效。');
      }
      final token = cancellation ?? AdbCancellation();
      token.check();
      validate?.call();
      final connection = _requireConnection(deviceId);
      final value = await read(connection, token);
      token.check();
      if (_isDisposed() ||
          !identical(_currentConnection(deviceId), connection)) {
        throw const RequestFailure('cancelled', '设备连接已改变，旧应用读取不再适用。');
      }
      return value;
    } catch (error, stack) {
      final failure = switch (error) {
        CompanionException(:final code, :final message) => RequestFailure(
          code,
          message,
        ),
        AdbException(:final code, :final message) => RequestFailure(
          code,
          message,
        ),
        _ => error,
      };
      onFailure?.call(label, deviceId, failure, clock.elapsedMilliseconds);
      Error.throwWithStackTrace(failure, stack);
    }
  }

  @override
  Future<List<DeviceApp>> readInstalledApps(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _read(
    'apps.installed',
    deviceId,
    cancellation,
    (connection, token) async => List.unmodifiable(
      await _serverQueries.installedApps(connection, token),
    ),
    validate: () {
      if (!validDeviceId(deviceId)) {
        throw const RequestFailure('invalid_device_id', '设备标识无效。');
      }
    },
  );

  @override
  Future<RunningDeviceApps> readRunningApps(
    String deviceId, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  }) => _read('apps.running', deviceId, cancellation, (
    connection,
    token,
  ) async {
    final connectionId = _connectionId(deviceId);
    final response = await _companion.request(
      deviceId,
      'apps.list',
      {'filter': 'running'},
      allowStart: allowStart,
      expectedConnection: connection,
      cancellation: token,
    );
    if (response
        case {
          'deviceId': final String owner,
          'source': 'runningTasks',
          'live': true,
          'userId': final int user,
          'apps': final List<Object?> apps,
        }
        when owner == deviceId && user >= 0) {
      final entries = [for (final raw in apps) _runningApp(raw, user)];
      return RunningDeviceApps(
        deviceId: deviceId,
        connectionId: connectionId,
        userId: user,
        apps: entries,
      );
    }
    throw const RequestFailure('apps_running_unavailable', '当前设备未提供有效的后台应用列表。');
  });

  @override
  Future<DeviceAppIcon> readAppIcon(
    String deviceId,
    String packageName, {
    int? userId,
    bool allowStart = true,
    AdbCancellation? cancellation,
  }) => _read(
    'apps.icon',
    deviceId,
    cancellation,
    (connection, token) async {
      final response = await _companion.request(
        deviceId,
        'apps.icon',
        {'packageName': packageName},
        allowStart: allowStart,
        expectedConnection: connection,
        cancellation: token,
      );
      if (response
          case {
            'deviceId': final String owner,
            'packageName': final String package,
            'mimeType': 'image/png',
            'userId': final int user,
            'dataBase64': final String data,
            'width': final int width,
            'height': final int height,
          }
          when owner == deviceId &&
              package == packageName &&
              user >= 0 &&
              (userId == null || user == userId) &&
              data.isNotEmpty &&
              data.length <= 2 * 1024 * 1024 &&
              width > 0 &&
              width <= 512 &&
              height > 0 &&
              height <= 512) {
        final Uint8List bytes;
        try {
          bytes = base64Decode(data);
        } on FormatException {
          throw const RequestFailure('invalid_response', '设备图标编码无效。');
        }
        return DeviceAppIcon(
          deviceId: deviceId,
          packageName: packageName,
          userId: user,
          bytes: bytes,
          width: width,
          height: height,
        );
      }
      throw const RequestFailure('invalid_response', '设备图标不属于已核验的应用与用户。');
    },
    validate: () {
      if (!_validPackage(packageName) || (userId != null && userId < 0)) {
        throw const RequestFailure('invalid_argument', '请指定有效的应用包名与用户。');
      }
    },
  );

  static DeviceApp _runningApp(Object? raw, int userId) => switch (raw) {
    {
      'packageName': final String package,
      'name': final String name,
      'system': final bool system,
      'userId': final int user,
      'taskId': final int task,
    }
        when _validPackage(package) && user == userId && task >= 0 =>
      DeviceApp(
        packageName: package,
        name: name,
        system: system,
        userId: user,
        taskId: task,
      ),
    _ => throw const RequestFailure(
      'apps_running_unavailable',
      '应用任务缺少当前用户的有效身份。',
    ),
  };
}
