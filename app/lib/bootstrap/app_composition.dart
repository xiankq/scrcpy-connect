import 'dart:async';
import 'dart:io';

import 'package:scrcpy/scrcpy.dart'
    show createNativeScrcpyLocalFiles, readNativeScrcpyLocalStorageFreeBytes;
import 'package:scrcpy_connect/core/activities/activity_catalog.dart';
import 'package:scrcpy_connect/core/companion/companion_recovery.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/companion/models/companion_config.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_cache_gate.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/content/thumbnail_job_service.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/control_operations.dart';
import 'package:scrcpy_connect/core/control/control_session_service.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';
import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/core/devices/device_actions.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_apps_reader.dart';
import 'package:scrcpy_connect/core/devices/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/core/devices/device_capability_policy.dart';
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
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/adb_file_executor.dart';
import 'package:scrcpy_connect/core/files/file_catalog.dart';
import 'package:scrcpy_connect/core/files/file_delivery_journal.dart';
import 'package:scrcpy_connect/core/files/file_document_cache.dart';
import 'package:scrcpy_connect/core/files/file_document_scope.dart';
import 'package:scrcpy_connect/core/files/file_mutation_service.dart';
import 'package:scrcpy_connect/core/files/file_operations.dart';
import 'package:scrcpy_connect/core/files/file_publication_lease_pool.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/identity/identity_manager.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifecycle.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/media/media_operations.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/app_platform.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/core/platform/platform_event_handler.dart';
import 'package:scrcpy_connect/core/recovery/runtime_snapshot_reader.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';

/// 启动时创建唯一的能力依赖图；业务操作与生命周期由注入的所有者实现。
final class AppComposition {
  AppComposition._({
    required this._dataDirectory,
    required this._connectionPolicy,
    required this._host,
    required this._records,
    required this._identities,
    required this._launches,
    required this.diagnostics,
    required this._transfers,
    required this._fileExecutor,
    required this._cache,
    required this._deliveries,
    required this._sharing,
    required this._documentSources,
  });

  final NativeHost _host;
  final DeviceRecordStorage _records;
  final AdbIdentityService _identities;
  final AppLaunchJournal _launches;
  final FileTransferService _transfers;
  final AdbFileExecutor _fileExecutor;
  late final _fileCatalog = FileCatalog(_fileExecutor);
  late final _fileMutations = FileMutationService(_fileExecutor);
  final ContentCache _cache;
  final FileDeliveryJournal _deliveries;
  final FileShareService? _sharing;
  final FileDocumentCache? _documentSources;

  final DiagnosticLog? diagnostics;
  late final _diagnostics = DiagnosticReporter(diagnostics);
  late final _artifacts = ContentPreview(
    cache: _cache,
    executor: _fileExecutor,
    jobs: _mediaJobs,
    isDisposed: () => lifecycle.isDisposed,
    emit: _events.emit,
  );
  late final IdentityManagement identity = IdentityManager(
    keys: _identities,
    prepareChange: () => _setup.prepareChange(
      const ConnectionChange(ConnectionChangeKind.defaultIdentity),
    ),
    pauseReconnect: () => _reconnections.beginChange(
      const ConnectionChange(ConnectionChangeKind.defaultIdentity),
    ),
    publishDevices: () => lifecycle.publishBusiness('devices.changed', null, {
      'devices': _devices.projectDevices(),
    }),
    isDisposed: () => lifecycle.isDisposed,
  );
  late final _deviceActions = DeviceActions(
    devices: _devices,
    connections: _devices,
    setup: _setup,
    isStateUnverified: () => _stateRecovery.pending,
    prepareChange: _setup.prepareChange,
    beginChange: _reconnections.beginChange,
    cancelContent: _artifacts.cancelDevice,
    cancelUsbAttempt: (id) async {
      if (Platform.isAndroid) await _platform.cancelUsb({'attemptId': id});
    },
    cancelFiles: (id) => lifecycle.cancelDeviceFiles(id),
    forgetObservation: _observations.forget,
    forgetPreferences: _preferences.forgetDevicePreferences,
    stopMediaIntent: _media.stopDeviceIntent,
    finishMediaStop: _media.finishDeviceStop,
    isDisposed: () => lifecycle.isDisposed,
    announceStop: (id) => _events.emit({
      'type': 'device.disconnect.requested',
      'deviceId': id,
      'data': <String, dynamic>{},
    }),
    diagnostics: _diagnostics,
  );

  late final DeviceApps apps = DeviceAppsReader(
    requireConnection: _devices.requireConnection,
    currentConnection: _devices.current,
    connectionId: (id) => _devices.readDevice(id).connectionId,
    serverQueries: _serverQueries,
    companion: _companion,
    isDisposed: () => lifecycle.isDisposed,
    onFailure: _diagnostics.appCatalogFailed,
  );
  late final _preferences = AppSettings(
    preferences: _host.preferences,
    isDisposed: () => lifecycle.isDisposed,
    prepareImport: () => _setup.prepareChange(
      const ConnectionChange(ConnectionChangeKind.replaceRecords),
    ),
    pauseReconnect: () => _reconnections.beginChange(
      const ConnectionChange(ConnectionChangeKind.replaceRecords),
    ),
    records: _records,
    onDevicesImported: (receipt) =>
        _events.publish({'type': 'devices.changed', 'data': receipt.toJson()}),
    applyBackgroundPolicy: (enabled) =>
        _background.apply(enabled, automatic: false),
    onChanged: (preferences) => lifecycle.settingsChanged(preferences),
  );

  late final _captures = MediaCapture(
    sessions: _sessions,
    audio: _audio,
    keepAwake: _keepAwake,
    connectionForDevice: _devices.current,
    preferences: _preferences,
    scrcpy: _host.scrcpy,
  );

  late final _activities = ActivityCatalog(
    diagnostics: _diagnostics,
    events: _events,
    devices: _devices,
    sessions: _sessions,
    observations: _observations,
    audio: _audio,
    transfers: _transfers,
    disconnectDevice: (id) => _deviceActions.disconnectDevice(id),
    stopAudio: (target) => _media.stopAudio(target),
    stopVideo: (id) async {
      _events.emit({
        'type': 'session.stop.requested',
        'data': {'sessionId': id},
      });
      await _media.stopVideo(ControlTarget(sessionId: id));
    },
    isDisposed: () => lifecycle.isDisposed,
  );

  final ConnectionPolicy _connectionPolicy;
  late final _reconnections = DeviceReconnectService(
    host: _RuntimeReconnectHost(_devices, _state),
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
    emit: (event) {
      _events.emit(event);
    },
    authorizeUsb: Platform.isAndroid ? _platform.authorizeUsb : null,
    cancelUsb: Platform.isAndroid ? _platform.cancelUsb : null,
    releaseUsb: Platform.isAndroid ? _platform.releaseUsb : null,
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
      sessions: () => _sessions.currentSessions(),
      audioSources: () => _audio.snapshots(activeOnly: true),
    ),
    burstRequested: () => _host.preferences.current.values.adbBurstMode,
  );

  final String _dataDirectory;

  late final BackgroundPolicy _background = BackgroundPolicy(
    platform: Platform.isAndroid ? _platform : null,
    audioPolicy: (enabled) async {
      await _media.policy(enabled);
    },
    onChanged: (status) =>
        _events.emit({'type': 'background.changed', 'data': status.toJson()}),
    onFailure: (error) => _events.emit({
      'type': 'background.failed',
      'data': {'reason': '$error'},
    }),
  );

  late final AppPlatform _platform = AppPlatform(
    usbOwnerLeaseId: _host.usbOwnerLeaseId,
    localFiles: createNativeScrcpyLocalFiles,
    sharing: _sharing,
    documentSources: _documentSources,
    deliveries: _deliveries,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => lifecycle.isDisposed,
  );
  late final _platformEvents = PlatformEventHandler(
    reconnections: _reconnections,
    isDisposed: () => lifecycle.isDisposed,
    stopConnections: () =>
        Future.wait([_setup.stopPending(), _devices.stopConnections()]),
    emit: (event) => _events.emit(event),
    handleShare: _platform.handleShare,
    handleMedia: _media.handlePlatformEvent,
  );
  late final RuntimeEvents _events = RuntimeEvents(
    acceptState: (event) => _stateRecovery.accept(event),
    onState: (event) => _diagnostics.applicationEvent(event),
    onLocalStateChanged: () => _stateRecovery.noteLocalStateChange(),
    beforePublish: (event) => lifecycle.handleBusinessEvent(event),
    afterState: (event) => _media.handleApplicationEvent(event),
    handlePlatform: (event) => _platformEvents.handle(event),
    isDisposed: () => lifecycle.isDisposed,
  );
  late final MediaPlayback _media = MediaPlayback(
    captures: _captures,
    readSnapshot: _state.readSnapshot,
    readSettings: _preferences.read,
    platform: _platform.audioRequest,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => lifecycle.isDisposed,
    requireVerifiedState: () => lifecycle.requireVerifiedState(),
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
    isDisposed: () => lifecycle.isDisposed,
  );
  late final DeviceService _devices = DeviceService(
    records: _records,
    identities: _identities,
    reconnectionCandidates: DeviceReconnectionCandidates.mdns(_discovery),
    clientForIdentity: (identity) => _host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    ),
    stopActivities: (id, connection) =>
        lifecycle.stopConnectionActivities(id, connection),
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
    emit: (type, data) => lifecycle.publishBusiness(type, null, data),
  );
  late final DeviceHealthService _health = DeviceHealthService(
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
  late final DevicePowerService _power = DevicePowerService(
    requireConnection: _devices.requireConnection,
    timeout: _connectionPolicy.probeTimeout,
  );
  late final ScrcpyServerQueries _serverQueries = ScrcpyServerQueries(
    serverBytes: _host.scrcpyBytes,
    timeout: const Duration(seconds: 15),
  );
  bool completeDocumentSelection(String id, Json result) =>
      _platform.documentSelections.complete(id, result);

  late final ControlSessionService _sessions = ControlSessionService(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    launches: _launches,
    onClipboardFailure: _diagnostics.clipboardFailure,
    requireClipboardAccess: () {
      if (lifecycle.isDisposed) {
        throw const RequestFailure('disposed', '连接界面已关闭。');
      }
      if (_stateRecovery.pending) {
        throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
      }
    },
    serverQueries: _serverQueries,
    settings: () => _host.preferences.current.values,
    emit: (type, device, data) => lifecycle.publishBusiness(type, device, data),
    onAudioEligibilityChanged: (id) {
      // 同步撤准入后记录实际排空，回调不等待其他设备，也不丢弃失败所有者。
      lifecycle.observeCleanup(_audio.eligibilityChanged(id));
      lifecycle.observeCleanup(_keepAwake.windowsChanged(id));
    },
  );
  late final DeviceAudioService _audio = DeviceAudioService(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    hasAudioOwner: _sessions.hasAudioOwner,
    deviceName: (id) => _records.current.find(id)?.name ?? 'Android 设备',
    apiLevel: (id) => _records.current.find(id)?.apiLevel,
    emit: (type, device, data) => lifecycle.publishBusiness(type, device, data),
  );
  late final DeviceWakeService _keepAwake = DeviceWakeService(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    hasWindowOwner: _sessions.hasAudioOwner,
    keepAwakeEnabled: (deviceId) =>
        _host.preferences.current.values.deviceSettings[deviceId]?.stayAwake ==
        true,
    emit: (type, device, data) => lifecycle.publishBusiness(type, device, data),
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
    emit: (type, device, data) => lifecycle.publishBusiness(type, device, data),
  );
  late final DeviceObservationService _observations = DeviceObservationService(
    companion: _companion,
    records: _records,
    emit: (type, device, data) => lifecycle.publishBusiness(type, device, data),
  );
  late final ThumbnailJobService _mediaJobs = ThumbnailJobService(
    requireConnection: _devices.requireConnection,
    request: _companion.request,
  );
  late final RuntimeSnapshotReader _state = RuntimeSnapshotReader(
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
    activities: _activities,
  );

  static Future<AppComposition> open(
    NativeHost host,
    String dataDirectory,
    ConnectionPolicy policy,
    DiagnosticLog? diagnostics, {
    required void Function(FileShareService?) onSharingOpened,
  }) async {
    // 旧 isolate 的句柄先真实排空，再打开唯一的 Dart 设备与身份所有者。
    await host.recoverConnections();
    final records = await DeviceRecordStorage.open(directory: host.directory);
    DeviceService? devices;
    final identities = await AdbIdentityService.open(
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
    final launches = await AppLaunchJournal.open(directory: host.directory);
    // 读取或清理缓存前先排空旧 isolate 的文档复制，避免与恢复产生并发写入。
    await AppPlatform.recoverDocuments(
      localFiles: createNativeScrcpyLocalFiles,
    );
    final documentSources = Platform.isAndroid
        ? await FileDocumentCache.open(
            cacheDirectory: Directory(
              (await FileDocumentScope.fromEnvironment(
                await AppPlatform.requestPlatform(
                  'documents.platform.environment',
                  const {},
                ),
              )).cacheDirectory,
            ),
          )
        : null;
    final sharing = Platform.isAndroid
        ? await FileShareService.open(
            files: createNativeScrcpyLocalFiles,
            platform: AppPlatform.requestPlatform,
          )
        : null;
    onSharingOpened(sharing);
    final gate = ContentCacheGate();
    late final ContentCache cache;
    FileTransferService? cacheTransfers;
    AppComposition? cacheRuntime;
    final deliveries = await FileDeliveryJournal.open(
      Directory(dataDirectory),
      cacheGate: gate,
      validateSource: (path) => cache.validateDeliveryLocked(path),
    );
    cache = await ContentCache.open(
      root: Directory(dataDirectory),
      gate: gate,
      protectedPaths: () => deliveries.protectedPaths,
      freeBytes: _cacheStorageFreeBytes,
      isDisposed: () => cacheRuntime?.lifecycle.isDisposed ?? false,
      onChanged: () {
        final owner = cacheRuntime;
        if (owner != null && !owner.lifecycle.isDisposed) {
          owner._events.emit({'type': 'media.cache.changed'});
        }
      },
      protectionDetails: () async => [
        for (final source
            in cacheTransfers?.cacheSources ?? <CacheProtection>[])
          source.copyWith(
            sourceLabel:
                records.current.find(source.sourceLabel ?? '')?.name ??
                source.sourceLabel,
          ),
        ...await deliveries.protectedSources,
      ],
    );
    final fileExecutor = AdbFileExecutor(
      localFiles: defaultClient.services,
      resolveConnection: (id) async => devices!.requireConnection(id),
      fileScopeId: host.fileScopeId,
      fileScopeKey: host.fileScopeKey,
    );
    final transfers = await FileTransferService.open(
      executor: fileExecutor,
      cache: cache,
      publication: documentSources == null
          ? sharing
          : FilePublicationLeasePool(
              sharing: sharing,
              documents: documentSources,
            ),
      dataDirectory: Directory(dataDirectory),
    );
    cacheTransfers = transfers;
    final session = AppComposition._(
      dataDirectory: dataDirectory,
      connectionPolicy: policy,
      host: host,
      records: records,
      identities: identities,
      launches: launches,
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
    // 先完成依赖图，构造失败时仍由启动门禁持有宿主与分享的清理责任。
    session.lifecycle;
    cacheRuntime = session;
    return session;
  }

  late final _files = FileOperations(
    search: _fileCatalog,
    gallery: _fileCatalog,
    directories: _fileCatalog,
    mutations: _fileMutations,
    transfers: _transfers,
    sharing: _sharing,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final _mediaOperations = MediaOperations(
    videos: _media,
    audio: _media,
    screenshots: _media,
    quality: _media,
    resizeDisplayCapture: _captures.resizeDisplay,
    emit: _events.emit,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final _deviceOperations = DeviceOperations(
    capabilities: _capabilities,
    observation: _observations,
    calls: _observations,
    notifications: _observations,
    wake: _power.wakeDevice,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final _controlOperations = ControlOperations(
    sessions: _sessions,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final AppLifecycle lifecycle = AppLifecycle(
    host: _host,
    records: _records,
    events: _events,
    stateRecovery: _stateRecovery,
    preferences: _preferences,
    transfers: _transfers,
    fileCatalog: _fileCatalog,
    fileMutations: _fileMutations,
    fileExecutor: _fileExecutor,
    sharing: _sharing,
    platform: _platform,
    background: _background,
    reconnections: _reconnections,
    setup: _setup,
    media: _media,
    devices: _devices,
    observations: _observations,
    health: _health,
    power: _power,
    sessions: _sessions,
    audio: _audio,
    keepAwake: _keepAwake,
    serverQueries: _serverQueries,
    mediaJobs: _mediaJobs,
    companion: _companion,
    artifacts: _artifacts,
    diagnostics: _diagnostics,
  );
  AppDependencies dependencies({required Future<void> Function() close}) {
    return AppDependencies(
      content: _artifacts,
      clipboard: _sessions,
      control: _controlOperations,
      remoteAudio: _mediaOperations,
      videoQuality: _mediaOperations,
      screenshots: _mediaOperations,
      displays: _mediaOperations,
      activities: _activities,
      reconcileState: lifecycle.reconcileState,
      background: _platform,
      devices: _deviceActions,
      connections: _deviceActions,
      setup: _deviceActions,
      inspection: _devices,
      assessment: _deviceOperations,
      observation: _deviceOperations,
      calls: _deviceOperations,
      notifications: _deviceOperations,
      fileSearch: _files,
      directories: _files,
      fileMutations: _files,
      fileTransfers: _files,
      incomingShares: _files,
      documents: _platform,
      gallery: _files,
      apps: apps,
      wake: _deviceOperations,
      appInfo: () => readAppInfo(isClosed: () => lifecycle.isDisposed),
      identity: identity,
      metadata: _preferences,
      settings: _preferences,
      cache: _cache,
      acquireTransferCacheLease: _acquireTransferCacheLease,
      completeDocumentSelection: completeDocumentSelection,
      setVisible: lifecycle.setVisible,
      diagnostics: diagnostics,
      videos: _mediaOperations,
      events: _events.stream,
      close: close,
    );
  }

  Future<String> _acquireTransferCacheLease(String transferId) async {
    if (lifecycle.isDisposed) throw const RequestFailure('disposed', '应用已关闭。');
    return _transfers.acquireCacheLease(transferId);
  }
}

/// 只读查询暂存所在存储的实际可用量，不申请文件复制作用域。
Future<int?> _cacheStorageFreeBytes(String root) async {
  final value = await readNativeScrcpyLocalStorageFreeBytes(root);
  if (value < BigInt.zero || value > BigInt.from(0x7fffffffffffffff)) {
    return null;
  }
  return value.toInt();
}

final class _RuntimeReconnectHost implements DeviceReconnectHost {
  _RuntimeReconnectHost(this.devices, this.state);
  final DeviceService devices;
  final RuntimeSnapshotReader state;
  @override
  Future<ReconnectJson> readSnapshot() => state.readSnapshot();
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
