import 'package:scrcpy_connect/media/cache/app_media_cache.dart';
import 'package:scrcpy_connect/media/cache/media_artifact_coordinator.dart';
import 'package:scrcpy_connect/files/documents/delivery_journal.dart';
import 'package:scrcpy_connect/files/execution/file_executor.dart';
import 'package:scrcpy_connect/files/catalog/file_catalog.dart';
import 'package:scrcpy_connect/files/mutations/file_mutation_coordinator.dart';
import 'package:scrcpy_connect/files/transfers/transfer_coordinator.dart';
import 'package:scrcpy_connect/application/transport/file_commands.dart';
import 'package:scrcpy_connect/files/sharing/share_coordinator.dart';
import 'package:scrcpy_connect/preferences/preference_store.dart';
import 'package:scrcpy_connect/application/transport/command_contract.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/media/quality/video_quality_policy.dart';
import 'package:scrcpy_connect/media/quality/virtual_display_policy.dart';

import 'package:scrcpy_connect/preferences/preference_commands.dart';

/// 应用命令的校验、产品偏好和文件流程；各业务所有者通过 Dart 接口执行。
final class ApplicationCommandDispatcher {
  ApplicationCommandDispatcher({
    required FileExecutor executor,
    required FileCatalog catalog,
    required FileMutationCoordinator mutations,
    required TransferCoordinator transfers,
    required PreferenceStore preferences,
    required this.execute,
    AppMediaCache? cache,
    DeliveryJournal? deliveries,
    ShareCoordinator? sharing,
    void Function(Map<String, dynamic>)? onMediaEvent,
    required void Function(Map<String, dynamic>) onSettingsChanged,
    required Future<void> Function(bool) applyBackgroundPolicy,
  }) : _catalog = catalog,
       _mutations = mutations,
       _transfers = transfers {
    _fileCommands = FileCommands(
      catalog: catalog,
      mutations: mutations,
      transfers: transfers,
    );
    _onMediaEvent = onMediaEvent;
    _cache = cache;
    _deliveries = deliveries;
    _sharing = sharing;
    _artifacts = cache == null
        ? null
        : MediaArtifactCoordinator(
            cache: cache,
            executor: executor,
            request: _request,
            emit: onMediaEvent,
          );
    _preferences = PreferenceCommands(
      preferences: preferences,
      request: _request,
      onChanged: onSettingsChanged,
      applyBackgroundPolicy: applyBackgroundPolicy,
    );
  }
  final FileCatalog _catalog;
  final FileMutationCoordinator _mutations;
  final TransferCoordinator _transfers;
  late final FileCommands _fileCommands;
  final Future<Map<String, dynamic>> Function(
    String command,
    Map<String, dynamic> params,
  )
  execute;
  late final PreferenceCommands _preferences;
  late final void Function(Map<String, dynamic>)? _onMediaEvent;
  late final AppMediaCache? _cache;
  late final DeliveryJournal? _deliveries;
  late final ShareCoordinator? _sharing;
  late final MediaArtifactCoordinator? _artifacts;
  Future<void> closeMediaArtifacts() async => _artifacts?.close();

  /// 连接所有者在撤销连接时调用，覆盖断开、换钥和连接配置替换。
  Future<void> cancelDeviceArtifacts(String deviceId) async =>
      _artifacts?.cancelDevice(deviceId);

  Map<String, dynamic> projectEvent(Map<String, dynamic> event) =>
      _preferences.projectEvent(event);

  Future<Map<String, dynamic>> invoke(
    String command,
    Map<String, dynamic> params,
  ) async {
    if (command == 'settings.update') {
      VideoQualityPolicy.validateSettings(params);
    } else if (command == 'settings.import') {
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
      if (command == 'activities.stop' &&
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
          if (command == 'sharing.pending') return {'shares': <Object?>[]};
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
        if (command == 'media.cache.configure' ||
            command == 'media.cache.clear') {
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
        'media.preview',
        'media.thumbnail',
        'media.thumbnail.cancel',
      ].contains(command)) {
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
      'session.start',
      'apps.launch',
      'session.quality',
    ].contains(command)) {
      final settings = await invoke('settings.get', const {});
      params = {
        ...params,
        ...VideoQualityPolicy.resolve(
          settings,
          params['deviceId'] as String?,
          command == 'session.quality' ? params : const {},
        ),
      }..remove('preset');
    }
    params = await VirtualDisplayPolicy.prepare(
      command,
      params,
      readSessions: (filter) => invoke('session.list', filter),
    );
    if (['devices.disconnect', 'devices.forget'].contains(command)) {
      await _artifacts?.cancelDevice(params['deviceId'] as String);
      final device = params['deviceId'] as String;
      await Future.wait([
        _catalog.cancelDevice(device),
        _mutations.cancelDevice(device),
        _transfers.cancelDevice(device),
      ]);
    }
    final response = await _request(command, params);
    if (command == 'devices.forget') {
      await _preferences.forgetDevicePreferences(params['deviceId'] as String);
    }
    final result = command == 'state.snapshot'
        ? _preferences.projectSnapshot(response)
        : response;
    if (command == 'session.quality') {
      await _preferences.saveDeviceQuality(
        params['deviceId'] as String,
        Map<String, dynamic>.from(result['current'] as Map),
      );
    }
    if (command == 'session.quality.options') {
      return VideoQualityPolicy.options(
        result,
        await invoke('settings.get', const {}),
        params['deviceId'] as String?,
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _request(
    String command,
    Map<String, dynamic> params,
  ) async {
    final contract = validateCommandRequest(command, params);
    final response = await execute(command, params);
    validateCommandResult(contract, response);
    return response;
  }
}
