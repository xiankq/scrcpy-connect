import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/core/companion/companion_recovery.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/companion/models/companion_config.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_apps_reader.dart';
import 'package:scrcpy_connect/core/devices/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/core/devices/device_capability_policy.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/device_connection_service.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/devices/device_health_service.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/devices/device_operations.dart';
import 'package:scrcpy_connect/core/devices/device_power_service.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';
import 'package:scrcpy_connect/core/devices/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/identity_manager.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/control/display_recovery.dart';
import 'package:scrcpy_connect/core/identity/models/identity_selection.dart';
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
    required this.serverQueries,
    required this.authorizeUsb,
    required this.cancelUsb,
    required this.releaseUsb,
    required this.emit,
    required this.publish,
    required this.stopWork,
  }) : _connectionPolicy = policy,
       _isAppDisposed = isDisposed;

  final Directory _directory;
  final FutureOr<AdbClient> Function(IdentitySelection) _clientForIdentity;
  final Future<void> Function(IdentitySelection) _releaseIdentityClient;
  final DisplayRecovery _displays;
  final Uint8List _companionBytes;
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
  final ScrcpyServerQueries Function() serverQueries;
  final Future<Json> Function(Json)? authorizeUsb;
  final Future<void> Function(Json)? cancelUsb, releaseUsb;
  final void Function(Map<String, dynamic>) emit;
  final void Function(String, String?, Map<String, Object?>) publish;
  final Future<void> Function(String, DeviceConnection, bool) stopWork;
  final _observedConnections = <String, DeviceConnection>{};
  final _deviceTaskConnections = <DeviceConnection>{};
  final _cleanup = <Future<void>>{};

  DeviceService get devices => _devices;
  DeviceConnectionService get setup => _setup;
  DeviceReconnectService get reconnections => _reconnections;
  CompanionService get companion => _companion;
  DeviceObservationService get observations => _observations;

  IdentityManagement? _identityInstance;
  IdentityManagement get identity {
    if (_identityInstance == null) _checkCreation();
    return _identityInstance ??= IdentityManager(
      keys: _identities,
      prepareChange: () => _setup.prepareChange(
        const ConnectionChange(ConnectionChangeKind.defaultIdentity),
      ),
      pauseReconnect: () => _reconnections.beginChange(
        const ConnectionChange(ConnectionChangeKind.defaultIdentity),
      ),
      publishDevices: () => publish('devices.changed', null, {
        'devices': _devices.projectDevices(),
      }),
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
      serverQueries: serverQueries(),
      companion: _companion,
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
      emit: emit,
      authorizeUsb: authorizeUsb,
      cancelUsb: cancelUsb,
      releaseUsb: releaseUsb,
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
      reconnectionCandidates: DeviceReconnectionCandidates.mdns(_discovery),
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
      emit: (type, data) => publish(type, null, data),
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
      emit: (type, device, data) => publish(type, device, data),
    );
  }

  DeviceObservationService? _observationInstance;
  DeviceObservationService get _observations {
    if (_observationInstance == null) _checkCreation();
    return _observationInstance ??= DeviceObservationService(
      companion: _companion,
      records: _records,
      emit: (type, device, data) => publish(type, device, data),
    );
  }

  DeviceOperations? _operationInstance;
  DeviceOperations get operations {
    if (_operationInstance == null) _checkCreation();
    return _operationInstance ??= DeviceOperations(
      capabilities: _capabilities,
      observation: _observations,
      calls: _observations,
      notifications: _observations,
      wake: _power.wakeDevice,
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
    required bool Function() burstMode,
    required ConnectionPolicy policy,
    required DiagnosticLog? diagnostics,
    required bool Function() isDisposed,
    required bool Function() isStateUnverified,
    required int Function() readEventSequence,
    required bool Function() readBackgroundKeepAlive,
    required List<VideoSessionSnapshot> Function() readSessions,
    required List<DeviceAudioSnapshot> Function() readAudio,
    required ScrcpyServerQueries Function() serverQueries,
    required Future<Json> Function(Json)? authorizeUsb,
    required Future<void> Function(Json)? cancelUsb,
    required Future<void> Function(Json)? releaseUsb,
    required void Function(Map<String, dynamic>) emit,
    required void Function(String, String?, Map<String, Object?>) publish,
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
      serverQueries: serverQueries,
      authorizeUsb: authorizeUsb,
      cancelUsb: cancelUsb,
      releaseUsb: releaseUsb,
      emit: emit,
      publish: publish,
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

  void handleEvent(Map<String, dynamic> event) {
    if (_isDisposed) return;
    _setupInstance?.handleEvent(event);
    if (_reconnectionInstance case final reconnect?) {
      if (_reconnectEvent(event) case final update?) {
        reconnect.handleEvent(update);
      }
    }
    if (event['type'] != 'devices.changed') return;
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
            emit({
              'type': 'activity.cleanup.failed',
              'data': {'reason': '$error'},
            });
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
    ], eagerError: true);
    await _displays.retireConnection(connection);
    await _observationInstance?.stopForConnection(id, connection);
    await _companionInstance?.stopForConnection(id, connection);
    _deviceTaskConnections.remove(connection);
  }

  Future<void> stopAdmission() {
    _closed = true;
    return Future.wait([
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
  if (type == 'session.frame' || type == 'runtime.heartbeat') return null;
  if (type == 'state.resync' || type == 'state.resync.failed') {
    return const DeviceReconnectInvalidated();
  }
  final raw = event['data'];
  final data = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  List<DeviceSnapshot>? devices() => data['devices'] is List
      ? [
          for (final device in data['devices'] as List)
            DeviceSnapshot.fromJson(Map<String, dynamic>.from(device as Map)),
        ]
      : null;
  if (type == 'state.resynced') {
    final sequence = data['sequence'];
    if (sequence is! int || sequence < 0) return null;
    final settings = data['settings'];
    return DeviceReconnectRecovered(
      DeviceReconnectSnapshot(
        sequence: sequence,
        devices: devices() ?? [],
        backgroundKeepAlive:
            settings is Map && settings['backgroundKeepAlive'] == true,
      ),
    );
  }
  final sequence = event['sequence'];
  if (sequence is! int || sequence < 0) return null;
  return switch (type) {
    'devices.changed' => DeviceReconnectDevicesChanged(
      devices(),
      sequence: sequence,
    ),
    'device.changed' when data['id'] is String => DeviceReconnectDeviceChanged(
      DeviceSnapshot.fromJson(data),
      sequence: sequence,
    ),
    'settings.changed' => DeviceReconnectSettingsChanged(
      data['backgroundKeepAlive'] == true,
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
