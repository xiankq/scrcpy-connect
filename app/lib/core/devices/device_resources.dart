import 'dart:async';
import 'dart:io';

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
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/identity_manager.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 设备记录、身份、连接策略与伴生观察的所有者。
/// 其他能力在连接退休时交回精确连接的清理回执。
final class DeviceResources {
  DeviceResources._({
    required this.host,
    required this._records,
    required this._identities,
    required this._dataDirectory,
    required ConnectionPolicy policy,
    required this.diagnostics,
    required this.isDisposed,
    required this.isStateUnverified,
    required this.readSnapshot,
    required this.readSessions,
    required this.readAudio,
    required this.serverQueries,
    required this.authorizeUsb,
    required this.cancelUsb,
    required this.releaseUsb,
    required this.emit,
    required this.publish,
    required this.stopWork,
    required this.stopDisplays,
  }) : _connectionPolicy = policy;

  final NativeHost host;
  NativeHost get _host => host;
  final DeviceRecordStorage _records;
  DeviceRecordStorage get records => _records;
  final AdbIdentityService _identities;
  AdbIdentityService get identities => _identities;
  final String _dataDirectory;
  final ConnectionPolicy _connectionPolicy;
  final DiagnosticLog? diagnostics;
  late final _diagnostics = DiagnosticReporter(diagnostics);
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final Future<Map<String, dynamic>> Function() readSnapshot;
  final List<VideoSessionSnapshot> Function() readSessions;
  final List<DeviceAudioSnapshot> Function() readAudio;
  final ScrcpyServerQueries Function() serverQueries;
  final Future<Json> Function(Json)? Function() authorizeUsb;
  final Future<void> Function(Json)? Function() cancelUsb, releaseUsb;
  final void Function(Map<String, dynamic>) emit;
  final void Function(String, String?, Map<String, Object?>) publish;
  final Future<void> Function(String, DeviceConnection, bool) stopWork;
  final Future<void> Function(DeviceConnection) stopDisplays;
  final _observedConnections = <String, DeviceConnection>{};
  final _deviceTaskConnections = <DeviceConnection>{};
  final _cleanup = <Future<void>>{};

  DeviceService get devices => _devices;
  DeviceConnectionService get setup => _setup;
  DeviceReconnectService get reconnections => _reconnections;
  CompanionService get companion => _companion;
  DeviceObservationService get observations => _observations;

  late final IdentityManagement identity = IdentityManager(
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
    isDisposed: () => isDisposed(),
  );

  late final DeviceApps apps = DeviceAppsReader(
    requireConnection: _devices.requireConnection,
    currentConnection: _devices.current,
    connectionId: (id) => _devices.readDevice(id).connectionId,
    serverQueries: serverQueries(),
    companion: _companion,
    isDisposed: () => isDisposed(),
    onFailure: _diagnostics.appCatalogFailed,
  );

  late final _reconnections = DeviceReconnectService(
    host: _RuntimeReconnectHost(_devices, readSnapshot),
    policy: _connectionPolicy,
  );
  late final _discovery = DeviceDiscovery(
    timeout: _connectionPolicy.discoveryTimeout,
  );
  late final _setup = DeviceConnectionService(
    devices: _devices,
    discovery: _discovery,
    burstMode: () => _host.preferences.current.values.adbBurstMode,
    clientForIdentity: (identity) => _host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    releaseIdentityClient: (identity) => _host.releaseIdentityClient(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    policy: _connectionPolicy,
    emit: emit,
    authorizeUsb: authorizeUsb(),
    cancelUsb: cancelUsb(),
    releaseUsb: releaseUsb(),
    holdDevice: (id) => _reconnections.beginChange(
      ConnectionChange(ConnectionChangeKind.connect, deviceId: id),
    ),
  );
  late final _capabilities = DeviceCapabilityPolicy(
    facts: DeviceCapabilityFactsReader(
      records: _records,
      identities: _identities,
      connectionForDevice: _devices.current,
      policy: _connectionPolicy,
      observationCapabilities: _observations.currentCapabilities,
      sessions: () => readSessions(),
      audioSources: () => readAudio(),
    ),
    burstRequested: () => _host.preferences.current.values.adbBurstMode,
  );

  DeviceService? _deviceInstance;
  DeviceService get _devices => _deviceInstance ??= DeviceService(
    records: _records,
    identities: _identities,
    reconnectionCandidates: DeviceReconnectionCandidates.mdns(_discovery),
    clientForIdentity: (identity) => _host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    stopActivities: (id, connection) =>
        stopConnectionActivities(id, connection),
    prepareConnection: (id, connection, serial, cancellation) async {
      await _companion.prepareConnection(id, connection, serial, cancellation);
      await _host.physicalDisplays.recover(
        connection,
        cancellation: cancellation,
      );
    },
    onConnected: (id, connection) => _health.start(id, connection),
    policy: _connectionPolicy,
    burstMode: () => _host.preferences.current.values.adbBurstMode,
    emit: (type, data) => publish(type, null, data),
  );
  DeviceHealthService? _healthInstance;
  DeviceHealthService get _health => _healthInstance ??= DeviceHealthService(
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
  DevicePowerService? _powerInstance;
  DevicePowerService get _power => _powerInstance ??= DevicePowerService(
    requireConnection: _devices.requireConnection,
    timeout: _connectionPolicy.probeTimeout,
  );

  late final CompanionService _companion = CompanionService(
    requireConnection: _devices.requireConnection,
    recovery: CompanionRecovery(Directory(_dataDirectory)),
    deviceSerial: (id) => _records.current.find(id)?.serial,
    serverBytes: _host.companionBytes,
    config: const CompanionConfig(
      startupTimeout: Duration(seconds: 15),
      requestTimeout: Duration(seconds: 10),
      cleanupTimeout: Duration(seconds: 5),
      sessionTimeout: Duration(hours: 24),
    ),
    emit: (type, device, data) => publish(type, device, data),
  );
  late final DeviceObservationService _observations = DeviceObservationService(
    companion: _companion,
    records: _records,
    emit: (type, device, data) => publish(type, device, data),
  );

  late final operations = DeviceOperations(
    capabilities: _capabilities,
    observation: _observations,
    calls: _observations,
    notifications: _observations,
    wake: _power.wakeDevice,
    isDisposed: () => isDisposed(),
    isStateUnverified: () => isStateUnverified(),
    diagnostics: _diagnostics,
  );

  static Future<DeviceResources> open({
    required NativeHost host,
    required String dataDirectory,
    required ConnectionPolicy policy,
    required DiagnosticLog? diagnostics,
    required bool Function() isDisposed,
    required bool Function() isStateUnverified,
    required Future<Map<String, dynamic>> Function() readSnapshot,
    required List<VideoSessionSnapshot> Function() readSessions,
    required List<DeviceAudioSnapshot> Function() readAudio,
    required ScrcpyServerQueries Function() serverQueries,
    required Future<Json> Function(Json)? Function() authorizeUsb,
    required Future<void> Function(Json)? Function() cancelUsb,
    required Future<void> Function(Json)? Function() releaseUsb,
    required void Function(Map<String, dynamic>) emit,
    required void Function(String, String?, Map<String, Object?>) publish,
    required Future<void> Function(String, DeviceConnection, bool) stopWork,
    required Future<void> Function(DeviceConnection) stopDisplays,
  }) async {
    await host.recoverConnections();
    final records = await DeviceRecordStorage.open(directory: host.directory);
    DeviceResources? owner;
    final identities = await AdbIdentityService.open(
      directory: host.directory,
      records: records,
      identities: host.identities,
      invalidate: (ids, {required global}) =>
          owner?._deviceInstance?.invalidate(ids) ?? host.drainConnections(),
    );
    return owner = DeviceResources._(
      host: host,
      records: records,
      identities: identities,
      dataDirectory: dataDirectory,
      policy: policy,
      diagnostics: diagnostics,
      isDisposed: isDisposed,
      isStateUnverified: isStateUnverified,
      readSnapshot: readSnapshot,
      readSessions: readSessions,
      readAudio: readAudio,
      serverQueries: serverQueries,
      authorizeUsb: authorizeUsb,
      cancelUsb: cancelUsb,
      releaseUsb: releaseUsb,
      emit: emit,
      publish: publish,
      stopWork: stopWork,
      stopDisplays: stopDisplays,
    );
  }

  void handleEvent(Map<String, dynamic> event) {
    if (isDisposed()) return;
    _setup.handleEvent(event);
    _reconnections.handleEvent(event);
    if (event['type'] != 'devices.changed') return;
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
    await stopDisplays(connection);
    await _observations.stopForConnection(id, connection);
    await _companion.stopForConnection(id, connection);
    _deviceTaskConnections.remove(connection);
  }

  Future<void> stopAdmission() async =>
      await Future.wait([_reconnections.dispose(), _setup.dispose()]);
  OrderedDisposal? _connectionsClose, _servicesClose;
  Future<void> closeConnections() {
    _connectionsClose ??= OrderedDisposal([
      () async => await _healthInstance?.close(),
      () async => await _powerInstance?.close(),
      _devices.close,
    ]);
    return _connectionsClose!.run();
  }

  Future<void> closeServices() {
    _servicesClose ??= OrderedDisposal([
      _observations.close,
      _companion.close,
      () async => await Future.wait(_cleanup.toList()),
    ]);
    return _servicesClose!.run();
  }
}

final class _RuntimeReconnectHost implements DeviceReconnectHost {
  _RuntimeReconnectHost(this.devices, this.state);
  final DeviceService devices;
  final Future<Map<String, dynamic>> Function() state;
  @override
  Future<ReconnectJson> readSnapshot() => state();
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
