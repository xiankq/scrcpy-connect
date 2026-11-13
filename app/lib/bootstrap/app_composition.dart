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
import 'package:scrcpy_connect/core/devices/models/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/usb_authorization.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log_provider.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/file_document_platform.dart';
import 'package:scrcpy_connect/core/files/file_resources.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner_provider.dart';
import 'package:scrcpy_connect/core/identity/identity_management_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifecycle.dart';
import 'package:scrcpy_connect/core/lifecycle/app_lifetime.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/media_operations.dart';
import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/media/platform_audio.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/background_policy.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/core/platform/platform_background_control.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_channels.dart';
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
  final _lifetime = AppLifetime();
  bool get _isDisposed => _lifetime.ended;
  late final AppLifecycle lifecycle;
  late final DeviceResources _connections;
  late final AppLaunchJournal _launches;
  late final FileResources _files;

  final DiagnosticLog? diagnostics;
  late final _diagnostics = DiagnosticReporter(diagnostics);
  late final _deviceActions = DeviceActions(
    devices: _connections.devices,
    connections: _connections.devices,
    setup: () => _connections.setup,
    isStateUnverified: () => _stateRecovery.pending,
    prepareChange: _connections.prepareChange,
    beginChange: (change) => _connections.reconnections.beginChange(change),
    cancelContent: _files.cancelContent,
    cancelUsbAttempt: (id) async {
      if (Platform.isAndroid) await _usbAuthorization.cancel(id);
    },
    cancelFiles: _files.cancelFiles,
    forgetObservation: _connections.forgetObservation,
    forgetPreferences: (id) => _preferences.forgetDevicePreferences(id),
    stopMediaIntent: (id) => _media.stopDeviceIntent(id),
    finishMediaStop: (id) => _media.finishDeviceStop(id),
    isDisposed: () => _isDisposed,
    onDisconnectRequested: _events.emitEvent,
    diagnostics: _diagnostics,
  );

  late final _preferences = AppSettings(
    preferences: _host.preferences,
    isDisposed: () => _isDisposed,
    metadata: _connections.metadata,
    applyBackgroundPolicy: (enabled) =>
        _background.apply(enabled, automatic: false),
    onChanged: _events.publishEvent,
  );

  CaptureResources? _captureInstance;
  CaptureResources get _captureResources =>
      _captureInstance ??= CaptureResources(
        scrcpy: _host.scrcpy,
        readServerQueries: () => _connections.serverQueries,
        requireConnection: _connections.devices.requireConnection,
        connectionForDevice: _connections.devices.current,
        records: _connections.records,
        preferences: _preferences,
        launches: _launches,
        diagnostics: _diagnostics,
        isDisposed: () => _isDisposed,
        isStateUnverified: () => _stateRecovery.pending,
        onChanged: _events.publishEvent,
        onCleanupFailure: _events.emitEvent,
      );

  late final _activities = ActivityCatalog(
    diagnostics: _diagnostics,
    readRevision: () => _events.cursor.revision,
    devices: _connections.devices,
    readSessions: ({deviceId}) =>
        _captureResources.readActivitySessions(deviceId: deviceId),
    readAudio: () => _captureInstance?.audioSnapshots() ?? [],
    readObservations: _connections.currentObservations,
    transfers: _files.transfers,
    disconnectDevice: (id) => _deviceActions.disconnectDevice(id),
    stopAudio: (target) => _mediaOperations.stopAudio(target),
    stopObservation: (id) => _connections.operations.stopObservation(id),
    stopVideo: (id) => _mediaOperations.stopVideo(ControlTarget(sessionId: id)),
    isDisposed: () => _isDisposed,
  );

  final String _dataDirectory;

  late final BackgroundPolicy _background = BackgroundPolicy(
    platform: Platform.isAndroid ? _backgroundControl : null,
    audioPolicy: (enabled) async {
      await _media.policy(enabled);
    },
    onEvent: _events.emitEvent,
    isDisposed: () => _isDisposed,
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
    stopConnections: _connections.stopConnections,
    emit: _events.emitEvent,
    handleShare: _files.receiveShare,
    handleMedia: _media.handlePlatformEvent,
  );
  late final RuntimeEvents _events = RuntimeEvents(
    acceptState: ({required sequence, required telemetry}) =>
        _stateRecovery.accept(sequence: sequence, telemetry: telemetry),
    onState: (event) => _diagnostics.applicationEvent(event),
    onLocalStateChanged: () => _stateRecovery.noteLocalStateChange(),
    beforePublish: (event) => _connections.handleEvent(event),
    afterState: (event) {
      _media.handleApplicationEvent(event);
      _captureInstance?.handleApplicationEvent(event);
    },
    handlePlatform: (event) => _platformEvents.handle(event),
    isDisposed: () => _isDisposed,
  );
  late final MediaPlayback _media = MediaPlayback(
    captures: () => _captureResources.capture,
    readCapturedAudio: () async => _captureInstance?.audioSnapshots() ?? [],
    readSnapshot: () => _state.readSnapshot(),
    readSettings: _preferences.read,
    platform: (command, params) => _audioPlatform.request(command, params),
    emit: _events.emitEvent,
    isDisposed: () => _isDisposed,
    requireVerifiedState: () => _stateRecovery.requireVerifiedState(),
    dataDirectory: _dataDirectory,
    capture: () => ScrcpyCaptureAdapter(_host.scrcpy.api),
    diagnostics: diagnostics,
  );
  late final StateRecovery _stateRecovery = StateRecovery(
    read: (current) => _media.snapshot(current),
    emit: (event) {
      _connections.handleRecovery(event);
      _events.emitEvent(event);
    },
    isDisposed: () => _isDisposed,
  );
  late final RuntimeSnapshotReader _state = RuntimeSnapshotReader(
    readCursor: () => _events.cursor,
    readSessions: () => _captureResources.readRecoverySessions(),
    readDevices: () => _connections.devices.readDevices(),
    readAudio: () => _captureInstance?.audioSnapshots() ?? [],
    readShares: () async => await _files.sharing?.readIncomingShares() ?? [],
    readObservations: () => _connections.currentObservations(),
    readSettings: () => _host.preferences.current.values,
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
      scrcpyServerBytes: host.scrcpyBytes,
      burstMode: () => host.preferences.current.values.adbBurstMode,
      policy: policy,
      diagnostics: diagnostics,
      isDisposed: () => session._isDisposed,
      isStateUnverified: () => session._stateRecovery.pending,
      readEventSequence: () => session._events.cursor.sequence,
      readBackgroundKeepAlive: () =>
          host.preferences.current.values.backgroundKeepAlive,
      readSessions: () => session._captureInstance?.currentSessions() ?? [],
      readAudio: () =>
          session._captureInstance?.audioSnapshots(activeOnly: true) ?? [],
      authorizeUsb: Platform.isAndroid
          ? session._usbAuthorization.authorize
          : null,
      cancelUsb: Platform.isAndroid ? session._usbAuthorization.cancel : null,
      onCleanupFailure: session._events.emitEvent,
      onCompanionChanged: session._events.publishEvent,
      onDevicesChanged: session._events.publishEvent,
      onObservationChanged: session._events.publishEvent,
      stopWork: (id, connection, accepted) => Future.wait([
        if (session._captureInstance case final captures?)
          captures.stopForConnection(id, connection),
        session._files.stopForConnection(id, connection, accepted: accepted),
      ], eagerError: true),
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
      localFiles: host.localFiles,
      dataDirectory: dataDirectory,
      records: connections.records,
      requireConnection: (id) => connections.devices.requireConnection(id),
      request: () => session._connections.companion.request,
      isDisposed: () => session._isDisposed,
      isStateUnverified: () => session._stateRecovery.pending,
      diagnostics: DiagnosticReporter(diagnostics),
      onChanged: session._events.publishEvent,
      attachCatalogEvents: (source) => session._events.attachFileEvents(source),
      onSharingOpened: onSharingOpened,
    );
    session.lifecycle = AppLifecycle(
      lifetime: session._lifetime,
      closeHost: host.close,
      connections: connections,
      readCaptures: () => session._captureInstance,
      files: session._files,
      events: session._events,
      stateRecovery: session._stateRecovery,
      preferences: session._preferences,
      platformEvents: Platform.isAndroid ? _channels.events : null,
      readVisible: Platform.isAndroid
          ? session._audioPlatform.readVisible
          : null,
      background: session._background,
      media: session._media,
      diagnostics: session._diagnostics,
    );
    return session;
  }

  late final _mediaOperations = MediaOperations(
    videos: _media,
    audio: _media,
    screenshots: _media,
    quality: _media,
    resizeDisplayCapture: (target, size) =>
        _captureResources.capture.resizeDisplay(target, size),
    onStopRequested: _events.emitEvent,
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
    deviceReaderProvider.overrideWith((ref) => _connections.devices),
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
      (ref) => _files.acquireTransferCacheLease,
    ),
    documentSelectionResponderProvider.overrideWith(
      (ref) => _files.documents.completeSelection,
    ),
    diagnosticLogProvider.overrideWith((ref) => diagnostics),
    videoSessionsProvider.overrideWith((ref) => _mediaOperations),
  ];

  Future<void> configureOutgoingDirectory(String path) =>
      _files.cache.configure(outgoingDirectory: path);
}
