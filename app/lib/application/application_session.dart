library;

import 'package:scrcpy_connect/media/cache/app_media_cache.dart';
import 'package:scrcpy_connect/files/documents/delivery_journal.dart';

import 'package:scrcpy/scrcpy.dart' show createNativeScrcpyLocalFiles;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:scrcpy_connect/platform/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/platform/diagnostics/diagnostic_reporter.dart';

import 'package:scrcpy_connect/media/capture/media_intent_registry.dart';
import 'package:scrcpy_connect/media/capture/scrcpy_capture_adapter.dart';

import 'package:scrcpy_connect/media/media_coordinator.dart';
import 'package:scrcpy_connect/application/events/state_recovery.dart';

import 'package:scrcpy_connect/files/transfers/transfer_coordinator.dart';
import 'package:scrcpy_connect/files/catalog/file_catalog.dart';
import 'package:scrcpy_connect/files/mutations/file_mutation_coordinator.dart';
import 'package:scrcpy_connect/files/sharing/share_coordinator.dart';
import 'package:scrcpy_connect/application/transport/commands_generated.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

import 'package:scrcpy_connect/application/lifecycle/ordered_disposal.dart';
import 'package:scrcpy_connect/application/lifecycle/application_host.dart';
import 'package:scrcpy_connect/application/application_command_dispatcher.dart';
import 'package:scrcpy_connect/platform/application_platform.dart';
import 'package:scrcpy_connect/platform/application_background_coordinator.dart';
import 'package:scrcpy_connect/application/events/application_platform_events.dart';
import 'package:scrcpy_connect/application/events/application_events.dart';
import 'package:scrcpy_connect/application/lifecycle/application_lifecycle.dart';
import 'package:scrcpy_connect/files/execution/adb_file_executor.dart';

import 'package:scrcpy_connect/connection/connection_policy.dart';
import 'package:scrcpy_connect/connection/connection_setup_coordinator.dart';
import 'package:scrcpy_connect/connection/device_capability_policy.dart';
import 'package:scrcpy_connect/connection/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/connection/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/connection/reconnection_coordinator.dart';

import 'package:scrcpy_connect/connection/connection_owner.dart';
import 'package:scrcpy_connect/connection/device_coordinator.dart';
import 'package:scrcpy_connect/connection/device_health_coordinator.dart';
import 'package:scrcpy_connect/connection/device_power_coordinator.dart';
import 'package:scrcpy_connect/connection/device_discovery.dart';
import 'package:scrcpy_connect/connection/identity_manager.dart';
import 'package:scrcpy_connect/connection/records/device_record_store.dart';
import 'package:scrcpy_connect/connection/records/device_record.dart'
    show validDeviceId;
import 'package:scrcpy_connect/application/events/application_snapshot_reader.dart';
import 'package:scrcpy_connect/connection/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/companion/companion_client.dart';
import 'package:scrcpy_connect/companion/companion_coordinator.dart';
import 'package:scrcpy_connect/companion/observation_coordinator.dart';
import 'package:scrcpy_connect/companion/media_job_coordinator.dart';
import 'package:scrcpy_connect/media/capture/app_launch_store.dart';
import 'package:scrcpy_connect/media/capture/session_coordinator.dart';
import 'package:scrcpy_connect/media/capture/device_audio_source_coordinator.dart';
import 'package:scrcpy_connect/media/capture/device_keep_awake_coordinator.dart';

/// 按应用生命周期组装独立设备能力；ADB 传输与媒体解码由各自的包负责。
class ApplicationSession {
  ApplicationSession._(
    this._dataDirectory,
    this._connectionPolicy,
    this._host,
    this._records,
    this._identities,
    this._launches,
    this._defaultClient,
    this.diagnostics,
    this._transfers,
    this._fileExecutor,
    this._cache,
    this._deliveries,
    this._sharing,
  );

  final ApplicationHost _host;
  final DeviceRecordStore _records;
  final IdentityManager _identities;
  final AppLaunchStore _launches;
  final AdbClient _defaultClient;
  final TransferCoordinator _transfers;
  final AdbFileExecutor _fileExecutor;
  late final _fileCatalog = FileCatalog(_fileExecutor);
  late final _fileMutations = FileMutationCoordinator(_fileExecutor);
  final AppMediaCache _cache;
  final DeliveryJournal _deliveries;
  final ShareCoordinator? _sharing;

  final DiagnosticLog? diagnostics;
  Future<AdbClient> get adb => Future.value(_defaultClient);
  late final _diagnostics = DiagnosticReporter(diagnostics);
  late final ApplicationCommandDispatcher _commands =
      ApplicationCommandDispatcher(
        executor: _fileExecutor,
        catalog: _fileCatalog,
        mutations: _fileMutations,
        transfers: _transfers,
        preferences: _host.preferences,
        cache: _cache,
        deliveries: _deliveries,
        sharing: _sharing,
        onMediaEvent: (event) => _events.emit(event),
        execute: _dispatchBusiness,
        applyBackgroundPolicy: (enabled) async {
          await _background.apply(enabled, automatic: false);
        },
        onSettingsChanged: (settings) {
          if (_disposed) return;
          _reconnections.updateSettings(settings);
          final event = {'type': 'settings.changed', 'data': settings};
          _events.publish(event);
          _observeCleanup(
            _keepAwake.settingsChanged(
              _records.current.devices.map((record) => record.id),
            ),
          );
        },
      );

  final ConnectionPolicy _connectionPolicy;
  late final _reconnections = ReconnectionCoordinator(
    request: _commands.invoke,
    policy: _connectionPolicy,
  );
  late final _discovery = DeviceDiscovery(
    timeout: _connectionPolicy.discoveryTimeout,
  );
  late final _setup = ConnectionSetupCoordinator(
    devices: _devices,
    discovery: _discovery,
    burstMode: () => _host.preferences.current.values['adbBurstMode'] == true,
    clientForIdentity: (identity) => _host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    releaseIdentityClient: (identity) => _host.releaseIdentityClient(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    policy: _connectionPolicy,
    emit: (event) {
      _events.emit(event);
    },
    authorizeUsb: Platform.isAndroid ? _platform.authorizeUsb : null,
    cancelUsb: Platform.isAndroid ? _platform.cancelUsb : null,
    releaseUsb: Platform.isAndroid ? _platform.releaseUsb : null,
    holdDevice: (id) =>
        _reconnections.beforeRequest('devices.connect', {'deviceId': id}),
  );
  late final _capabilities = DeviceCapabilityPolicy(
    facts: DeviceCapabilityFactsReader(
      records: _records,
      identities: _identities,
      connectionForDevice: _devices.current,
      policy: _connectionPolicy,
      companionState: _companion.capabilityState,
      sessions: _sessions.currentSnapshots,
      audioSources: () => _audio.snapshots(activeOnly: true),
    ),
    burstRequested: () =>
        _host.preferences.current.values['adbBurstMode'] == true,
    localVideoCapabilities: _media.capabilities,
  );

  final String _dataDirectory;

  late final ApplicationBackgroundCoordinator _background =
      ApplicationBackgroundCoordinator(
        request: Platform.isAndroid ? _platform.request : null,
        audioPolicy: (enabled) async {
          await _media.policy(enabled);
        },
        emit: (event) {
          _events.emit(event);
        },
      );

  late final ApplicationPlatform _platform = ApplicationPlatform(
    usbOwnerLeaseId: _host.usbOwnerLeaseId,
    localFiles: createNativeScrcpyLocalFiles,
    sharing: _sharing,
    applicationRequest: _commands.invoke,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => _disposed,
  );
  late final _platformEvents = ApplicationPlatformEvents(
    reconnections: _reconnections,
    isDisposed: () => _disposed,
    stopConnections: () =>
        Future.wait([_setup.stopPending(), _devices.stopConnections()]),
    emit: (event) => _events.emit(event),
    handleShare: _platform.handleShare,
    handleMedia: _media.handlePlatformEvent,
  );
  late final ApplicationEvents _events = ApplicationEvents(
    acceptState: (event) => _stateRecovery.accept(event),
    onState: (event) => _diagnostics.applicationEvent(event),
    onLocalStateChanged: () => _stateRecovery.noteLocalStateChange(),
    beforePublish: _handleBusinessEvent,
    afterState: (event) => _media.handleApplicationEvent(event),
    handlePlatform: (event) => _platformEvents.handle(event),
    isDisposed: () => _disposed,
  );
  late final _lifecycle = ApplicationLifecycle(
    isDisposed: () => _disposed,
    setConnectionsVisible: (visible) => _reconnections.setVisible(visible),
    setMediaVisible: (visible) => _media.setVisible(visible),
    shutdown: shutdown,
  );
  bool _disposed = false;
  Future<void>? _shuttingDown;
  late final MediaCoordinator _media = MediaCoordinator(
    invoke: _commands.invoke,
    platform: _platform.audioRequest,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => _disposed,
    dataDirectory: _dataDirectory,
    capture: ScrcpyCaptureAdapter(_host.scrcpy.api),
    diagnostics: diagnostics,
  );
  late final StateRecovery _stateRecovery = StateRecovery(
    read: _media.snapshot,
    emit: (event) {
      // 恢复回执不是业务变更；直接通知策略，不能重新进入序列核验。
      _setup.handleEvent(event);
      _reconnections.handleEvent(event);
      _events.emit(event);
    },
    isDisposed: () => _disposed,
  );
  late final DeviceCoordinator _devices = DeviceCoordinator(
    records: _records,
    identities: _identities,
    reconnectionCandidates: MdnsDeviceReconnectionCandidates(_discovery),
    clientForIdentity: (identity) => _host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    stopActivities: _stopConnectionActivities,
    prepareConnection: (connection, cancellation) =>
        _host.physicalDisplays.recover(connection, cancellation: cancellation),
    onConnected: (id, connection) => _health.start(id, connection),
    policy: _connectionPolicy,
    burstMode: () => _host.preferences.current.values['adbBurstMode'] == true,
    emit: (type, data) => _publishBusiness(type, null, data),
  );
  late final DeviceHealthCoordinator _health = DeviceHealthCoordinator(
    current: _devices.current,
    retire: _devices.retireUnhealthy,
    policy: _connectionPolicy,
    onError: (error, stack) => diagnostics?.record(
      DiagnosticArea.connection,
      'health.check.failed',
      level: LogLevel.error,
      fields: {'errorType': error.runtimeType.toString()},
    ),
  );
  late final DevicePowerCoordinator _power = DevicePowerCoordinator(
    requireConnection: _devices.requireConnection,
    timeout: _connectionPolicy.probeTimeout,
  );
  late final ScrcpyServerQueries _serverQueries = ScrcpyServerQueries(
    serverBytes: _host.scrcpyBytes,
    timeout: const Duration(seconds: 15),
  );
  late final SessionCoordinator _sessions = SessionCoordinator(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    launches: _launches,
    serverQueries: _serverQueries,
    settings: () => _host.preferences.current.toMap(),
    emit: _publishBusiness,
    onAudioEligibilityChanged: (id) {
      // 同步撤准入后记录实际排空，回调不等待其他设备，也不丢弃失败所有者。
      _observeCleanup(_audio.eligibilityChanged(id));
      _observeCleanup(_keepAwake.windowsChanged(id));
    },
  );
  late final DeviceAudioSourceCoordinator _audio = DeviceAudioSourceCoordinator(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    hasAudioOwner: _sessions.hasAudioOwner,
    deviceName: (id) => _records.current.find(id)?.name ?? 'Android 设备',
    apiLevel: (id) => _records.current.find(id)?.apiLevel,
    emit: _publishBusiness,
  );
  late final DeviceKeepAwakeCoordinator _keepAwake = DeviceKeepAwakeCoordinator(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    hasWindowOwner: _sessions.hasAudioOwner,
    settings: () => _host.preferences.current.toMap(),
    emit: _publishBusiness,
  );
  late final CompanionCoordinator _companion = CompanionCoordinator(
    requireConnection: _devices.requireConnection,
    serverBytes: _host.companionBytes,
    config: const CompanionConfig(
      startupTimeout: Duration(seconds: 15),
      requestTimeout: Duration(seconds: 10),
      cleanupTimeout: Duration(seconds: 5),
      sessionTimeout: Duration(hours: 24),
    ),
    emit: _publishBusiness,
  );
  late final ObservationCoordinator _observations = ObservationCoordinator(
    companion: _companion,
    records: _records,
    emit: _publishBusiness,
  );
  late final MediaJobCoordinator _mediaJobs = MediaJobCoordinator(
    requireConnection: _devices.requireConnection,
    request: _companion.request,
  );
  final _businessTasks = <Future<void>>{};
  final _observedConnections = <String, DeviceConnection>{};
  // 当前连接投影可先消失；设备级任务的退休责任保留到精确旧连接排空。
  final _deviceTaskConnections = <DeviceConnection>{};

  void _observeCleanup(Future<void> work) {
    _businessTasks.add(work);
    unawaited(
      work.then<void>(
        (_) {
          _businessTasks.remove(work);
        },
        onError: (Object error, StackTrace stack) {
          _businessTasks.remove(work);
          _events.emit({
            'type': 'activity.cleanup.failed',
            'data': {'reason': '$error'},
          });
        },
      ),
    );
  }

  void _publishBusiness(
    String type,
    String? device,
    Map<String, Object?> data,
  ) {
    _events.publish({
      'type': type,
      'deviceId': ?device,
      'data':
          type.startsWith('session.') &&
              type != 'session.frame' &&
              data['sessionId'] is String
          ? _state.projectSession(data)
          : data,
    });
    if (type == 'device.keep_active.updated' && device != null) {
      _publishKeepAwake(device);
    }
  }

  void _publishKeepAwake(String device) {
    for (final session in _sessions.currentSnapshots(deviceId: device)) {
      _publishBusiness('session.updated', device, session);
    }
  }

  void _handleBusinessEvent(Map<String, dynamic> event) {
    _setup.handleEvent(event);
    _reconnections.handleEvent(event);
    if (event['type'] == 'devices.changed') {
      final ids = {
        ..._observedConnections.keys,
        ..._records.current.devices.map((record) => record.id),
      };
      for (final id in ids) {
        final connection = _devices.current(id);
        if (identical(_observedConnections[id], connection)) continue;
        if (connection == null) {
          _observedConnections.remove(id);
        } else {
          _observedConnections[id] = connection;
          _deviceTaskConnections.add(connection);
        }
        _observeCleanup(_observations.connectionChanged(id));
      }
    }
  }

  Future<void> _stopConnectionActivities(
    String id,
    DeviceConnection connection,
  ) async {
    // 各调用先同步撤销自己创建的资源；所有步骤均运行并保留精确失败供下一轮重试。
    final stops = [
      _health.stopConnection(id, connection),
      _power.stopConnection(id, connection),
      _sessions.stopForConnection(id, connection),
      _audio.stopForConnection(id, connection),
      _keepAwake.stopForConnection(id, connection),
      _serverQueries.stopForConnection(connection),
      // 未获接纳的候选也会回收到这里，不能取消原连接仍持有的设备级任务。
      // 观察投影变化不撤销退休责任；清理失败后仍由同一旧连接重试。
      if (_deviceTaskConnections.contains(connection)) ...[
        _transfers.cancelDevice(id),
        _fileCatalog.cancelDevice(id),
        _fileMutations.cancelDevice(id),
        _commands.cancelDeviceArtifacts(id),
      ],
      _mediaJobs.stopForConnection(id, connection),
      // 同步撤销普通执行并关闭原 worker，避免目录或传输取消仍在等待阻塞读取。
      _fileExecutor.stopForConnection(connection),
    ];
    // 首个失败立即保留退休责任；其他任务仍归各自所有者，不能断开承载连接。
    await Future.wait(stops, eagerError: true);
    final displays = _host.physicalDisplays;
    if ((await connection.client.services.connectionFacts(connection.device))
        .closed) {
      await displays.detachClosedConnection(connection);
    } else {
      try {
        await displays.stopForConnection(connection);
      } catch (_) {
        if (!(await connection.client.services.connectionFacts(
          connection.device,
        )).closed) {
          rethrow;
        }
        await displays.detachClosedConnection(connection);
      }
    }
    // 远端子任务确认退出后才能关闭承载它们的有序 RPC 部署。
    await _observations.stopForConnection(id, connection);
    await _companion.stopForConnection(id, connection);
    _deviceTaskConnections.remove(connection);
  }

  Future<Map<String, dynamic>> _dispatchBusiness(
    String command,
    Map<String, dynamic> params,
  ) async {
    try {
      if (command == 'system.info') {
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
      if (command == 'state.snapshot') return await _state.readSnapshot();
      if (command == 'activities.list') {
        final snapshot = await _state.readSnapshot();
        return {
          'activities': snapshot['activities'],
          'sessions': snapshot['sessions'],
        };
      }
      if (command == 'activities.stop') return await _stopActivity(params);
      // 偏好导入只追加未授权元数据，不重建密钥、连接或另一份执行配置。
      if (command == 'settings.export') {
        return Map.from(_records.exportMetadata());
      }
      if (command == 'settings.import') {
        final imported = await _records.importMetadata(params['metadata']);
        _publishBusiness('devices.changed', null, imported.toJson());
        return Map.from(imported.toJson());
      }
      if (_power.handles(command)) {
        return Map.from(await _power.command(command, params));
      }
      if (_devices.handles(command)) {
        final result = await _devices.command(command, params);
        if (command == 'devices.forget') {
          await _observations.forget(_deviceId(params));
        }
        return Map.from(result);
      }
      if (_sessions.handles(command)) {
        final closing = command == 'session.stop'
            ? _sessions
                  .currentSnapshots()
                  .where(
                    (session) =>
                        (params['sessionId'] == null ||
                            params['sessionId'] == session['sessionId']) &&
                        (params['deviceId'] == null ||
                            params['deviceId'] == session['deviceId']),
                  )
                  .singleOrNull
            : null;
        final result = await _sessions.command(command, params);
        if (command == 'session.list') {
          return {
            ...result,
            'sessions': [
              for (final session
                  in (result['sessions'] as List).cast<Map<String, Object?>>())
                _state.projectSession(session),
            ],
          };
        }
        if (closing != null) {
          final device = closing['deviceId'] as String;
          try {
            await _keepAwake.sync(device);
          } catch (_) {
            // 窗口停止已经确认；保持唤醒的失败与清理证据由原所有者单独保留。
          }
          final projected = _state.projectSession({
            ...result,
            'deviceId': device,
            'status': 'stopped',
          });
          final cleanup = projected['keepActiveCleanup'] as Map;
          final healthySharedLease =
              _sessions.hasAudioOwner(device) &&
              projected['keepActiveLeaseActive'] == true &&
              cleanup['error'] == null &&
              cleanup['releasePending'] != true &&
              (cleanup['pendingCleanup'] as List).isEmpty;
          if (healthySharedLease ||
              (cleanup['leaseId'] == null &&
                  cleanup['error'] == null &&
                  cleanup['releasePending'] != true &&
                  (cleanup['pendingCleanup'] as List).isEmpty)) {
            projected.remove('keepActiveCleanup');
          }
          return Map.from(projected);
        }
        if (result['sessionId'] is String && result['deviceId'] is String) {
          return Map.from(_state.projectSession(result));
        }
        return Map.from(result);
      }
      if (command.startsWith('audio.')) {
        return Map.from(await _audio.command(command, params));
      }
      if (_mediaJobs.handles(command)) {
        return Map.from(await _mediaJobs.command(command, params));
      }
      if (_observations.handles(command)) {
        return Map.from(await _observations.command(command, params));
      }
      if (command == 'apps.list' &&
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
      if (command == 'media.open') {
        if (params['kind'] != 'audio') {
          throw const ApplicationCommandException(
            'invalid_argument',
            '视频输入由窗口的精确捕获直接附着。',
          );
        }
        return Map.from(
          await _audio.openSource(
            params['sourceId'] as String,
            generation: params['generation'] as int? ?? 1,
          ),
        );
      }
      if (command == 'media.status') {
        return await _sourceStatus(params['relayId'] as String);
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

  Future<Map<String, dynamic>> _sourceStatus(String sourceId) async {
    final sessions = await _sessions.snapshots();
    for (final session in sessions) {
      if (session['videoSourceId'] != sourceId) continue;
      final connection = _devices.requireConnection(
        session['deviceId'] as String,
      );
      final status = await _host.scrcpy.sourceStatus(
        connection.device,
        captureRef: session['captureRef'] as String,
        sourceId: sourceId,
      );
      if (!identical(
        _devices.current(session['deviceId'] as String),
        connection,
      )) {
        throw const ApplicationCommandException('cancelled', '输入所属的设备连接已改变。');
      }
      return {
        'relayId': sourceId,
        'sourceId': sourceId,
        'status': status.status.name,
        'packets': status.packets,
        'bytes': status.bytes,
      };
    }
    return Map.from(await _audio.sourceStatus(sourceId));
  }

  late final ApplicationSnapshotReader _state = ApplicationSnapshotReader(
    events: _events,
    devices: _devices,
    sessions: _sessions,
    audio: _audio,
    keepAwake: _keepAwake,
    observations: _observations,
    companion: _companion,
    transfers: _transfers,
    preferences: _host.preferences,
    sharing: _sharing,
  );

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
        return _dispatchBusiness('devices.disconnect', {'deviceId': target});
      case 'session':
        return _dispatchBusiness('session.stop', {'sessionId': target});
      case 'observation':
        return _dispatchBusiness('observation.stop', {'deviceId': target});
      case 'audio':
        final source = _audio
            .snapshots()
            .where((source) => source['sourceId'] == target)
            .firstOrNull;
        if (source == null) {
          throw const ApplicationCommandException('not_found', '这代音源已结束。');
        }
        return _dispatchBusiness('audio.stop', {
          'deviceId': source['deviceId'],
          'sourceId': target,
        });
      default:
        throw const ApplicationCommandException('not_found', '此活动已结束或标识无效。');
    }
  }

  Future<void> _closeFiles() async {
    // 文件协调器先撤销任务；执行器独立排空原 worker，关闭失败不能困住任务等待。
    await Future.wait([
      _transfers.close(),
      _fileCatalog.close(),
      _fileMutations.close(),
      _fileExecutor.close(),
    ], eagerError: true);
  }

  Future<void> _closeHost() async {
    // OrderedDisposal 继续清理独立资源；承载执行层必须等全部依赖实际关闭后才退出。
    await _commands.closeMediaArtifacts();
    await _closeFiles();
    await _sharing?.close();
    await _media.dispose();
    await _health.close();
    await _power.close();
    await _devices.close();
    await _mediaJobs.close();
    await _sessions.close();
    await _audio.close();
    await _keepAwake.close();
    await _serverQueries.close();
    await _observations.close();
    await _companion.close();
    await Future.wait(_businessTasks.toList());
    await _host.close();
  }

  static Future<ApplicationSession>? _initializing;
  static String? _initializingDirectory;
  static String? _initializingPolicyJson;
  static String? _initializingBinaryDirectory;
  static ApplicationSession? _active;
  // 组装尚未交付给 Session 时也保留精确分享所有者，关闭失败由下次启动重试。
  static ShareCoordinator? _startingSharing;
  static ApplicationHost? _startingHost;

  static Future<ApplicationSession> initialize({
    required String dataDirectory,
    Directory? adbBinaryDirectory,
    ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
    DiagnosticLog? diagnostics,
  }) {
    if (_active case final existing? when !existing._disposed) {
      return Future.error(
        const ApplicationCommandException(
          'application_already_initialized',
          '此引擎已有应用会话，请复用现有实例。',
        ),
      );
    }
    if (_initializing != null && _initializingDirectory != dataDirectory) {
      return Future.error(
        const ApplicationCommandException(
          'runtime_directory_mismatch',
          '应用正在使用另一个私有目录，请重新启动应用。',
        ),
      );
    }
    final policyJson = jsonEncode(connectionPolicy.toJson());
    if (_initializing != null && _initializingPolicyJson != policyJson) {
      return Future.error(
        const ApplicationCommandException(
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
        const ApplicationCommandException(
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

  static Future<ApplicationSession> _initialize(
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
    final unfinished = _startingSharing;
    if (unfinished != null) {
      await unfinished.close();
      _startingSharing = null;
    }
    if (_startingHost case final unfinishedHost?) {
      await unfinishedHost.close();
      _startingHost = null;
    }
    final host = await ApplicationHost.attach(
      dataDirectory: dataDirectory,
      connectionPolicy: policy,
      adbBinaryDirectory: adbBinaryDirectory,
    );
    _startingHost = host;
    try {
      // 旧 isolate 的句柄先真实排空，再打开唯一的 Dart 设备与身份所有者。
      await host.recoverConnections();
      final records = await DeviceRecordStore.open(directory: host.directory);
      DeviceCoordinator? devices;
      final identities = await IdentityManager.open(
        directory: host.directory,
        records: records,
        identities: host.identities,
        invalidate: (ids, {required global}) =>
            devices?.invalidate(ids) ?? host.drainConnections(),
      );
      final identity = await identities.selectForDevice();
      final defaultClient = await host.clientForIdentity(
        identityPath: identity.path,
        fingerprint: identity.fingerprint,
      );
      final launches = await AppLaunchStore.open(directory: host.directory);
      // 读取或清理缓存前先排空旧 isolate 的文档复制，避免与恢复产生并发写入。
      await ApplicationPlatform.recoverDocuments(
        localFiles: createNativeScrcpyLocalFiles,
      );
      final sharing = Platform.isAndroid
          ? await ShareCoordinator.open(
              files: createNativeScrcpyLocalFiles,
              platform: ApplicationPlatform.requestPlatform,
            )
          : null;
      _startingSharing = sharing;
      try {
        final gate = MediaCacheGate();
        late final AppMediaCache cache;
        final deliveries = await DeliveryJournal.open(
          Directory(dataDirectory),
          cacheGate: gate,
          validateSource: (path) => cache.validateDeliveryLocked(path),
        );
        cache = await AppMediaCache.open(
          root: Directory(dataDirectory),
          gate: gate,
          protectedPaths: () => deliveries.protectedPaths,
        );
        final fileExecutor = AdbFileExecutor(
          localFiles: defaultClient.services,
          resolveConnection: (id) async => devices!.requireConnection(id),
          fileScopeId: host.fileScopeId,
          fileScopeKey: host.fileScopeKey,
        );
        final transfers = await TransferCoordinator.open(
          executor: fileExecutor,
          cache: cache,
          publication: sharing,
          dataDirectory: Directory(dataDirectory),
        );
        final session = ApplicationSession._(
          dataDirectory,
          policy,
          host,
          records,
          identities,
          launches,
          defaultClient,
          diagnostics,
          transfers,
          fileExecutor,
          cache,
          deliveries,
          sharing,
        );
        devices = session._devices;
        // 事件可能由 helper 同步交付，先建立观察所有者后再附着界面。
        session._observations;
        _startingHost = null;
        _startingSharing = null;
        try {
          await transfers.reconcileShares();
          await session._events.attach(
            files: [transfers.events, session._fileCatalog.events],
            sharing: sharing?.events,
            platform: Platform.isAndroid ? session._platform.events : null,
          );
          if (Platform.isAndroid) {
            final state = await session._platform.request(
              'audio.platform.state',
              const {},
            );
            await session._media.setVisible(state['visible'] == true);
            session._reconnections.setVisible(state['visible'] == true);
            await session._platform.attachShare();
          }
          // isolate 重启会丢失播放器及一次性媒体流；回收孤立捕获，不能接管未经核验的播放。
          await session._media.retireUnownedAudio();
          final settings = await session._commands.invoke(
            'settings.get',
            const {},
          );
          final backgroundStatus = await session._background.apply(
            settings['backgroundKeepAlive'] == true,
            automatic: true,
          );
          // 恢复快照安排连接前先应用宿主的显式或系统停止状态，之后仍允许手动连接。
          if (backgroundStatus?['stopped'] == true) {
            session._reconnections.stopAutomaticConnections();
          }
          await session._lifecycle.attach();
          // 可信快照先建立屏幕偏好和旧连接身份，再允许第一次自动重连。
          await session._stateRecovery.refresh();
          await session._reconnections.start();
          _active = session;
          return session;
        } catch (error, stack) {
          // 初始化失败也保留同一会话的清理责任，后继不能绕过未完成释放。
          _active = session;
          try {
            await session.dispose();
          } catch (_) {
            // 失败所有者留给下一次附着重试，原始启动异常仍是本次失败原因。
          }
          Error.throwWithStackTrace(error, stack);
        }
      } catch (error, stack) {
        if (sharing != null && identical(_startingSharing, sharing)) {
          try {
            await sharing.close();
            _startingSharing = null;
          } catch (_) {
            // 保留原实例，后继启动在创建新所有者之前继续收尾。
          }
        }
        Error.throwWithStackTrace(error, stack);
      }
    } catch (error, stack) {
      // 尚未交付给会话的资源也立即清理；失败保留原对象，禁止后继绕过收尾。
      if (_startingSharing case final pending?) {
        try {
          await pending.close();
          _startingSharing = null;
        } catch (_) {
          // 分享仍持有原生复制时，不能先关闭承载宿主。
        }
      }
      if (_startingSharing == null && identical(_startingHost, host)) {
        try {
          await host.close();
          _startingHost = null;
        } catch (_) {
          // 原宿主仍由静态登记持有，下一次初始化先重试。
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// 类型化调用与兼容字符串入口共用同一命令分发器。
  Future<Map<String, dynamic>> execute(
    ApplicationCommand command, [
    Map<String, dynamic> params = const {},
  ]) => request(command.wire, params);

  Future<Map<String, dynamic>> request(
    String command, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_disposed) {
      throw const ApplicationCommandException('disposed', '连接界面已关闭。');
    }
    // 拒绝必须早于连接准备与重连意图钩子，未受理命令不能撤销已有尝试。
    _requireVerifiedState(command, params);
    await _setup.beforeRequest(command, params);
    final finishReconnect = _reconnections.beforeRequest(command, params);
    final watch = Stopwatch()..start();
    try {
      final result = await _media.dispatch(command, params, _request);
      _diagnostics.command(command, params, watch.elapsedMilliseconds);
      return result;
    } catch (error) {
      _diagnostics.command(
        command,
        params,
        watch.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    } finally {
      await finishReconnect();
    }
  }

  void _requireVerifiedState(String command, Map<String, dynamic> params) {
    if (_stateRecovery.pending && needsVerifiedState(command, params)) {
      throw const ApplicationCommandException(
        'state_unverified',
        '正在重新核验设备状态，完成后再操作。',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String command,
    Map<String, dynamic> params, {
    MediaIntent? intent,
  }) async {
    if (_disposed || intent?.cancelled == true) {
      throw const ApplicationCommandException(
        'cancelled',
        '已停止本次打开，不会重新启动画面或声音。',
      );
    }
    if (command == 'state.reconcile') return _stateRecovery.refresh();
    _requireVerifiedState(command, params);
    if (_setup.handles(command)) {
      return _setup.request(command, params);
    }
    if (_capabilities.handles(command)) {
      return _capabilities.request(command, params);
    }
    // 缺口恢复时刷新投影不能创建助手；用户明确核验可通过 allowStart=true 选择启动。
    if (_stateRecovery.hasSnapshot &&
        const [
          'notifications.list',
          'calls.list',
          'clipboard.get',
        ].contains(command) &&
        !params.containsKey('allowStart')) {
      params = {...params, 'allowStart': false};
    }
    final local = await _platform.intercept(command, params);
    if (local != null) return local;
    return _media.execute(command, params, intent: intent);
  }

  /// 结束当前应用所有者；关闭失败保留原对象，下一次调用继续排空。
  Future<void> shutdown() => _shuttingDown ??= dispose().whenComplete(() {
    _shuttingDown = null;
  });

  OrderedDisposal? _disposal;

  Future<void> dispose() {
    _disposal ??= _prepareDisposal();
    return _disposal!.run().then((_) {
      if (identical(_active, this)) _active = null;
    });
  }

  OrderedDisposal _prepareDisposal() {
    _disposed = true;
    _sharing?.stopIntake();
    _media.stopAdmission();
    _lifecycle.dispose();
    _stateRecovery.dispose();
    return OrderedDisposal([
      () async =>
          await Future.wait([_reconnections.dispose(), _setup.dispose()]),
      _platform.dispose,
      _commands.closeMediaArtifacts,
      _closeFiles,
      if (_sharing != null) _sharing.close,
      _events.detach,
      _media.dispose,
      _health.close,
      _power.close,
      _devices.close,
      _mediaJobs.close,
      _sessions.close,
      _audio.close,
      _keepAwake.close,
      _serverQueries.close,
      _observations.close,
      _companion.close,
      // 依赖资源若尚未关闭，不能释放承载它们的 SDK scope 或服务器。
      _closeHost,
      _events.close,
    ]);
  }
}
