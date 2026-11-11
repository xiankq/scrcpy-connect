import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/services/file_paths.dart';
import 'package:scrcpy_connect/models/file_stamp.dart';

import 'package:scrcpy_connect/models/media_cache_failure.dart';
import 'package:scrcpy_connect/models/file_failure.dart';
import 'package:scrcpy_connect/services/media_cache_service.dart';
import 'package:scrcpy_connect/services/media_preview_service.dart';
import 'package:scrcpy_connect/services/file_delivery_journal.dart';

import 'package:scrcpy_connect/services/file_catalog.dart';
import 'package:scrcpy_connect/services/file_mutation_service.dart';
import 'package:scrcpy_connect/services/file_transfer_service.dart';
import 'package:scrcpy_connect/services/file_share_service.dart';
import 'package:scrcpy_connect/services/command_contract.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/video_quality_policy.dart';
import 'package:scrcpy_connect/services/virtual_display_policy.dart';

import 'package:scrcpy_connect/services/app_settings.dart';

/// 应用命令的校验、产品偏好和文件流程；各业务所有者通过 Dart 接口执行。
final class ApplicationCommandDispatcher {
  ApplicationCommandDispatcher({
    required this._catalog,
    required this._mutations,
    required this._transfers,
    required this._preferences,
    required this.execute,
    this._cache,
    this._deliveries,
    this._sharing,
    this._artifacts,
    this._onMediaEvent,
  });

  final FileCatalog _catalog;
  final FileMutationService _mutations;
  final FileTransferService _transfers;
  final Future<Map<String, dynamic>> Function(
    ApplicationCommand command,
    Map<String, dynamic> params,
  )
  execute;
  final AppSettings _preferences;
  final void Function(Map<String, dynamic>)? _onMediaEvent;
  final MediaCacheService? _cache;
  final FileDeliveryJournal? _deliveries;
  final FileShareService? _sharing;
  final MediaPreviewService? _artifacts;

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
    switch (operation) {
      case ApplicationCommand.settingsGet:
        return _preferences.read();
      case ApplicationCommand.settingsUpdate:
        return _preferences.update(params);
      case ApplicationCommand.settingsExport:
        return _preferences.exportMetadata();
      case ApplicationCommand.settingsImportPreview:
        return _preferences.previewImport(params);
      case ApplicationCommand.settingsImport:
        return _preferences.importMetadata(params);
      default:
        break;
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
      final local = await _executeFiles(command, params);
      if (local != null) return Map<String, dynamic>.from(local);
      if (command.startsWith('sharing.')) {
        final sharing = _sharing;
        if (sharing == null) {
          if (operation == ApplicationCommand.sharingPending) {
            return {'shares': <Object?>[]};
          }
          throw const RequestFailure('platform_unavailable', '此宿主不支持接收系统分享。');
        }
        return await sharing.command(command, params);
      }
      if (command.startsWith('media.cache.')) {
        if (_cache == null) {
          throw const RequestFailure('cache_not_configured', '应用缓存尚未配置。');
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
          throw const RequestFailure('delivery_not_configured', '保存日志尚未配置。');
        }
        return await _deliveries.command(command, params);
      }
      if (const [
        ApplicationCommand.mediaPreview,
        ApplicationCommand.mediaThumbnail,
        ApplicationCommand.mediaThumbnailCancel,
      ].contains(operation)) {
        if (_artifacts == null) {
          throw const RequestFailure('cache_not_configured', '应用媒体缓存尚未配置。');
        }
        return await _artifacts.invoke(command, params);
      }
    } on MediaCacheFailure catch (error) {
      throw RequestFailure(error.code, error.message);
    } on FileFailure catch (error) {
      throw RequestFailure(error.code, error.message);
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
    final response = await execute(operation, params);
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

  Future<Map<String, Object?>?> _executeFiles(
    String command,
    Map<String, Object?> params,
  ) async {
    String device() => switch (params['deviceId']) {
      final String value => value,
      null => '',
      _ => throw const FileFailure('invalid_argument', '设备标识必须为字符串。'),
    };
    FileStamp stamp(Object? value) {
      if (value is! Map) {
        throw const FileFailure('source_changed', '缺少所选文件快照，请重新选择。');
      }
      try {
        final result = FileStamp.fromJson(Map<String, Object?>.from(value));
        if (result.identity == null || result.identity!.isEmpty) {
          throw const FileFailure('source_changed', '缺少所选文件身份，请重新选择。');
        }
        return result;
      } on TypeError {
        throw const FileFailure('invalid_argument', '所选文件快照无效。');
      } on FormatException {
        throw const FileFailure('invalid_argument', '所选文件快照无效。');
      }
    }

    switch (command) {
      case 'media.cache.acquire':
        return {
          'leaseId': await _transfers.acquireCacheLease(
            params['transferId']! as String,
          ),
        };
      case 'files.list':
        return _catalog.browse(
          device(),
          params['path'] as String? ?? '/sdcard',
          filter: params['filter'] as String? ?? 'all',
          sort: params['sort'] as String? ?? 'name',
          descending: params['descending'] == true,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 10000,
        );
      case 'files.search.start':
        return _catalog.startSearch(
          device(),
          params['path']! as String,
          query: params['query']! as String,
          filter: params['filter'] as String? ?? 'all',
        );
      case 'files.search.get':
        return _catalog.scan(
          device(),
          params['searchId']! as String,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 500,
        );
      case 'files.search.cancel':
        return _catalog.cancelScan(device(), params['searchId']! as String);
      case 'media.list':
        final id = params['scanId'] as String?;
        if (id == null || params['refresh'] == true) {
          return _catalog.startSearch(
            device(),
            '/sdcard',
            query: '',
            gallery: true,
          );
        }
        return _catalog.scan(
          device(),
          id,
          offset: params['offset'] as int? ?? 0,
          limit: params['limit'] as int? ?? 100,
        );
      case 'media.scan.cancel':
        return _catalog.cancelScan(device(), params['scanId']! as String);
      case 'files.push':
      case 'files.pull':
        final selections = (params['items'] as List? ?? [params]).map((item) {
          final selection = Map<String, Object?>.from(item as Map);
          selection['source'] ??= selection['path'];
          return selection;
        }).toList();
        final policy =
            params['conflict'] as String? ??
            params['policy'] as String? ??
            'ask';
        final scope = params['destinationScope'] as String? ?? 'localPath';
        final share = params['shareId'] as String?;
        if (command == 'files.push' && share != null) {
          return _transfers.submitShare(
            device(),
            selections,
            shareId: share,
            publicationRequest: params,
            policy: policy,
            destinationScope: scope,
          );
        }
        return _transfers.startTransfer(
          device(),
          command == 'files.push',
          selections,
          policy: policy,
          destinationScope: scope,
          shareId: share,
        );
      case 'sharing.reconcile':
        if (_transfers.publication != null && params['transfers'] == null) {
          return _transfers.reconcileShares();
        }
        return null;
      case 'transfers.list':
        return _transfers.transfers();
      case 'transfers.get':
        return _transfers.transfer(params['transferId']! as String);
      case 'transfers.cancel':
        if (params['batchId'] is String) {
          return _transfers.cancelBatch(params['batchId']! as String);
        }
        return _transfers.cancelTransfer(params['transferId']! as String);
      case 'transfers.resolve':
      case 'transfers.resume':
        final id = params['transferId']! as String;
        return _transfers.resolveTransfer(
          id,
          params['policy'] as String? ??
              params['conflict'] as String? ??
              (_transfers.transfer(id)['policy'] as String? ?? 'ask'),
          restart: params['restart'] == true,
          applyToAll: params['applyToAll'] == true,
        );
      case 'transfers.remove':
        return _transfers.removeTransfer(
          (params['batchId'] ?? params['transferId'])! as String,
          batch: params['batchId'] is String,
        );
      case 'files.mkdir':
        await _mutations.createDirectory(device(), params['path']! as String);
        return {'ok': true};
      case 'files.rename':
        final path = params['path']! as String;
        await _mutations.rename(
          device(),
          path,
          expected: stamp(params['expectedStamp']),
          destination:
              params['destination'] as String? ??
              params['newPath'] as String? ??
              (params['name'] is String
                  ? p.posix.join(
                      p.posix.dirname(path),
                      FilePaths.name(params['name']! as String),
                    )
                  : ''),
        );
        return {'ok': true};
      case 'files.delete':
        await _mutations.delete(
          device(),
          (params['paths']! as List).cast<String>(),
          expected: {
            for (final path in (params['paths']! as List).cast<String>())
              path: stamp((params['expectedStamps'] as Map?)?[path]),
          },
        );
        return {'ok': true};
      default:
        return null;
    }
  }
}
