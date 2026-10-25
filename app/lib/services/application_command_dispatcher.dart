import 'package:scrcpy_connect/stores/media/app_media_cache.dart';
import 'package:scrcpy_connect/stores/media/media_artifact_coordinator.dart';
import 'package:scrcpy_connect/stores/files/delivery_journal.dart';
import 'package:scrcpy_connect/services/files/file_executor.dart'
    show FileFailure;
import 'package:scrcpy_connect/stores/files/file_catalog.dart';
import 'package:scrcpy_connect/stores/files/file_mutation_coordinator.dart';
import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';
import 'package:scrcpy_connect/services/file_commands.dart';
import 'package:scrcpy_connect/stores/files/share_coordinator.dart';
import 'package:scrcpy_connect/services/command_contract.dart';
import 'package:scrcpy_connect/models/generated/commands_generated.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/services/media/video_quality_policy.dart';
import 'package:scrcpy_connect/services/media/virtual_display_policy.dart';

import 'package:scrcpy_connect/services/preference_commands.dart';

/// 应用命令的校验、产品偏好和文件流程；各业务所有者通过 Dart 接口执行。
final class ApplicationCommandDispatcher {
  ApplicationCommandDispatcher({
    required FileCatalog catalog,
    required FileMutationCoordinator mutations,
    required TransferCoordinator transfers,
    required this._preferences,
    required this.execute,
    this._cache,
    this._deliveries,
    this._sharing,
    this._artifacts,
    this._onMediaEvent,
  }) : _catalog = catalog,
       _mutations = mutations,
       _transfers = transfers,
       _fileCommands = FileCommands(
         catalog: catalog,
         mutations: mutations,
         transfers: transfers,
       );

  final FileCatalog _catalog;
  final FileMutationCoordinator _mutations;
  final TransferCoordinator _transfers;
  final FileCommands _fileCommands;
  final Future<Map<String, dynamic>> Function(
    ApplicationCommand command,
    Map<String, dynamic> params,
  )
  execute;
  final PreferenceCommands _preferences;
  final void Function(Map<String, dynamic>)? _onMediaEvent;
  final AppMediaCache? _cache;
  final DeliveryJournal? _deliveries;
  final ShareCoordinator? _sharing;
  final MediaArtifactCoordinator? _artifacts;

  Map<String, dynamic> projectEvent(Map<String, dynamic> event) =>
      _preferences.projectEvent(event);

  Future<Map<String, dynamic>> invoke(
    String command,
    Map<String, dynamic> params,
  ) async => invokeCommand(validateCommandRequest(command, params), params);

  Future<Map<String, dynamic>> invokeCommand(
    ApplicationCommand command,
    Map<String, dynamic> params,
  ) async {
    validateTypedCommandRequest(command, params);
    final response = await _invoke(command, params);
    validateCommandResult(command, response);
    return response;
  }

  Future<Map<String, dynamic>> _invoke(
    ApplicationCommand operation,
    Map<String, dynamic> params,
  ) async {
    final command = operation.wire;
    if (operation == ApplicationCommand.settingsUpdate) {
      VideoQualityPolicy.validateSettings(params);
    } else if (operation == ApplicationCommand.settingsImport) {
      final metadata = params['metadata'];
      final settings = metadata is Map ? metadata['settings'] : null;
      if (settings is Map) {
        VideoQualityPolicy.validateSettings(
          Map<String, dynamic>.from(settings),
        );
      }
    }
    if (_preferences.handles(command)) {
      return Map<String, dynamic>.from(
        await _preferences.invoke(command, params) as Map,
      );
    }
    try {
      if (operation == ApplicationCommand.activitiesStop &&
          params['activityId'] is String &&
          (params['activityId'] as String).startsWith('transfer:')) {
        return Map<String, dynamic>.from(
          await _transfers.cancelTransfer(
            (params['activityId'] as String).substring('transfer:'.length),
          ),
        );
      }
      final local = await _fileCommands.invoke(command, params);
      if (local != null) return Map<String, dynamic>.from(local);
      if (command.startsWith('sharing.')) {
        final sharing = _sharing;
        if (sharing == null) {
          if (operation == ApplicationCommand.sharingPending) {
            return {'shares': <Object?>[]};
          }
          throw const ApplicationCommandException(
            'platform_unavailable',
            '此宿主不支持接收系统分享。',
          );
        }
        return await sharing.command(command, params);
      }
      if (command.startsWith('media.cache.')) {
        if (_cache == null) {
          throw const ApplicationCommandException(
            'cache_not_configured',
            '应用缓存尚未配置。',
          );
        }
        final result = Map<String, dynamic>.from(
          await _cache.command(command, params),
        );
        if (operation == ApplicationCommand.mediaCacheConfigure ||
            operation == ApplicationCommand.mediaCacheClear) {
          _onMediaEvent?.call({'type': 'media.cache.changed', 'data': result});
        }
        return result;
      }
      if (command.startsWith('delivery.')) {
        if (_deliveries == null) {
          throw const ApplicationCommandException(
            'delivery_not_configured',
            '保存日志尚未配置。',
          );
        }
        return await _deliveries.command(command, params);
      }
      if (const [
        ApplicationCommand.mediaPreview,
        ApplicationCommand.mediaThumbnail,
        ApplicationCommand.mediaThumbnailCancel,
      ].contains(operation)) {
        if (_artifacts == null) {
          throw const ApplicationCommandException(
            'cache_not_configured',
            '应用媒体缓存尚未配置。',
          );
        }
        return await _artifacts.invoke(command, params);
      }
    } on MediaCacheFailure catch (error) {
      throw ApplicationCommandException(error.code, error.message);
    } on FileFailure catch (error) {
      throw ApplicationCommandException(error.code, error.message);
    }
    if (const [
      ApplicationCommand.sessionStart,
      ApplicationCommand.appsLaunch,
      ApplicationCommand.sessionQuality,
    ].contains(operation)) {
      final settings = await invokeCommand(
        ApplicationCommand.settingsGet,
        const {},
      );
      params = {
        ...params,
        ...VideoQualityPolicy.resolve(
          settings,
          params['deviceId'] as String?,
          operation == ApplicationCommand.sessionQuality ? params : const {},
        ),
      }..remove('preset');
    }
    params = await VirtualDisplayPolicy.prepare(
      command,
      params,
      readSessions: (filter) =>
          invokeCommand(ApplicationCommand.sessionList, filter),
    );
    if ([
      ApplicationCommand.devicesDisconnect,
      ApplicationCommand.devicesForget,
    ].contains(operation)) {
      await _artifacts?.cancelDevice(params['deviceId'] as String);
      final device = params['deviceId'] as String;
      await Future.wait([
        _catalog.cancelDevice(device),
        _mutations.cancelDevice(device),
        _transfers.cancelDevice(device),
      ]);
    }
    final response = await _request(operation, params);
    if (operation == ApplicationCommand.devicesForget) {
      await _preferences.forgetDevicePreferences(params['deviceId'] as String);
    }
    final result = operation == ApplicationCommand.stateSnapshot
        ? _preferences.projectSnapshot(response)
        : response;
    if (operation == ApplicationCommand.sessionQuality) {
      await _preferences.saveDeviceQuality(
        params['deviceId'] as String,
        Map<String, dynamic>.from(result['current'] as Map),
      );
    }
    if (operation == ApplicationCommand.sessionQualityOptions) {
      return VideoQualityPolicy.options(
        result,
        await invokeCommand(ApplicationCommand.settingsGet, const {}),
        params['deviceId'] as String?,
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _request(
    ApplicationCommand command,
    Map<String, dynamic> params,
  ) async {
    validateTypedCommandRequest(command, params);
    final response = await execute(command, params);
    validateCommandResult(command, response);
    return response;
  }
}
