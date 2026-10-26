library;

import 'package:scrcpy_connect/services/files/cache_storage_space.dart';

import 'package:scrcpy_connect/stores/media/app_media_cache.dart';
import 'package:scrcpy_connect/stores/media/media_artifact_coordinator.dart';
import 'package:scrcpy_connect/services/preference_commands.dart';
import 'package:scrcpy_connect/services/command_contract.dart';
import 'package:scrcpy_connect/stores/files/delivery_journal.dart';
import 'package:scrcpy_connect/stores/files/document_sources.dart';
import 'package:scrcpy_connect/services/files/document_scope_recovery.dart';
import 'package:scrcpy_connect/services/files/composite_publication_leases.dart';

import 'package:scrcpy/scrcpy.dart' show createNativeScrcpyLocalFiles;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/services/platform/diagnostic_log.dart';
import 'package:scrcpy_connect/services/platform/diagnostic_reporter.dart';

import 'package:scrcpy_connect/stores/media/media_intent_registry.dart';
import 'package:scrcpy_connect/services/media/media_capture_operations.dart';
import 'package:scrcpy_connect/services/media/scrcpy_capture_adapter.dart';

import 'package:scrcpy_connect/stores/media/media_coordinator.dart';
import 'package:scrcpy_connect/stores/state_recovery.dart';

import 'package:scrcpy_connect/stores/files/transfer_coordinator.dart';
import 'package:scrcpy_connect/stores/files/file_catalog.dart';
import 'package:scrcpy_connect/stores/files/file_mutation_coordinator.dart';
import 'package:scrcpy_connect/stores/files/share_coordinator.dart';
import 'package:scrcpy_connect/models/generated/commands_generated.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';

import 'package:scrcpy_connect/utils/ordered_disposal.dart';
import 'package:scrcpy_connect/stores/application_host.dart';
import 'package:scrcpy_connect/services/application_command_dispatcher.dart';
import 'package:scrcpy_connect/services/application_business_commands.dart';
import 'package:scrcpy_connect/services/platform/application_platform.dart';
import 'package:scrcpy_connect/services/platform/application_background_coordinator.dart';
import 'package:scrcpy_connect/services/application_platform_events.dart';
import 'package:scrcpy_connect/stores/application_events.dart';
import 'package:scrcpy_connect/services/application_lifecycle.dart';
import 'package:scrcpy_connect/services/files/adb_file_executor.dart';

import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/stores/connection/connection_setup_coordinator.dart';
import 'package:scrcpy_connect/services/connection/device_capability_policy.dart';
import 'package:scrcpy_connect/services/connection/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/services/connection/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/stores/connection/reconnection_coordinator.dart';

import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/connection/device_coordinator.dart';
import 'package:scrcpy_connect/stores/connection/device_health_coordinator.dart';
import 'package:scrcpy_connect/stores/connection/device_power_coordinator.dart';
import 'package:scrcpy_connect/stores/connection/device_discovery.dart';
import 'package:scrcpy_connect/stores/connection/identity_manager.dart';
import 'package:scrcpy_connect/stores/connection/device_record_store.dart';
import 'package:scrcpy_connect/services/application_snapshot_reader.dart';
import 'package:scrcpy_connect/services/connection/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/stores/companion_coordinator.dart';
import 'package:scrcpy_connect/stores/companion_recovery.dart';
import 'package:scrcpy_connect/stores/companion_client.dart'
    show CompanionConfig;
import 'package:scrcpy_connect/stores/observation_coordinator.dart';
import 'package:scrcpy_connect/stores/media_job_coordinator.dart';
import 'package:scrcpy_connect/stores/media/app_launch_store.dart';
import 'package:scrcpy_connect/stores/media/session_coordinator.dart';
import 'package:scrcpy_connect/stores/media/device_audio_source_coordinator.dart';
import 'package:scrcpy_connect/stores/media/device_keep_awake_coordinator.dart';

/// 按应用生命周期组装独立设备能力；ADB 传输与媒体解码由各自的包负责。
class ApplicationSession {
  ApplicationSession._({
    required this._dataDirectory,
    required this._connectionPolicy,
    required this._host,
    required this._records,
    required this._identities,
    required this._launches,
    required this._defaultClient,
    required this.diagnostics,
    required this._transfers,
    required this._fileExecutor,
    required this._cache,
    required this._deliveries,
    required this._sharing,
    required this._documentSources,
  });

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
  final DocumentSources? _documentSources;

  final DiagnosticLog? diagnostics;
  Future<AdbClient> get adb => Future.value(_defaultClient);
  late final _diagnostics = DiagnosticReporter(diagnostics);
  late final _artifacts = MediaArtifactCoordinator(
    cache: _cache,
    executor: _fileExecutor,
    request: (command, params) =>
        _business.execute(validateCommandRequest(command, params), params),
    emit: _events.emit,
  );
  late final _preferences = PreferenceCommands(
    preferences: _host.preferences,
    records: _records,
    onDevicesImported: (receipt) =>
        _events.publish({'type': 'devices.changed', 'data': receipt.toJson()}),
    applyBackgroundPolicy: (enabled) =>
        _background.apply(enabled, automatic: false),
    onChanged: (settings) {
      if (_disposed) return;
      _reconnections.updateSettings(settings);
      _events.publish({'type': 'settings.changed', 'data': settings});
      _observeCleanup(
        _keepAwake.settingsChanged(
          _records.current.devices.map((record) => record.id),
        ),
      );
    },
  );
  late final ApplicationCommandDispatcher _commands =
      ApplicationCommandDispatcher(
        catalog: _fileCatalog,
        mutations: _fileMutations,
        transfers: _transfers,
        preferences: _preferences,
        cache: _cache,
        deliveries: _deliveries,
        sharing: _sharing,
        artifacts: _artifacts,
        onMediaEvent: _events.emit,
        execute: _business.execute,
      );

  late final _captures = MediaCaptureOperations(
    sessions: _sessions,
    audio: _audio,
    keepAwake: _keepAwake,
    devices: _devices,
    state: _state,
    scrcpy: _host.scrcpy,
  );
  late final _business = ApplicationBusinessCommands(
    devices: _devices,
    power: _power,
    audio: _audio,
    captures: _captures,
    mediaJobs: _mediaJobs,
    observations: _observations,
    companion: _companion,
    serverQueries: _serverQueries,
    state: _state,
    isDisposed: () => _disposed,
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
    documentSources: _documentSources,
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
    invoke: _commands.invokeCommand,
    captures: _captures,
    readSnapshot: _state.readSnapshot,
    readSettings: _preferences.read,
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
    prepareConnection: (id, connection, serial, cancellation) async {
      await _companion.prepareConnection(id, connection, serial, cancellation);
      await _host.physicalDisplays.recover(
        connection,
        cancellation: cancellation,
      );
    },
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
  void Function() bindClipboardAdmission(
    bool Function(String, String, int) check,
  ) => _sessions.bindClipboardAdmission(check);

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
    recovery: CompanionRecovery(Directory(_dataDirectory)),
    deviceSerial: (id) => _records.current.find(id)?.serial,
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
        _artifacts.cancelDevice(id),
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
    await _artifacts.close();
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
    await _closeStartingResources();
    final host = await ApplicationHost.attach(
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
        await session._activate();
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

  static Future<ApplicationSession> _assemble(
    ApplicationHost host,
    String dataDirectory,
    ConnectionPolicy policy,
    DiagnosticLog? diagnostics,
  ) async {
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
    final documentSources = Platform.isAndroid
        ? await DocumentSources.open(
            cacheDirectory: Directory(
              (await DocumentScopeConfiguration.fromEnvironment(
                await ApplicationPlatform.requestPlatform(
                  'documents.platform.environment',
                  const {},
                ),
              )).cacheDirectory,
            ),
          )
        : null;
    final sharing = Platform.isAndroid
        ? await ShareCoordinator.open(
            files: createNativeScrcpyLocalFiles,
            platform: ApplicationPlatform.requestPlatform,
          )
        : null;
    _startingSharing = sharing;
    final gate = MediaCacheGate();
    late final AppMediaCache cache;
    TransferCoordinator? cacheTransfers;
    final deliveries = await DeliveryJournal.open(
      Directory(dataDirectory),
      cacheGate: gate,
      validateSource: (path) => cache.validateDeliveryLocked(path),
    );
    cache = await AppMediaCache.open(
      root: Directory(dataDirectory),
      gate: gate,
      protectedPaths: () => deliveries.protectedPaths,
      freeBytes: cacheStorageFreeBytes,
      protectionDetails: () async => [
        for (final source
            in cacheTransfers?.cacheSources ?? <Map<String, Object?>>[])
          {
            ...source,
            'sourceLabel':
                records.current.find(source['sourceLabel'] as String)?.name ??
                source['sourceLabel'],
          },
        ...await deliveries.protectedSources,
      ],
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
      publication: documentSources == null
          ? sharing
          : CompositePublicationLeases(
              sharing: sharing,
              documents: documentSources,
            ),
      dataDirectory: Directory(dataDirectory),
    );
    cacheTransfers = transfers;
    final session = ApplicationSession._(
      dataDirectory: dataDirectory,
      connectionPolicy: policy,
      host: host,
      records: records,
      identities: identities,
      launches: launches,
      defaultClient: defaultClient,
      diagnostics: diagnostics,
      transfers: transfers,
      fileExecutor: fileExecutor,
      cache: cache,
      deliveries: deliveries,
      sharing: sharing,
      documentSources: documentSources,
    );
    devices = session._devices;
    // 事件可能由 helper 同步交付，先建立观察所有者后再附着界面。
    session._observations;
    return session;
  }

  Future<void> _activate() async {
    await _transfers.reconcileShares();
    await _events.attach(
      files: [_transfers.events, _fileCatalog.events],
      sharing: _sharing?.events,
      platform: Platform.isAndroid ? _platform.events : null,
    );
    if (Platform.isAndroid) {
      final state = await _platform.request('audio.platform.state', const {});
      await _media.setVisible(state['visible'] == true);
      _reconnections.setVisible(state['visible'] == true);
      await _platform.attachShare();
    }
    // isolate 重启会丢失播放器及一次性媒体流；回收孤立捕获，不能接管未经核验的播放。
    await _media.retireUnownedAudio();
    final settings = await _commands.invoke('settings.get', const {});
    final backgroundStatus = await _background.apply(
      settings['backgroundKeepAlive'] == true,
      automatic: true,
    );
    // 恢复快照安排连接前先应用宿主的显式或系统停止状态，之后仍允许手动连接。
    if (backgroundStatus?['stopped'] == true) {
      _reconnections.stopAutomaticConnections();
    }
    await _lifecycle.attach();
    // 可信快照先建立屏幕偏好和旧连接身份，再允许第一次自动重连。
    await _stateRecovery.refresh();
    await _reconnections.start();
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// wire 请求只在入口解析一次；应用内部保留类型化命令。
  Future<Map<String, dynamic>> request(
    String command, [
    Map<String, dynamic> params = const {},
  ]) async => execute(validateCommandRequest(command, params), params);

  Future<Map<String, dynamic>> execute(
    ApplicationCommand operation, [
    Map<String, dynamic> params = const {},
  ]) async {
    final command = operation.wire;
    if (_disposed) {
      throw const ApplicationCommandException('disposed', '连接界面已关闭。');
    }
    // 拒绝必须早于连接准备与重连意图钩子，未受理命令不能撤销已有尝试。
    validateTypedCommandRequest(operation, params);
    _requireVerifiedState(command, params);
    await _setup.beforeRequest(command, params);
    final finishReconnect = _reconnections.beforeRequest(command, params);
    final watch = Stopwatch()..start();
    try {
      final result = await _media.dispatch(operation, params, _request);
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
    ApplicationCommand operation,
    Map<String, dynamic> params, {
    MediaIntent? intent,
  }) async {
    final command = operation.wire;
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
    return _media.execute(operation, params, intent: intent);
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
      _artifacts.close,
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
