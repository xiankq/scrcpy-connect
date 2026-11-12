import 'dart:async';
import 'dart:io';

import 'package:hooks_riverpod/misc.dart';
import 'package:scrcpy/scrcpy.dart' show createNativeScrcpyLocalFiles;
import 'package:scrcpy_connect/core/activities/activity_catalog.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/capture_resources.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/control_operations.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/core/devices/device_actions.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_resources.dart';
import 'package:scrcpy_connect/core/devices/models/connection_change.dart';
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log_provider.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_resources.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner_provider.dart';
import 'package:scrcpy_connect/core/identity/identity_management_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifecycle.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/media_operations.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/app_platform.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_event_handler.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';
import 'package:scrcpy_connect/core/recovery/runtime_snapshot_reader.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';

/// 组合应用级所有者和功能的延迟绑定；内部资源由所属模块创建与关闭。
final class AppComposition {
  AppComposition._({
    required this._dataDirectory,
    required this._host,
    required this._connections,
    required this._launches,
    required this.diagnostics,
    required this._files,
  });

  final NativeHost _host;
  final DeviceResources _connections;
  final AppLaunchJournal _launches;
  final FileResources _files;

  final DiagnosticLog? diagnostics;
  late final _diagnostics = DiagnosticReporter(diagnostics);
  late final _deviceActions = DeviceActions(
    devices: _connections.devices,
    connections: _connections.devices,
    setup: _connections.setup,
    isStateUnverified: () => _stateRecovery.pending,
    prepareChange: _connections.setup.prepareChange,
    beginChange: _connections.reconnections.beginChange,
    cancelContent: _files.cancelContent,
    cancelUsbAttempt: (id) async {
      if (Platform.isAndroid) await _platform.cancelUsb({'attemptId': id});
    },
    cancelFiles: (id) => lifecycle.cancelDeviceFiles(id),
    forgetObservation: _connections.observations.forget,
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

  late final _preferences = AppSettings(
    preferences: _host.preferences,
    isDisposed: () => lifecycle.isDisposed,
    prepareImport: () => _connections.setup.prepareChange(
      const ConnectionChange(ConnectionChangeKind.replaceRecords),
    ),
    pauseReconnect: () => _connections.reconnections.beginChange(
      const ConnectionChange(ConnectionChangeKind.replaceRecords),
    ),
    records: _connections.records,
    onDevicesImported: (receipt) =>
        _events.publish({'type': 'devices.changed', 'data': receipt.toJson()}),
    applyBackgroundPolicy: (enabled) =>
        _background.apply(enabled, automatic: false),
    onChanged: (preferences) => lifecycle.settingsChanged(preferences),
  );

  late final _captureResources = CaptureResources(
    host: _host,
    devices: _connections.devices,
    records: _connections.records,
    preferences: _preferences,
    launches: _launches,
    diagnostics: _diagnostics,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    publish: _events.publish,
    onCleanupFailure: (error) => _events.emit({
      'type': 'activity.cleanup.failed',
      'data': {'reason': '$error'},
    }),
  );

  late final _activities = ActivityCatalog(
    diagnostics: _diagnostics,
    events: _events,
    devices: _connections.devices,
    captures: _captureResources,
    observations: _connections.observations,
    transfers: _files.transfers,
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
    sharing: _files.sharing,
    documentSources: _files.documentSources,
    deliveries: _files.deliveries,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => lifecycle.isDisposed,
  );
  late final _platformEvents = PlatformEventHandler(
    reconnections: _connections.reconnections,
    isDisposed: () => lifecycle.isDisposed,
    stopConnections: () => Future.wait([
      _connections.setup.stopPending(),
      _connections.devices.stopConnections(),
    ]),
    emit: (event) => _events.emit(event),
    handleShare: _platform.handleShare,
    handleMedia: _media.handlePlatformEvent,
  );
  late final RuntimeEvents _events = RuntimeEvents(
    acceptState: (event) => _stateRecovery.accept(event),
    onState: (event) => _diagnostics.applicationEvent(event),
    onLocalStateChanged: () => _stateRecovery.noteLocalStateChange(),
    beforePublish: (event) => _connections.handleEvent(event),
    afterState: (event) => _media.handleApplicationEvent(event),
    handlePlatform: (event) => _platformEvents.handle(event),
    isDisposed: () => lifecycle.isDisposed,
  );
  late final MediaPlayback _media = MediaPlayback(
    captures: () => _captureResources.capture,
    readCapturedAudio: () async => _captureResources.audioSnapshots(),
    readSnapshot: _state.readSnapshot,
    readSettings: _preferences.read,
    platform: _platform.audioRequest,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => lifecycle.isDisposed,
    requireVerifiedState: () => lifecycle.requireVerifiedState(),
    dataDirectory: _dataDirectory,
    capture: () => ScrcpyCaptureAdapter(_host.scrcpy.api),
    diagnostics: diagnostics,
  );
  late final StateRecovery _stateRecovery = StateRecovery(
    read: _media.snapshot,
    emit: (event) {
      // 恢复回执不是业务变更；直接通知策略，不能重新进入序列核验。
      _connections.handleEvent(event);
      _events.emit(event);
    },
    isDisposed: () => lifecycle.isDisposed,
  );
  bool completeDocumentSelection(String id, Json result) =>
      _platform.documentSelections.complete(id, result);

  late final RuntimeSnapshotReader _state = RuntimeSnapshotReader(
    events: _events,
    captures: _captureResources,
    devices: _connections.devices,
    observations: _connections.observations,
    companion: _connections.companion,
    transfers: _files.transfers,
    preferences: _host.preferences,
    sharing: _files.sharing,
    activities: _activities,
  );

  static Future<AppComposition> open(
    NativeHost host,
    String dataDirectory,
    ConnectionPolicy policy,
    DiagnosticLog? diagnostics, {
    required void Function(FileShareService?) onSharingOpened,
  }) async {
    AppComposition? owner;
    final connections = await DeviceResources.open(
      host: host,
      dataDirectory: dataDirectory,
      policy: policy,
      diagnostics: diagnostics,
      isDisposed: () => owner?.lifecycle.isDisposed ?? false,
      isStateUnverified: () => owner?._stateRecovery.pending ?? false,
      readSnapshot: () => owner!._state.readSnapshot(),
      readSessions: () => owner?._captureResources.currentSessions() ?? [],
      readAudio: () =>
          owner?._captureResources.audioSnapshots(activeOnly: true) ?? [],
      serverQueries: () => owner!._captureResources.serverQueries,
      authorizeUsb: () =>
          Platform.isAndroid ? owner!._platform.authorizeUsb : null,
      cancelUsb: () => Platform.isAndroid ? owner!._platform.cancelUsb : null,
      releaseUsb: () => Platform.isAndroid ? owner!._platform.releaseUsb : null,
      emit: (event) => owner?._events.emit(event),
      publish: (type, device, data) =>
          owner?._events.publishBusiness(type, device, data),
      stopWork: (id, connection, accepted) => Future.wait([
        owner!._captureResources.stopForConnection(id, connection),
        owner._files.stopForConnection(id, connection, accepted: accepted),
      ], eagerError: true),
      stopDisplays: (connection) =>
          owner!._captureResources.stopDisplays(connection),
    );
    final identity = await connections.identities.selectForDevice();
    final defaultClient = await host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    );
    final launches = await AppLaunchJournal.open(directory: host.directory);
    final files = await FileResources.open(
      host: host,
      localFiles: defaultClient.services,
      dataDirectory: dataDirectory,
      records: connections.records,
      requireConnection: (id) => connections.devices.requireConnection(id),
      request: () => owner!._connections.companion.request,
      isDisposed: () => owner?.lifecycle.isDisposed ?? false,
      isStateUnverified: () => owner?._stateRecovery.pending ?? false,
      diagnostics: DiagnosticReporter(diagnostics),
      emit: (event) => owner?._events.emit(event),
      attachCatalogEvents: (source) => owner!._events.attachFileEvents(source),
      onSharingOpened: onSharingOpened,
    );
    final session = AppComposition._(
      dataDirectory: dataDirectory,
      host: host,
      connections: connections,
      launches: launches,
      diagnostics: diagnostics,
      files: files,
    );
    owner = session;
    // 事件可能由 helper 同步交付，先建立观察所有者后再附着界面。
    session._connections.observations;
    // 先完成依赖图，构造失败时仍由启动门禁持有宿主与分享的清理责任。
    session.lifecycle;
    return session;
  }

  late final _mediaOperations = MediaOperations(
    videos: _media,
    audio: _media,
    screenshots: _media,
    quality: _media,
    resizeDisplayCapture: (target, size) =>
        _captureResources.capture.resizeDisplay(target, size),
    emit: _events.emit,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final _controlOperations = ControlOperations(
    sessions: _captureResources.sessions,
    isDisposed: () => lifecycle.isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final AppLifecycle lifecycle = AppLifecycle(
    host: _host,
    connections: _connections,
    captures: _captureResources,
    files: _files,
    events: _events,
    stateRecovery: _stateRecovery,
    preferences: _preferences,
    platform: _platform,
    background: _background,
    media: _media,
    diagnostics: _diagnostics,
  );
  List<Override> overrides({required Future<void> Function() close}) => [
    appSessionProvider.overrideWithValue(
      AppSession(
        events: _events.stream,
        close: close,
        setVisible: lifecycle.setVisible,
        diagnostics: diagnostics,
      ),
    ),
    contentReaderProvider.overrideWith((ref) => _files.content),
    remoteClipboardProvider.overrideWith((ref) => _captureResources.sessions),
    remoteControlProvider.overrideWith((ref) => _controlOperations),
    remoteAudioProvider.overrideWith((ref) => _mediaOperations),
    videoQualityControlProvider.overrideWith((ref) => _mediaOperations),
    videoScreenshotsProvider.overrideWith((ref) => _mediaOperations),
    videoDisplayProvider.overrideWith((ref) => _mediaOperations),
    activityManagementProvider.overrideWith((ref) => _activities),
    reconcileStateProvider.overrideWith((ref) => lifecycle.reconcileState),
    backgroundControlProvider.overrideWith((ref) => _platform),
    deviceManagementProvider.overrideWith((ref) => _deviceActions),
    deviceConnectionsProvider.overrideWith((ref) => _deviceActions),
    deviceSetupProvider.overrideWith((ref) => _deviceActions),
    deviceInspectionProvider.overrideWith((ref) => _connections.devices),
    deviceAssessmentProvider.overrideWith((ref) => _connections.operations),
    deviceObservationProvider.overrideWith((ref) => _connections.operations),
    deviceCallsProvider.overrideWith((ref) => _connections.operations),
    deviceNotificationsProvider.overrideWith((ref) => _connections.operations),
    fileSearchSourceProvider.overrideWith((ref) => _files.operations),
    fileDirectoriesProvider.overrideWith((ref) => _files.operations),
    fileMutationsProvider.overrideWith((ref) => _files.operations),
    fileTransfersProvider.overrideWith((ref) => _files.operations),
    incomingSharesProvider.overrideWith((ref) => _files.operations),
    systemDocumentsProvider.overrideWith((ref) => _platform),
    galleryScannerProvider.overrideWith((ref) => _files.operations),
    deviceAppsProvider.overrideWith((ref) => _connections.apps),
    deviceWakeProvider.overrideWith((ref) => _connections.operations),
    appInfoReaderProvider.overrideWith(
      (ref) =>
          () => readAppInfo(isClosed: () => lifecycle.isDisposed),
    ),
    identityManagementProvider.overrideWith((ref) => _connections.identity),
    metadataManagementProvider.overrideWith((ref) => _preferences),
    settingsManagementProvider.overrideWith((ref) => _preferences),
    contentCacheControlProvider.overrideWith((ref) => _files.cache),
    transferCacheLeaseProvider.overrideWith(
      (ref) => _acquireTransferCacheLease,
    ),
    documentSelectionResponderProvider.overrideWith(
      (ref) => completeDocumentSelection,
    ),
    diagnosticLogProvider.overrideWith((ref) => diagnostics),
    videoSessionsProvider.overrideWith((ref) => _mediaOperations),
  ];

  Future<void> configureOutgoingDirectory(String path) =>
      _files.cache.configure(outgoingDirectory: path);

  Future<String> _acquireTransferCacheLease(String transferId) =>
      _files.acquireTransferCacheLease(transferId);
}
