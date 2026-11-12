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
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
import 'package:scrcpy_connect/core/platform/platform_background_control.dart';
import 'package:scrcpy_connect/core/devices/usb_authorization.dart';
import 'package:scrcpy_connect/core/files/file_document_platform.dart';
import 'package:scrcpy_connect/core/media/platform_audio.dart';
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
    required this.diagnostics,
  });

  final NativeHost _host;
  late final DeviceResources _connections;
  late final AppLaunchJournal _launches;
  late final FileResources _files;

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
      if (Platform.isAndroid) await _usbAuthorization.cancel({'attemptId': id});
    },
    cancelFiles: _files.cancelFiles,
    forgetObservation: _connections.observations.forget,
    forgetPreferences: _preferences.forgetDevicePreferences,
    stopMediaIntent: _media.stopDeviceIntent,
    finishMediaStop: _media.finishDeviceStop,
    isDisposed: () => _isDisposed,
    announceStop: (id) => _events.emit({
      'type': 'device.disconnect.requested',
      'deviceId': id,
      'data': <String, dynamic>{},
    }),
    diagnostics: _diagnostics,
  );

  late final _preferences = AppSettings(
    preferences: _host.preferences,
    isDisposed: () => _isDisposed,
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

  CaptureResources? _captureInstance;
  CaptureResources get _captureResources =>
      _captureInstance ??= CaptureResources(
        scrcpy: _host.scrcpy,
        serverBytes: _host.scrcpyBytes,
        requireConnection: _connections.devices.requireConnection,
        connectionForDevice: _connections.devices.current,
        records: _connections.records,
        preferences: _preferences,
        launches: _launches,
        diagnostics: _diagnostics,
        isDisposed: () => _isDisposed,
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
    isDisposed: () => _isDisposed,
  );

  final String _dataDirectory;

  late final BackgroundPolicy _background = BackgroundPolicy(
    platform: Platform.isAndroid ? _backgroundControl : null,
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

  static const _channels = PlatformChannels();
  late final _backgroundControl = PlatformBackgroundControl(
    request: _channels.request,
    isDisposed: () => _isDisposed,
  );
  late final _usbAuthorization = UsbAuthorization(
    ownerLeaseId: _host.usbOwnerLeaseId,
    request: _channels.requestOptional,
    isDisposed: () => _isDisposed,
  );
  late final _audioPlatform = PlatformAudio(request: _channels.request);
  late final _platformEvents = PlatformEventHandler(
    reconnections: _connections.reconnections,
    isDisposed: () => _isDisposed,
    stopConnections: () => Future.wait([
      _connections.setup.stopPending(),
      _connections.devices.stopConnections(),
    ]),
    emit: (event) => _events.emit(event),
    handleShare: (data) async {
      try {
        await _files.sharing?.receive(data);
      } catch (error) {
        if (!_isDisposed) {
          _events.emit({
            'type': 'sharing.failed',
            'data': {'reason': '$error'},
          });
        }
      }
    },
    handleMedia: _media.handlePlatformEvent,
  );
  late final RuntimeEvents _events = RuntimeEvents(
    acceptState: (event) => _stateRecovery.accept(event),
    onState: (event) => _diagnostics.applicationEvent(event),
    onLocalStateChanged: () => _stateRecovery.noteLocalStateChange(),
    beforePublish: (event) => _connections.handleEvent(event),
    afterState: (event) => _media.handleApplicationEvent(event),
    handlePlatform: (event) => _platformEvents.handle(event),
    isDisposed: () => _isDisposed,
  );
  late final MediaPlayback _media = MediaPlayback(
    captures: () => _captureResources.capture,
    readCapturedAudio: () async => _captureResources.audioSnapshots(),
    readSnapshot: () => _state.readSnapshot(),
    readSettings: _preferences.read,
    platform: (command, params) => _audioPlatform.request(command, params),
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => _isDisposed,
    requireVerifiedState: () => lifecycle.requireVerifiedState(),
    dataDirectory: _dataDirectory,
    capture: () => ScrcpyCaptureAdapter(_host.scrcpy.api),
    diagnostics: diagnostics,
  );
  late final StateRecovery _stateRecovery = StateRecovery(
    read: (current) => _media.snapshot(current),
    emit: (event) {
      // 恢复回执不是业务变更；直接通知策略，不能重新进入序列核验。
      _connections.handleEvent(event);
      _events.emit(event);
    },
    isDisposed: () => _isDisposed,
  );
  bool completeDocumentSelection(String id, Json result) =>
      _files.documents.completeSelection(id, result);

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
    final session = AppComposition._(
      host: host,
      dataDirectory: dataDirectory,
      diagnostics: diagnostics,
    );
    final connections = session._connections = await DeviceResources.open(
      directory: host.directory,
      identities: host.identities,
      recoverConnections: host.recoverConnections,
      drainConnections: host.drainConnections,
      clientForIdentity: (identity) => host.clientForIdentity(
        identityPath: identity.path,
        fingerprint: identity.fingerprint,
      ),
      releaseIdentityClient: (identity) => host.releaseIdentityClient(
        identityPath: identity.path,
        fingerprint: identity.fingerprint,
      ),
      displays: host.physicalDisplays,
      companionBytes: host.companionBytes,
      burstMode: () => host.preferences.current.values.adbBurstMode,
      policy: policy,
      diagnostics: diagnostics,
      isDisposed: () => session._isDisposed,
      isStateUnverified: () => session._stateRecovery.pending,
      readSnapshot: () => session._state.readSnapshot(),
      readSessions: () => session._captureInstance?.currentSessions() ?? [],
      readAudio: () =>
          session._captureInstance?.audioSnapshots(activeOnly: true) ?? [],
      serverQueries: () => session._captureResources.serverQueries,
      authorizeUsb: Platform.isAndroid
          ? (params) => session._usbAuthorization.authorize(params)
          : null,
      cancelUsb: Platform.isAndroid
          ? (params) => session._usbAuthorization.cancel(params)
          : null,
      releaseUsb: Platform.isAndroid
          ? (params) => session._usbAuthorization.release(params)
          : null,
      emit: (event) => session._events.emit(event),
      publish: (type, device, data) =>
          session._events.publishBusiness(type, device, data),
      stopWork: (id, connection, accepted) => Future.wait([
        if (session._captureInstance case final captures?)
          captures.stopForConnection(id, connection),
        session._files.stopForConnection(id, connection, accepted: accepted),
      ], eagerError: true),
    );
    final identity = await connections.identities.selectForDevice();
    final defaultClient = await host.clientForIdentity(
      identityPath: identity.path,
      fingerprint: identity.fingerprint,
    );
    session._launches = await AppLaunchJournal.open(directory: host.directory);
    session._files = await FileResources.open(
      fileScopeId: host.fileScopeId,
      fileScopeKey: host.fileScopeKey,
      documentPlatform: FileDocumentPlatform(
        files: createNativeScrcpyLocalFiles,
        request: _channels.request,
        isDisposed: () => session._isDisposed,
      ),
      localFiles: defaultClient.services,
      dataDirectory: dataDirectory,
      records: connections.records,
      requireConnection: (id) => connections.devices.requireConnection(id),
      request: () => session._connections.companion.request,
      isDisposed: () => session._isDisposed,
      isStateUnverified: () => session._stateRecovery.pending,
      diagnostics: DiagnosticReporter(diagnostics),
      emit: (event) => session._events.emit(event),
      attachCatalogEvents: (source) => session._events.attachFileEvents(source),
      onSharingOpened: onSharingOpened,
    );
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
    isDisposed: () => _isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  late final _controlOperations = ControlOperations(
    sessions: _captureResources.sessions,
    isDisposed: () => _isDisposed,
    isStateUnverified: () => _stateRecovery.pending,
    diagnostics: _diagnostics,
  );
  AppLifecycle? _lifecycle;
  bool get _isDisposed => _lifecycle?.isDisposed ?? false;
  AppLifecycle get lifecycle => _lifecycle ??= AppLifecycle(
    closeHost: _host.close,
    connections: _connections,
    readCaptures: () => _captureInstance,
    files: _files,
    events: _events,
    stateRecovery: _stateRecovery,
    preferences: _preferences,
    platformEvents: Platform.isAndroid ? _channels.events : null,
    readVisible: Platform.isAndroid ? _audioPlatform.readVisible : null,
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
    backgroundControlProvider.overrideWith((ref) => _backgroundControl),
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
    systemDocumentsProvider.overrideWith((ref) => _files.documents),
    galleryScannerProvider.overrideWith((ref) => _files.operations),
    deviceAppsProvider.overrideWith((ref) => _connections.apps),
    deviceWakeProvider.overrideWith((ref) => _connections.operations),
    appInfoReaderProvider.overrideWith(
      (ref) =>
          () => readAppInfo(isClosed: () => _isDisposed),
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
