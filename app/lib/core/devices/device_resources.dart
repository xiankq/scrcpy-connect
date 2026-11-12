import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/activities/models/activity_cleanup_failed.dart';
import 'package:scrcpy_connect/core/companion/companion_recovery.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/companion/models/companion_event.dart';
import 'package:scrcpy_connect/core/companion/models/companion_config.dart';
import 'package:scrcpy_connect/core/control/display_recovery.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_apps_reader.dart';
import 'package:scrcpy_connect/core/devices/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/core/devices/device_capability_policy.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_connection_service.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/device_health_service.dart';
import 'package:scrcpy_connect/core/devices/device_metadata_transfer.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/devices/device_operations.dart';
import 'package:scrcpy_connect/core/devices/device_power_service.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';
import 'package:scrcpy_connect/core/devices/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_event.dart';
import 'package:scrcpy_connect/core/devices/models/observed_device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/devices/usb_authorization.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/identity_manager.dart';
import 'package:scrcpy_connect/core/identity/models/identity_selection.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/core/settings/models/settings_changed.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 设备记录、身份、连接策略与伴生观察的所有者。
/// 其他能力在连接退休时交回精确连接的清理回执。
final class DeviceResources {
  DeviceResources._({
    required this._directory,
    required this._clientForIdentity,
    required this._releaseIdentityClient,
    required this._displays,
    required this._companionBytes,
    required this._scrcpyServerBytes,
    required this._burstMode,
    required this._records,
    required ConnectionPolicy policy,
    required this.diagnostics,
    required bool Function() isDisposed,
    required this.isStateUnverified,
    required this.readEventSequence,
    required this.readBackgroundKeepAlive,
    required this.readSessions,
    required this.readAudio,
    required this.authorizeUsb,
    required this.cancelUsb,
    required this.onCleanupFailure,
    required this.onCompanionChanged,
    required this.onDevicesChanged,
    required this.onObservationChanged,
    required this.stopWork,
  }) : _connectionPolicy = policy,
       _isAppDisposed = isDisposed;

  final Directory _directory;
  final FutureOr<AdbClient> Function(IdentitySelection) _clientForIdentity;
  final Future<void> Function(IdentitySelection) _releaseIdentityClient;
  final DisplayRecovery _displays;
  final Uint8List _companionBytes;
  final Uint8List _scrcpyServerBytes;
  final bool Function() _burstMode;
  final DeviceRecordStorage _records;
  DeviceRecordStorage get records => _records;
  late final AdbIdentityService _identities;
  AdbIdentityService get identities => _identities;
  final ConnectionPolicy _connectionPolicy;
  final DiagnosticLog? diagnostics;
  late final _diagnostics = DiagnosticReporter(diagnostics);
  final bool Function() _isAppDisposed;
  bool _closed = false;
  bool get _isDisposed => _closed || _isAppDisposed();
  void _checkCreation() {
    if (_isDisposed) {
      throw const RequestFailure('disposed', '设备能力已关闭。');
    }
  }

  final bool Function() isStateUnverified;
  final int Function() readEventSequence;
  final bool Function() readBackgroundKeepAlive;
  final List<VideoSessionSnapshot> Function() readSessions;
  final List<DeviceAudioSnapshot> Function() readAudio;
  final Future<UsbAccess> Function(UsbAuthorizationRequest)? authorizeUsb;
  final Future<void> Function(String attemptId)? cancelUsb;
  final void Function(ActivityCleanupFailed) onCleanupFailure;
  final void Function(CompanionEvent) onCompanionChanged;
  final void Function(DeviceListChanged) onDevicesChanged;
  final void Function(DeviceObservationEvent) onObservationChanged;
  final Future<void> Function(String, DeviceConnection, bool) stopWork;
  final _observedConnections = <String, DeviceConnection>{};
  final _deviceTaskConnections = <DeviceConnection>{};
  final _cleanup = <Future<void>>{};

  DeviceService get devices => _devices;
  DeviceConnectionService get setup => _setup;
  DeviceReconnectService get reconnections => _reconnections;
  CompanionService get companion => _companion;
  DeviceObservationService get observations => _observations;
  List<ObservedDeviceSnapshot> currentObservations() =>
      _observationInstance?.currentObservedDevices() ?? [];

  /// 未创建的所有者没有待撤销的流程或观察；清理不取得新的执行能力。
  Future<void> prepareChange(ConnectionChange change) async =>
      await _setupInstance?.prepareChange(change);

  Future<void> forgetObservation(String id) async =>
      await _observationInstance?.forget(id);

  DeviceMetadataTransfer? _metadataInstance;
  DeviceMetadataTransfer get metadata {
    if (_metadataInstance == null) _checkCreation();
    return _metadataInstance ??= DeviceMetadataTransfer(
      records: _records,
      prepareImport: () =>
          prepareChange(const ConnectionChange(.replaceRecords)),
      holdReconnect: () =>
          _reconnectionInstance?.beginChange(
            const ConnectionChange(.replaceRecords),
          ) ??
          () async {},
      onImported: () =>
          onDevicesChanged(DeviceListChanged(_devices.readDevices())),
      isDisposed: () => _isDisposed,
    );
  }

  /// 宿主停止只撤销已存在的流程和连接；等待回收后仍允许新的手动连接。
  Future<void> stopConnections() {
    _reconnectionInstance?.stopAutomaticConnections();
    return Future.wait<void>([
      if (_setupInstance case final setup?) Future.sync(setup.stopPending),
      if (_deviceInstance case final devices?)
        Future.sync(devices.stopConnections),
    ]);
  }

  ScrcpyServerQueries? _queries;
  ScrcpyServerQueries get serverQueries {
    if (_queries == null) _checkCreation();
    return _queries ??= ScrcpyServerQueries(
      serverBytes: _scrcpyServerBytes,
      timeout: const Duration(seconds: 15),
    );
  }

  IdentityManagement? _identityInstance;
  IdentityManagement get identity {
    if (_identityInstance == null) _checkCreation();
    return _identityInstance ??= IdentityManager(
      keys: _identities,
      prepareChange: () => prepareChange(
        const ConnectionChange(ConnectionChangeKind.defaultIdentity),
      ),
      pauseReconnect: () => _reconnections.beginChange(
        const ConnectionChange(ConnectionChangeKind.defaultIdentity),
      ),
      publishDevices: () =>
          onDevicesChanged(DeviceListChanged(_devices.readDevices())),
      isDisposed: () => _isDisposed,
    );
  }

  DeviceApps? _appsInstance;
  DeviceApps get apps {
    if (_appsInstance == null) _checkCreation();
    return _appsInstance ??= DeviceAppsReader(
      requireConnection: _devices.requireConnection,
      currentConnection: _devices.current,
      connectionId: (id) => _devices.readDevice(id).connectionId,
      serverQueries: () => serverQueries,
      companion: () => _companion,
      isDisposed: () => _isDisposed,
      onFailure: _diagnostics.appCatalogFailed,
    );
  }

  DeviceReconnectService? _reconnectionInstance;
  DeviceReconnectService get _reconnections {
    if (_reconnectionInstance == null) _checkCreation();
    return _reconnectionInstance ??= DeviceReconnectService(
      host: _DeviceReconnectHost(
        devices: _devices,
        readSequence: readEventSequence,
        readBackgroundKeepAlive: readBackgroundKeepAlive,
      ),
      policy: _connectionPolicy,
    );
  }

  DeviceDiscovery? _discoveryInstance;
  DeviceDiscovery get _discovery {
    if (_discoveryInstance == null) _checkCreation();
    return _discoveryInstance ??= DeviceDiscovery(
      timeout: _connectionPolicy.discoveryTimeout,
    );
  }

  DeviceConnectionService? _setupInstance;
  DeviceConnectionService get _setup {
    if (_setupInstance == null) _checkCreation();
    return _setupInstance ??= DeviceConnectionService(
      devices: _devices,
      discovery: _discovery,
      burstMode: _burstMode,
      clientForIdentity: _clientForIdentity,
      releaseIdentityClient: _releaseIdentityClient,
      policy: _connectionPolicy,
      isStateUnverified: isStateUnverified,
      authorizeUsb: authorizeUsb,
      cancelUsb: cancelUsb,
      holdDevice: (id) => _reconnections.beginChange(
        ConnectionChange(ConnectionChangeKind.connect, deviceId: id),
      ),
    );
  }

  DeviceCapabilityPolicy? _capabilityInstance;
  DeviceCapabilityPolicy get _capabilities {
    if (_capabilityInstance == null) _checkCreation();
    return _capabilityInstance ??= DeviceCapabilityPolicy(
      facts: DeviceCapabilityFactsReader(
        records: _records,
        identities: _identities,
        connectionForDevice: _devices.current,
        policy: _connectionPolicy,
        observationCapabilities: (id) =>
            _observationInstance?.currentCapabilities(id) ?? [],
        sessions: () => readSessions(),
        audioSources: () => readAudio(),
      ),
      burstRequested: _burstMode,
    );
  }

  DeviceService? _deviceInstance;
  DeviceService get _devices {
    if (_deviceInstance == null) _checkCreation();
    return _deviceInstance ??= DeviceService(
      records: _records,
      identities: _identities,
      reconnectionCandidates: DeviceReconnectionCandidates.mdns(
        () => _discovery,
      ),
      clientForIdentity: _clientForIdentity,
      stopActivities: (id, connection) =>
          stopConnectionActivities(id, connection),
      prepareConnection: (id, connection, serial, cancellation) async {
        await _companion.prepareConnection(
          id,
          connection,
          serial,
          cancellation,
        );
        await _displays.recover(connection, cancellation: cancellation);
      },
      onConnected: (id, connection) => _health.start(id, connection),
      policy: _connectionPolicy,
      burstMode: _burstMode,
      onChanged: onDevicesChanged,
    );
  }

  DeviceHealthService? _healthInstance;
  DeviceHealthService get _health {
    if (_healthInstance == null) _checkCreation();
    return _healthInstance ??= DeviceHealthService(
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
  }

  DevicePowerService? _powerInstance;
  DevicePowerService get _power {
    if (_powerInstance == null) _checkCreation();
    return _powerInstance ??= DevicePowerService(
      requireConnection: _devices.requireConnection,
      timeout: _connectionPolicy.probeTimeout,
    );
  }

  CompanionService? _companionInstance;
  CompanionService get _companion {
    if (_companionInstance == null) _checkCreation();
    return _companionInstance ??= CompanionService(
      requireConnection: _devices.requireConnection,
      recovery: CompanionRecovery(_directory),
      deviceSerial: (id) => _records.current.find(id)?.serial,
      serverBytes: _companionBytes,
      config: const CompanionConfig(
        startupTimeout: Duration(seconds: 15),
        requestTimeout: Duration(seconds: 10),
        cleanupTimeout: Duration(seconds: 5),
        sessionTimeout: Duration(hours: 24),
      ),
      onChanged: onCompanionChanged,
    );
  }

  DeviceObservationService? _observationInstance;
  DeviceObservationService get _observations {
    if (_observationInstance == null) _checkCreation();
    return _observationInstance ??= DeviceObservationService(
      companion: _companion,
      records: _records,
      onChanged: onObservationChanged,
    );
  }

  DeviceOperations? _operationInstance;
  DeviceOperations get operations {
    if (_operationInstance == null) _checkCreation();
    return _operationInstance ??= DeviceOperations(
      capabilities: () => _capabilities,
      observation: () => _observations,
      calls: () => _observations,
      notifications: () => _observations,
      wake: (id, {connectionId}) =>
          _power.wakeDevice(id, connectionId: connectionId),
      isDisposed: () => _isDisposed,
      isStateUnverified: () => isStateUnverified(),
      diagnostics: _diagnostics,
    );
  }

  static Future<DeviceResources> open({
    required Directory directory,
    required AdbIdentities identities,
    required Future<void> Function() recoverConnections,
    required Future<void> Function() drainConnections,
    required FutureOr<AdbClient> Function(IdentitySelection) clientForIdentity,
    required Future<void> Function(IdentitySelection) releaseIdentityClient,
    required DisplayRecovery displays,
    required Uint8List companionBytes,
    required Uint8List scrcpyServerBytes,
    required bool Function() burstMode,
    required ConnectionPolicy policy,
    required DiagnosticLog? diagnostics,
    required bool Function() isDisposed,
    required bool Function() isStateUnverified,
    required int Function() readEventSequence,
    required bool Function() readBackgroundKeepAlive,
    required List<VideoSessionSnapshot> Function() readSessions,
    required List<DeviceAudioSnapshot> Function() readAudio,
    required Future<UsbAccess> Function(UsbAuthorizationRequest)? authorizeUsb,
    required Future<void> Function(String attemptId)? cancelUsb,
    required void Function(ActivityCleanupFailed) onCleanupFailure,
    required void Function(CompanionEvent) onCompanionChanged,
    required void Function(DeviceListChanged) onDevicesChanged,
    required void Function(DeviceObservationEvent) onObservationChanged,
    required Future<void> Function(String, DeviceConnection, bool) stopWork,
  }) async {
    await recoverConnections();
    final records = await DeviceRecordStorage.open(directory: directory);
    final owner = DeviceResources._(
      directory: directory,
      clientForIdentity: clientForIdentity,
      releaseIdentityClient: releaseIdentityClient,
      displays: displays,
      companionBytes: companionBytes,
      scrcpyServerBytes: scrcpyServerBytes,
      burstMode: burstMode,
      records: records,
      policy: policy,
      diagnostics: diagnostics,
      isDisposed: isDisposed,
      isStateUnverified: isStateUnverified,
      readEventSequence: readEventSequence,
      readBackgroundKeepAlive: readBackgroundKeepAlive,
      readSessions: readSessions,
      readAudio: readAudio,
      authorizeUsb: authorizeUsb,
      cancelUsb: cancelUsb,
      onCleanupFailure: onCleanupFailure,
      onCompanionChanged: onCompanionChanged,
      onDevicesChanged: onDevicesChanged,
      onObservationChanged: onObservationChanged,
      stopWork: stopWork,
    );
    owner._identities = await AdbIdentityService.open(
      directory: directory,
      records: records,
      identities: identities,
      invalidate: (ids, {required global}) =>
          owner._deviceInstance?.invalidate(ids) ?? drainConnections(),
    );
    return owner;
  }

  void handleRecovery(RecoveryEvent event) {
    if (_isDisposed) return;
    _reconnectionInstance?.handleEvent(switch (event) {
      RecoveryCompleted(:final snapshot) => DeviceReconnectRecovered(
        DeviceReconnectSnapshot(
          sequence: snapshot.sequence,
          devices: snapshot.devices,
          backgroundKeepAlive: snapshot.settings.backgroundKeepAlive,
        ),
      ),
      RecoveryStarted() ||
      RecoveryFailed() => const DeviceReconnectInvalidated(),
    });
  }

  void handleEvent(Map<String, dynamic> event) {
    if (_isDisposed) return;
    if (_reconnectionInstance case final reconnect?) {
      if (_reconnectEvent(event) case final update?) {
        reconnect.handleEvent(update);
      }
    }
    if (event['data'] is! DeviceListChanged) return;
    final ids = {
      ..._observedConnections.keys,
      ..._records.current.devices.map((record) => record.id),
    };
    for (final id in ids) {
      final connection = _deviceInstance?.current(id);
      if (identical(_observedConnections[id], connection)) continue;
      if (connection == null) {
        _observedConnections.remove(id);
      } else {
        _observedConnections[id] = connection;
        _deviceTaskConnections.add(connection);
      }
      final work = _observations.connectionChanged(id);
      _cleanup.add(work);
      unawaited(
        work.then<void>(
          (_) => _cleanup.remove(work),
          onError: (Object error, StackTrace stack) {
            _cleanup.remove(work);
            onCleanupFailure(ActivityCleanupFailed('$error'));
          },
        ),
      );
    }
  }

  Future<void> stopConnectionActivities(
    String id,
    DeviceConnection connection,
  ) async {
    await Future.wait([
      if (_healthInstance case final health?)
        health.stopConnection(id, connection),
      if (_powerInstance case final power?)
        power.stopConnection(id, connection),
      stopWork(id, connection, _deviceTaskConnections.contains(connection)),
      if (_queries case final queries?) queries.stopForConnection(connection),
    ], eagerError: true);
    await _displays.retireConnection(connection);
    await _observationInstance?.stopForConnection(id, connection);
    await _companionInstance?.stopForConnection(id, connection);
    _deviceTaskConnections.remove(connection);
  }

  Future<void> stopAdmission() {
    _closed = true;
    return Future.wait([
      if (_metadataInstance case final metadata?) metadata.close(),
      if (_reconnectionInstance case final reconnect?) reconnect.dispose(),
      if (_setupInstance case final setup?) setup.dispose(),
    ]);
  }

  OrderedDisposal? _disposal;

  /// 连接退休依赖观察与伴生；前一阶段未确认时保留后续执行能力，供原连接重试。
  Future<void> close() {
    _closed = true;
    _disposal ??= OrderedDisposal([
      () async => await _healthInstance?.close(),
      () async => await _powerInstance?.close(),
      () async {
        await stopAdmission();
        await _deviceInstance?.close();
        await _queries?.close();
        await _observationInstance?.close();
        await _companionInstance?.close();
        await _discoveryInstance?.close();
        await Future.wait(_cleanup.toList());
      },
    ]);
    return _disposal!.run();
  }
}

final class _DeviceReconnectHost implements DeviceReconnectHost {
  _DeviceReconnectHost({
    required this.devices,
    required this.readSequence,
    required this.readBackgroundKeepAlive,
  });
  final DeviceService devices;
  final int Function() readSequence;
  final bool Function() readBackgroundKeepAlive;
  @override
  Future<DeviceReconnectSnapshot> readSnapshot() async =>
      DeviceReconnectSnapshot(
        sequence: readSequence(),
        devices: devices.readDevices(),
        backgroundKeepAlive: readBackgroundKeepAlive(),
      );
  @override
  Future<void> connect(String deviceId, String attemptId, String ownerId) =>
      devices.connectAutomatically(deviceId, attemptId, ownerId);
  @override
  Future<void> cancel(String attemptId) =>
      devices.cancelConnectionAttempt(attemptId);
  @override
  Future<void> setOwner(String ownerId, bool active) async =>
      devices.setReconnectOwner(ownerId, active);
}

// 应用事件信封在此转换为设备事实；重连规则不解析全应用协议字段。
DeviceReconnectEvent? _reconnectEvent(Map<String, dynamic> event) {
  final type = event['type'];
  if (type == 'session.frame') return null;
  final raw = event['data'];
  final data = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  final sequence = event['sequence'];
  if (sequence is! int || sequence < 0) return null;
  return switch (type) {
    'devices.changed' when raw is DeviceListChanged =>
      DeviceReconnectDevicesChanged(raw.devices, sequence: sequence),
    'settings.changed' when raw is SettingsChanged =>
      DeviceReconnectSettingsChanged(
        raw.preferences.backgroundKeepAlive,
        sequence: sequence,
      ),
    'adb.discovery.changed' => DeviceReconnectDiscoveryChanged(
      data['guid'] as String?,
      sequence: sequence,
    ),
    'connections.stopped' => DeviceReconnectStopped(sequence: sequence),
    _ => DeviceReconnectWatermark(sequence: sequence),
  };
}
