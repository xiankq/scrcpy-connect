import 'package:adb/adb.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scrcpy_connect/application/transport/commands_generated.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/application/events/application_snapshot_reader.dart';
import 'package:scrcpy_connect/connection/device_coordinator.dart';
import 'package:scrcpy_connect/connection/device_power_coordinator.dart';
import 'package:scrcpy_connect/connection/records/device_record.dart'
    show validDeviceId;
import 'package:scrcpy_connect/connection/records/device_record_store.dart';
import 'package:scrcpy_connect/connection/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/companion/companion_client.dart';
import 'package:scrcpy_connect/companion/companion_coordinator.dart';
import 'package:scrcpy_connect/companion/observation_coordinator.dart';
import 'package:scrcpy_connect/companion/media_job_coordinator.dart';
import 'package:scrcpy_connect/media/capture/device_audio_source_coordinator.dart';
import 'package:scrcpy_connect/media/capture/media_capture_operations.dart';

/// 借用已组装的业务所有者执行命令，不创建资源、不回调应用会话。
final class ApplicationBusinessCommands {
  ApplicationBusinessCommands({
    required this._records,
    required this._devices,
    required this._power,
    required this._audio,
    required this._captures,
    required this._mediaJobs,
    required this._observations,
    required this._companion,
    required this._serverQueries,
    required this._state,
    required this._publish,
    required this._isDisposed,
  });

  final DeviceRecordStore _records;
  final DeviceCoordinator _devices;
  final DevicePowerCoordinator _power;
  final DeviceAudioSourceCoordinator _audio;
  final MediaCaptureOperations _captures;
  final MediaJobCoordinator _mediaJobs;
  final ObservationCoordinator _observations;
  final CompanionCoordinator _companion;
  final ScrcpyServerQueries _serverQueries;
  final ApplicationSnapshotReader _state;
  final void Function(Map<String, dynamic>) _publish;
  final bool Function() _isDisposed;
  bool get _disposed => _isDisposed();

  Future<Map<String, dynamic>> execute(
    ApplicationCommand command,
    Map<String, dynamic> params,
  ) => _execute(command, params);

  Future<Map<String, dynamic>> _execute(
    ApplicationCommand operation,
    Map<String, dynamic> params,
  ) async {
    final command = operation.wire;
    try {
      if (operation == ApplicationCommand.systemInfo) {
        // 读取实际安装包元数据，沿用构建时版本，不在 Rust 或 Dart 另存一份版本号。
        final PackageInfo info;
        try {
          info = await PackageInfo.fromPlatform();
        } on PlatformException catch (error, stack) {
          Error.throwWithStackTrace(
            ApplicationCommandException(
              'application_info_unavailable',
              '无法读取当前安装包信息，请重新启动应用后重试。',
              {'platformCode': error.code},
            ),
            stack,
          );
        } on MissingPluginException catch (_, stack) {
          Error.throwWithStackTrace(
            const ApplicationCommandException(
              'application_info_unavailable',
              '当前宿主尚未提供安装包信息，请重新启动应用后重试。',
            ),
            stack,
          );
        }
        if (_disposed) {
          throw const ApplicationCommandException('disposed', '应用会话已关闭。');
        }
        if (info.version.isEmpty) {
          throw const ApplicationCommandException(
            'application_info_unavailable',
            '当前安装包没有可核实的版本信息。',
          );
        }
        return {
          'appName': info.appName,
          'packageName': info.packageName,
          'version': info.version,
          'buildNumber': info.buildNumber,
        };
      }
      if (operation == ApplicationCommand.stateSnapshot) {
        return await _state.readSnapshot();
      }
      if (operation == ApplicationCommand.activitiesList) {
        final snapshot = await _state.readSnapshot();
        return {
          'activities': snapshot['activities'],
          'sessions': snapshot['sessions'],
        };
      }
      if (operation == ApplicationCommand.activitiesStop) {
        return await _stopActivity(params);
      }
      // 偏好导入只追加未授权元数据，不重建密钥、连接或另一份执行配置。
      if (operation == ApplicationCommand.settingsExport) {
        return Map.from(_records.exportMetadata());
      }
      if (operation == ApplicationCommand.settingsImport) {
        final imported = await _records.importMetadata(params['metadata']);
        _publish({'type': 'devices.changed', 'data': imported.toJson()});
        return Map.from(imported.toJson());
      }
      if (_power.handles(command)) {
        return Map.from(await _power.command(command, params));
      }
      if (_devices.handles(command)) {
        final result = await _devices.command(command, params);
        if (operation == ApplicationCommand.devicesForget) {
          await _observations.forget(_deviceId(params));
        }
        return Map.from(result);
      }
      if (_captures.handles(operation)) {
        return await _captures.execute(operation, params);
      }
      if (_mediaJobs.handles(command)) {
        return Map.from(await _mediaJobs.command(command, params));
      }
      if (_observations.handles(command)) {
        return Map.from(await _observations.command(command, params));
      }
      if (operation == ApplicationCommand.appsList &&
          (params['filter'] ?? 'installed') == 'installed') {
        final id = _deviceId(params);
        final connection = _devices.requireConnection(id);
        final result = await _serverQueries.installedApps(
          connection,
          AdbCancellation(),
        );
        if (!identical(_devices.current(id), connection)) {
          throw const ApplicationCommandException(
            'cancelled',
            '设备连接已改变，安装清单不再适用。',
          );
        }
        return {'apps': result};
      }
      if (_companion.handles(command)) {
        return Map.from(await _companion.command(command, params));
      }
      throw ApplicationCommandException(
        'unknown_command',
        '应用尚未提供此操作：$command',
      );
    } on DeviceRecordsFailure catch (error, stack) {
      Error.throwWithStackTrace(
        ApplicationCommandException(error.code, error.message, error.details),
        stack,
      );
    } on CompanionException catch (error, stack) {
      Error.throwWithStackTrace(
        ApplicationCommandException(error.code, error.message),
        stack,
      );
    } on AdbException catch (error, stack) {
      Error.throwWithStackTrace(
        ApplicationCommandException(error.code, error.message),
        stack,
      );
    }
  }

  String _deviceId(Map<String, dynamic> params) {
    final id = params['deviceId'];
    if (id is! String || !validDeviceId(id)) {
      throw const ApplicationCommandException('invalid_device_id', '设备标识无效。');
    }
    return id;
  }

  Future<Map<String, dynamic>> _stopActivity(
    Map<String, dynamic> params,
  ) async {
    final id = params['activityId'];
    if (id is! String) {
      throw const ApplicationCommandException('invalid_argument', '活动标识无效。');
    }
    final separator = id.indexOf(':');
    if (separator < 1 || separator == id.length - 1) {
      throw const ApplicationCommandException('not_found', '此活动已结束或标识无效。');
    }
    final target = id.substring(separator + 1);
    switch (id.substring(0, separator)) {
      case 'connection':
        return _execute(ApplicationCommand.devicesDisconnect, {
          'deviceId': target,
        });
      case 'session':
        return _execute(ApplicationCommand.sessionStop, {'sessionId': target});
      case 'observation':
        return _execute(ApplicationCommand.observationStop, {
          'deviceId': target,
        });
      case 'audio':
        final source = _audio
            .snapshots()
            .where((source) => source['sourceId'] == target)
            .firstOrNull;
        if (source == null) {
          throw const ApplicationCommandException('not_found', '这代音源已结束。');
        }
        return _execute(ApplicationCommand.audioStop, {
          'deviceId': source['deviceId'],
          'sourceId': target,
        });
      default:
        throw const ApplicationCommandException('not_found', '此活动已结束或标识无效。');
    }
  }
}
