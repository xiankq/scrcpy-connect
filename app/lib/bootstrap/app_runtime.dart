import '../core/media/video_sessions.dart';
import '../core/media/video_output.dart';
import '../core/control/video_session.dart';
import '../core/control/session_activity.dart';

import 'package:scrcpy_connect/core/control/video_display.dart';

import 'package:scrcpy_connect/core/media/video_screenshot.dart';

import 'package:scrcpy_connect/core/control/video_quality.dart';

import 'package:scrcpy_connect/core/application/activities.dart';

import 'package:scrcpy_connect/core/media/audio_sources.dart';

import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_cancellation.dart';
import 'package:scrcpy_connect/core/files/file_directory.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scan.dart';
import 'package:scrcpy_connect/core/files/file_failure.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_apps_reader.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/companion/companion_exception.dart';
import 'package:scrcpy_connect/core/devices/device_observation.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/application/device_lifecycle.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/core/settings/preference_codec.dart';
import 'package:scrcpy_connect/core/identity/identity_manager.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart';
import 'package:scrcpy_connect/core/application/application_activities.dart';
import 'package:scrcpy_connect/core/platform/application_info.dart';
import 'package:scrcpy_connect/core/devices/connection_change.dart';

import 'package:scrcpy_connect/core/diagnostics/diagnostic_record.dart';

import 'package:scrcpy_connect/core/content/content_cache_gate.dart';
import 'package:scrcpy_connect/core/files/file_document_scope.dart';
import 'package:scrcpy_connect/core/companion/companion_config.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';

import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart';
import 'package:scrcpy_connect/core/settings/app_settings.dart';
import 'package:scrcpy_connect/core/files/file_delivery_journal.dart';
import 'package:scrcpy_connect/core/files/file_document_cache.dart';
import 'package:scrcpy_connect/core/files/file_publication_lease_pool.dart';

import 'package:scrcpy/scrcpy.dart'
    show createNativeScrcpyLocalFiles, readNativeScrcpyLocalStorageFreeBytes;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';

import 'package:scrcpy_connect/core/control/media_capture.dart';
import 'package:scrcpy_connect/core/control/scrcpy_capture_adapter.dart';

import 'package:scrcpy_connect/core/media/media_playback.dart';
import 'package:scrcpy_connect/core/application/state_recovery.dart';

import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/files/file_catalog.dart';
import 'package:scrcpy_connect/core/files/file_mutation_service.dart';
import 'package:scrcpy_connect/core/files/file_share_service.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

import 'package:scrcpy_connect/utils/ordered_disposal.dart';
import 'package:scrcpy_connect/core/platform/native_host.dart';
import 'package:scrcpy_connect/core/application/application_snapshot_reader.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/devices/device_power_service.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/companion/companion_service.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/content/thumbnail_job_service.dart';
import 'package:scrcpy_connect/core/media/device_audio_service.dart';
import 'package:scrcpy_connect/core/platform/application_platform.dart';
import 'package:scrcpy_connect/core/platform/application_background_policy.dart';
import 'package:scrcpy_connect/core/platform/application_platform_events.dart';
import 'package:scrcpy_connect/core/application/application_events.dart';
import 'package:scrcpy_connect/core/files/adb_file_executor.dart';

import 'package:scrcpy_connect/core/devices/connection_policy.dart';
import 'package:scrcpy_connect/core/devices/device_connection_service.dart';
import 'package:scrcpy_connect/core/devices/device_capability_policy.dart';
import 'package:scrcpy_connect/core/devices/device_capability_facts_reader.dart';
import 'package:scrcpy_connect/core/devices/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/core/devices/device_reconnect_service.dart';

import 'package:scrcpy_connect/core/devices/device_health_service.dart';
import 'package:scrcpy_connect/core/devices/device_discovery.dart';
import 'package:scrcpy_connect/core/identity/adb_identity_service.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/companion/companion_recovery.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/control_session_service.dart';
import 'package:scrcpy_connect/core/control/device_wake_service.dart';

/// 按应用生命周期组装独立设备能力；ADB 传输与媒体解码由各自的包负责。
class AppRuntime
    implements
        RemoteAudio,
        VideoSessions,
        VideoDisplayControl,
        VideoScreenshots,
        VideoQualityControl,
        ActivityManagement,
        DeviceWake,
        RemoteControl,
        DeviceAssessment,
        DeviceObservation,
        DeviceCalls,
        DeviceNotifications,
        FileSearch,
        GalleryScanner,
        FileDirectories,
        FileMutations,
        FileTransfers,
        IncomingShares {
  AppRuntime._({
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

  final NativeHost _host;
  final DeviceRecordStorage _records;
  final AdbIdentityService _identities;
  final AppLaunchJournal _launches;
  final AdbClient _defaultClient;
  final FileTransferService _transfers;
  final AdbFileExecutor _fileExecutor;
  late final _fileCatalog = FileCatalog(_fileExecutor);
  late final _fileMutations = FileMutationService(_fileExecutor);
  final ContentCache _cache;
  final FileDeliveryJournal _deliveries;
  final FileShareService? _sharing;
  final FileDocumentCache? _documentSources;

  final DiagnosticLog? diagnostics;
  Future<AdbClient> get adb => Future.value(_defaultClient);
  late final _diagnostics = DiagnosticReporter(diagnostics);
  late final _artifacts = ContentPreview(
    cache: _cache,
    executor: _fileExecutor,
    jobs: _mediaJobs,
    isDisposed: () => _disposed,
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
    publishDevices: () => _publishBusiness('devices.changed', null, {
      'devices': _devices.projectDevices(),
    }),
    isDisposed: () => _disposed,
  );
  MetadataManagement get metadata => _preferences;
  SettingsManagement get settings => _preferences;
  ContentReader get content => _artifacts;
  RemoteClipboard get clipboard => _sessions;
  BackgroundControl get background => _platform;
  late final _deviceLifecycle = DeviceLifecycle(
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
    cancelFiles: _cancelDeviceFiles,
    forgetObservation: _observations.forget,
    forgetPreferences: _preferences.forgetDevicePreferences,
    stopMediaIntent: _media.stopDeviceIntent,
    finishMediaStop: _media.finishDeviceStop,
    isDisposed: () => _disposed,
    announceStop: (id) => _events.emit({
      'type': 'device.disconnect.requested',
      'deviceId': id,
      'data': <String, dynamic>{},
    }),
    diagnostics: _diagnostics,
  );

  DeviceManagement get deviceManagement => _deviceLifecycle;
  DeviceConnectionControl get connections => _deviceLifecycle;
  DeviceSetup get setup => _deviceLifecycle;
  DeviceInspection get inspection => _devices;
  late final DeviceApps apps = DeviceAppsReader(
    requireConnection: _devices.requireConnection,
    currentConnection: _devices.current,
    connectionId: (id) => _devices.readDevice(id).connectionId,
    serverQueries: _serverQueries,
    companion: _companion,
    isDisposed: () => _disposed,
    onFailure: _diagnostics.appCatalogFailed,
  );
  DeviceAssessment get assessment => this;

  @override
  Future<DeviceCapabilities> readCapabilities(
    String deviceId, {
    AdbCancellation? cancellation,
  }) {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    return _capabilities.readCapabilities(deviceId, cancellation: cancellation);
  }

  @override
  Future<DeviceDiagnosis> diagnoseDevice(
    String deviceId, {
    AdbCancellation? cancellation,
  }) {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    return _capabilities.diagnoseDevice(deviceId, cancellation: cancellation);
  }

  GalleryScanner get gallery => this;

  @override
  Future<GalleryScanSnapshot> startScan(String deviceId, {int limit = 100}) =>
      _fileOperation(
        'media.list',
        deviceId,
        () => _fileCatalog.startScan(deviceId, limit: limit),
      );

  @override
  Future<GalleryScanSnapshot> readScan(
    GalleryScanTarget target, {
    int offset = 0,
    int limit = 100,
  }) => _fileOperation(
    'media.list',
    target.deviceId,
    () => _fileCatalog.readScan(target, offset: offset, limit: limit),
  );

  @override
  Future<GalleryScanSnapshot> cancelScan(GalleryScanTarget target) =>
      _fileOperation(
        'media.scan.cancel',
        target.deviceId,
        () => _fileCatalog.cancelScan(target),
      );

  FileDirectories get directories => this;

  @override
  Future<FileDirectorySnapshot> readDirectory(
    FileDirectoryTarget target, {
    FileCatalogFilter filter = .all,
    FileDirectorySort sort = .name,
    bool descending = false,
    int offset = 0,
    int limit = 10000,
    FileCancellation? cancellation,
  }) => _fileOperation(
    'files.list',
    target.deviceId,
    () => _fileCatalog.readDirectory(
      target,
      filter: filter,
      sort: sort,
      descending: descending,
      offset: offset,
      limit: limit,
      cancellation: cancellation,
    ),
  );

  FileTransfers get fileTransfers => this;

  @override
  Future<FileTransferCollection> readTransfers() =>
      _fileOperation('transfers.list', null, _transfers.readTransfers);

  @override
  Future<FileTransferSnapshot> readTransfer(String id) => _fileOperation(
    'transfers.get',
    null,
    () => _transfers.readTransfer(id),
    transferId: id,
  );

  @override
  Future<FileTransferSubmission> startTransfer(
    FileTransferPlan plan, {
    String? shareId,
  }) => _fileOperation(
    'files.${plan.direction.name}',
    plan.deviceId,
    () => _transfers.startTransfer(plan, shareId: shareId),
    requiresVerifiedState: true,
  );

  @override
  Future<void> cancelTransfer(FileTransferTarget target) => _fileOperation(
    'transfers.cancel',
    null,
    () => _transfers.cancelTransfer(target),
    transferId: target.id,
  );

  @override
  Future<FileTransferSnapshot> resolveConflict(
    String id,
    FileTransferConflict policy, {
    bool applyToAll = false,
  }) => _fileOperation(
    'transfers.resolve',
    null,
    () => _transfers.resolveConflict(id, policy, applyToAll: applyToAll),
    transferId: id,
    requiresVerifiedState: true,
  );

  @override
  Future<FileTransferSnapshot> restartTransfer(
    String id, {
    FileTransferConflict? policy,
    bool applyToAll = false,
  }) => _fileOperation(
    'transfers.resume',
    null,
    () =>
        _transfers.restartTransfer(id, policy: policy, applyToAll: applyToAll),
    transferId: id,
    requiresVerifiedState: true,
  );

  @override
  Future<List<String>> removeTransfer(FileTransferTarget target) =>
      _fileOperation(
        'transfers.remove',
        null,
        () => _transfers.removeTransfer(target),
        transferId: target.id,
      );

  SystemDocuments get documents => _platform;

  IncomingShares get incomingShares => this;

  @override
  Future<List<IncomingShare>> readIncomingShares() => _fileOperation(
    'sharing.pending',
    null,
    () async => await _sharing?.readIncomingShares() ?? [],
  );

  @override
  Future<void> consumeShare(String id) =>
      _fileOperation('sharing.consume', null, () async {
        final sharing = _sharing;
        if (sharing == null) {
          throw const RequestFailure('platform_unavailable', '此宿主不支持接收系统分享。');
        }
        await sharing.consumeShare(id);
      });

  FileMutations get fileMutations => this;

  @override
  Future<void> createDirectory(String deviceId, String path) => _fileOperation(
    'files.mkdir',
    deviceId,
    () => _fileMutations.createDirectory(deviceId, path),
    requiresVerifiedState: true,
  );

  @override
  Future<void> rename(
    String deviceId,
    FileMutationSelection source, {
    required String destination,
  }) => _fileOperation(
    'files.rename',
    deviceId,
    () => _fileMutations.rename(deviceId, source, destination: destination),
    requiresVerifiedState: true,
  );

  @override
  Future<void> delete(String deviceId, List<FileMutationSelection> sources) =>
      _fileOperation(
        'files.delete',
        deviceId,
        () => _fileMutations.delete(deviceId, sources),
        requiresVerifiedState: true,
      );

  FileSearch get fileSearch => this;

  @override
  Future<FileSearchSnapshot> startSearch(
    String deviceId, {
    required String path,
    required String query,
    FileCatalogFilter filter = .all,
  }) => _fileOperation(
    'files.search.start',
    deviceId,
    () => _fileCatalog.startSearch(
      deviceId,
      path: path,
      query: query,
      filter: filter,
    ),
  );

  @override
  Future<FileSearchSnapshot> readSearch(
    FileSearchTarget target, {
    int offset = 0,
    int limit = 500,
  }) => _fileOperation(
    'files.search.get',
    target.deviceId,
    () => _fileCatalog.readSearch(target, offset: offset, limit: limit),
  );

  @override
  Future<void> cancelSearch(FileSearchTarget target) => _fileOperation(
    'files.search.cancel',
    target.deviceId,
    () => _fileCatalog.cancelSearch(target),
  );

  VideoDisplayControl get displays => this;
  @override
  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size) =>
      _videoOperation(
        'session.display',
        target.deviceId,
        () => _captures.resizeDisplay(target, size),
        sessionId: target.sessionId,
        verified: true,
      );

  VideoScreenshots get screenshots => this;
  @override
  Future<VideoScreenshot> captureScreenshot(String sessionId) =>
      _videoOperation(
        'session.screenshot',
        null,
        () => _media.captureScreenshot(sessionId),
        sessionId: sessionId,
      );

  VideoQualityControl get videoQuality => this;
  @override
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) =>
      _videoOperation(
        'session.quality.options',
        deviceId,
        () => _media.readVideoQualityOptions(deviceId),
      );
  @override
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) => _videoOperation(
    'session.quality',
    deviceId,
    () => _media.changeVideoQuality(deviceId, patch),
    verified: true,
  );

  Future<T> _videoOperation<T>(
    String label,
    String? deviceId,
    Future<T> Function() action, {
    bool verified = false,
    String? sessionId,
  }) async {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    for (final id in [?deviceId, ?sessionId]) {
      if (id.isEmpty || id.contains('\u0000')) {
        throw const RequestFailure('invalid_argument', '画面身份无效。');
      }
    }
    if (verified && _stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    final details = {'deviceId': ?deviceId, 'sessionId': ?sessionId};
    try {
      final result = await action();
      _diagnostics.command(label, details, watch.elapsedMilliseconds);
      return result;
    } catch (error, stack) {
      final failure = error is AdbException
          ? RequestFailure(error.code, error.message)
          : error;
      _diagnostics.command(
        label,
        details,
        watch.elapsedMilliseconds,
        error: failure,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  RemoteAudio get remoteAudio => this;
  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({String? deviceId}) =>
      _audioOperation(
        'audio.sources',
        deviceId,
        () => _media.readAudioSources(deviceId: deviceId),
      );
  @override
  Future<Set<String>> readAudioEligibleDevices() => _audioOperation(
    'audio.eligibility',
    null,
    _media.readAudioEligibleDevices,
  );
  @override
  Future<DeviceAudioPlayback> startAudio(String deviceId) => _audioOperation(
    'audio.start',
    deviceId,
    () => _media.startAudio(deviceId),
    verified: true,
  );
  @override
  Future<void> stopAudio(DeviceAudioTarget target) => _audioOperation(
    'audio.stop',
    target.deviceId,
    () => _media.stopAudio(target),
    sourceId: target.sourceId,
  );
  @override
  Future<DeviceAudioPlayback> pauseAudio(DeviceAudioTarget target) =>
      _audioOperation(
        'audio.pause',
        target.deviceId,
        () => _media.pauseAudio(target),
        sourceId: target.sourceId,
      );
  @override
  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target) =>
      _audioOperation(
        'audio.resume',
        target.deviceId,
        () => _media.resumeAudio(target),
        sourceId: target.sourceId,
        verified: true,
      );
  @override
  Future<DeviceAudioPlayback> changeAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  }) => _audioOperation(
    'audio.volume',
    target.deviceId,
    () => _media.changeAudioVolume(target, volume: volume, muted: muted),
    sourceId: target.sourceId,
  );

  Future<T> _audioOperation<T>(
    String label,
    String? deviceId,
    Future<T> Function() action, {
    String? sourceId,
    bool verified = false,
  }) async {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    if (deviceId != null && (deviceId.isEmpty || deviceId.contains('\u0000')) ||
        sourceId != null && (sourceId.isEmpty || sourceId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '声音来源身份无效。');
    }
    if (verified && _stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    final details = {'deviceId': ?deviceId, 'sourceId': ?sourceId};
    try {
      final result = await action();
      _diagnostics.command(label, details, watch.elapsedMilliseconds);
      return result;
    } catch (error, stack) {
      final failure = error is AdbException
          ? RequestFailure(error.code, error.message)
          : error;
      _diagnostics.command(
        label,
        details,
        watch.elapsedMilliseconds,
        error: failure,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  Future<T> _fileOperation<T>(
    String label,
    String? deviceId,
    Future<T> Function() action, {
    bool requiresVerifiedState = false,
    String? transferId,
  }) async {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    if (deviceId != null && (deviceId.isEmpty || deviceId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '请指定设备。');
    }
    if (transferId != null &&
        (transferId.isEmpty || transferId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '请指定传输任务。');
    }
    if (requiresVerifiedState && _stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await action();
    } catch (error, stack) {
      final failure = switch (error) {
        FileFailure(:final code, :final message) ||
        AdbException(
          :final code,
          :final message,
        ) => RequestFailure(code, message),
        DeviceRecordsFailure(:final code, :final message, :final details) =>
          RequestFailure(code, message, details),
        _ => error,
      };
      _diagnostics.fileOperationFailed(
        label,
        deviceId,
        failure,
        watch.elapsedMilliseconds,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  DeviceNotifications get notifications => this;

  @override
  Future<DeviceNotificationsSnapshot> readNotifications(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'notifications.list',
    () => _observations.readNotifications(deviceId, cancellation: cancellation),
    deviceId: deviceId,
  );

  @override
  Future<DeviceNotificationOpening> openNotification(
    String deviceId,
    String notificationId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'notifications.open',
    () => _observations.openNotification(
      deviceId,
      notificationId,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    requiresVerifiedState: true,
  );

  @override
  Future<bool> dismissNotification(
    String deviceId,
    String notificationId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'notifications.dismiss',
    () => _observations.dismissNotification(
      deviceId,
      notificationId,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    requiresVerifiedState: true,
  );

  DeviceCalls get calls => this;

  @override
  Future<DeviceCallsSnapshot> readCalls(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'calls.list',
    () => _observations.readCalls(deviceId, cancellation: cancellation),
    deviceId: deviceId,
  );

  @override
  Future<void> requestCurrentCallUi(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'calls.open',
    () => _observations.requestCurrentCallUi(
      deviceId,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    requiresVerifiedState: true,
  );

  @override
  Future<void> requestPhoneApp(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'calls.openPhoneApp',
    () => _observations.requestPhoneApp(deviceId, cancellation: cancellation),
    deviceId: deviceId,
    requiresVerifiedState: true,
  );

  DeviceObservation get observation => this;

  @override
  Future<List<DeviceObservationSnapshot>> readObservations({
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.list',
    () => _observations.readObservations(cancellation: cancellation),
  );

  @override
  Future<DeviceObservationSnapshot> readObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.status',
    () => _observations.readObservation(deviceId, cancellation: cancellation),
    deviceId: deviceId,
  );

  @override
  Future<DeviceObservationSnapshot> startObservation(
    String deviceId, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.start',
    () => _observations.startObservation(
      deviceId,
      allowStart: allowStart,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    requiresVerifiedState: true,
  );

  @override
  Future<DeviceObservationSnapshot> stopObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.stop',
    () => _observations.stopObservation(deviceId, cancellation: cancellation),
    deviceId: deviceId,
  );

  Future<T> _observationOperation<T>(
    String diagnosticLabel,
    Future<T> Function() action, {
    String? deviceId,
    bool requiresVerifiedState = false,
  }) async {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    if (deviceId != null && (deviceId.isEmpty || deviceId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '请指定设备。');
    }
    // 状态核验先于改变观察意图或执行通知、电话动作。
    if (requiresVerifiedState && _stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await action();
    } catch (error, stack) {
      final failure = switch (error) {
        CompanionException(:final code, :final message) ||
        AdbException(
          :final code,
          :final message,
        ) => RequestFailure(code, message),
        DeviceRecordsFailure(:final code, :final message, :final details) =>
          RequestFailure(code, message, details),
        _ => error,
      };
      _diagnostics.observationFailed(
        diagnosticLabel,
        deviceId,
        failure,
        watch.elapsedMilliseconds,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  RemoteControl get control => this;

  @override
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  ) async {
    if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
    // 保留结构拒绝先于状态屏障的顺序；范围与原生执行仍由捕获所有者核验。
    for (final value in [?target.sessionId, ?target.deviceId]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw const RequestFailure('invalid_argument', '控制目标无效。');
      }
    }
    if (action.isInput && target.captureGeneration == null) {
      throw const RequestFailure('invalid_argument', '缺少捕获代际。');
    }
    if (_stateRecovery.pending && needsVerifiedControl(target, action)) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await _sessions.sendControl(target, action);
    } catch (error) {
      _diagnostics.controlFailed(
        target,
        action,
        error,
        watch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  @override
  Future<DeviceWakeReceipt> wakeDevice(
    String id, {
    String? connectionId,
  }) async {
    if (_disposed) throw const RequestFailure('disposed', '应用已关闭。');
    if (id.isEmpty ||
        id.contains('\u0000') ||
        connectionId != null &&
            (connectionId.isEmpty || connectionId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '设备或连接标识无效。');
    }
    if (_stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await _power.wakeDevice(id, connectionId: connectionId);
    } catch (error) {
      _diagnostics.deviceWakeFailed(id, error, watch.elapsedMilliseconds);
      rethrow;
    }
  }

  Future<ApplicationInfo> applicationInfo() =>
      readApplicationInfo(isClosed: () => _disposed);
  ContentCacheControl get cache => _cache;
  Future<String> acquireTransferCacheLease(String transferId) async {
    if (_disposed) throw const RequestFailure('disposed', '应用已关闭。');
    return _transfers.acquireCacheLease(transferId);
  }

  late final _preferences = AppSettings(
    preferences: _host.preferences,
    isDisposed: () => _disposed,
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
    onChanged: (preferences) {
      if (_disposed) return;
      final settings = PreferenceCodec.encode(preferences);
      _reconnections.updateBackgroundKeepAlive(preferences.backgroundKeepAlive);
      _events.publish({'type': 'settings.changed', 'data': settings});
      _observeCleanup(
        _keepAwake.settingsChanged(
          _records.current.devices.map((record) => record.id),
        ),
      );
    },
  );
  Future<void> _cancelDeviceFiles(String deviceId) async {
    await Future.wait([
      _fileCatalog.cancelDevice(deviceId),
      _fileMutations.cancelDevice(deviceId),
      _transfers.cancelDevice(deviceId),
    ]);
  }

  late final _captures = MediaCapture(
    sessions: _sessions,
    audio: _audio,
    keepAwake: _keepAwake,
    connectionForDevice: _devices.current,
    preferences: _preferences,
    scrcpy: _host.scrcpy,
  );

  ActivityManagement get activities => this;
  @override
  Future<ActivityCollection> readActivities({String? deviceId}) =>
      _activityOperation(
        'activities.list',
        () => _activities.readActivities(deviceId: deviceId),
      );
  @override
  Future<void> stopActivity(ActivityTarget target) => _activityOperation(
    'activities.stop',
    () => _activities.stopActivity(target),
  );

  Future<T> _activityOperation<T>(
    String label,
    Future<T> Function() action,
  ) async {
    final watch = Stopwatch()..start();
    try {
      return await action();
    } catch (error, stack) {
      final failure = error is AdbException
          ? RequestFailure(error.code, error.message)
          : error;
      _diagnostics.command(
        label,
        const {},
        watch.elapsedMilliseconds,
        error: failure,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  late final _activities = ApplicationActivities(
    events: _events,
    devices: _devices,
    sessions: _sessions,
    observations: _observations,
    audio: _audio,
    transfers: _transfers,
    disconnectDevice: (id) => _deviceLifecycle.disconnectDevice(id),
    stopAudio: (target) => _media.stopAudio(target),
    stopVideo: (id) async {
      _events.emit({
        'type': 'session.stop.requested',
        'data': {'sessionId': id},
      });
      await _media.stopVideo(ControlTarget(sessionId: id));
    },
    isDisposed: () => _disposed,
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

  late final ApplicationBackgroundPolicy _background =
      ApplicationBackgroundPolicy(
        platform: Platform.isAndroid ? _platform : null,
        audioPolicy: (enabled) async {
          await _media.policy(enabled);
        },
        onChanged: (status) => _events.emit({
          'type': 'background.changed',
          'data': status.toJson(),
        }),
        onFailure: (error) => _events.emit({
          'type': 'background.failed',
          'data': {'reason': '$error'},
        }),
      );

  late final ApplicationPlatform _platform = ApplicationPlatform(
    usbOwnerLeaseId: _host.usbOwnerLeaseId,
    localFiles: createNativeScrcpyLocalFiles,
    sharing: _sharing,
    documentSources: _documentSources,
    deliveries: _deliveries,
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
  Future<void> setVisible(bool visible) async {
    if (_disposed) return;
    _reconnections.setVisible(visible);
    if (!Platform.isAndroid) await _media.setVisible(visible);
  }

  bool _disposed = false;
  Future<void>? _shuttingDown;
  late final MediaPlayback _media = MediaPlayback(
    captures: _captures,
    readSnapshot: _state.readSnapshot,
    readSettings: _preferences.read,
    platform: _platform.audioRequest,
    emit: (event) {
      _events.emit(event);
    },
    isDisposed: () => _disposed,
    requireVerifiedState: _verifyState,
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
  late final DeviceService _devices = DeviceService(
    records: _records,
    identities: _identities,
    reconnectionCandidates: DeviceReconnectionCandidates.mdns(_discovery),
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
    burstMode: () => _host.preferences.current.values.adbBurstMode,
    emit: (type, data) => _publishBusiness(type, null, data),
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
      if (_disposed) throw const RequestFailure('disposed', '连接界面已关闭。');
      if (_stateRecovery.pending) {
        throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
      }
    },
    serverQueries: _serverQueries,
    settings: () => _host.preferences.current.values,
    emit: _publishBusiness,
    onAudioEligibilityChanged: (id) {
      // 同步撤准入后记录实际排空，回调不等待其他设备，也不丢弃失败所有者。
      _observeCleanup(_audio.eligibilityChanged(id));
      _observeCleanup(_keepAwake.windowsChanged(id));
    },
  );
  late final DeviceAudioService _audio = DeviceAudioService(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    hasAudioOwner: _sessions.hasAudioOwner,
    deviceName: (id) => _records.current.find(id)?.name ?? 'Android 设备',
    apiLevel: (id) => _records.current.find(id)?.apiLevel,
    emit: _publishBusiness,
  );
  late final DeviceWakeService _keepAwake = DeviceWakeService(
    scrcpy: _host.scrcpy,
    requireConnection: _devices.requireConnection,
    hasWindowOwner: _sessions.hasAudioOwner,
    keepAwakeEnabled: (deviceId) =>
        _host.preferences.current.values.deviceSettings[deviceId]?.stayAwake ==
        true,
    emit: _publishBusiness,
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
    emit: _publishBusiness,
  );
  late final DeviceObservationService _observations = DeviceObservationService(
    companion: _companion,
    records: _records,
    emit: _publishBusiness,
  );
  late final ThumbnailJobService _mediaJobs = ThumbnailJobService(
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
          ? _keepAwake.projectSession(data)
          : data,
    });
    if (type == 'device.keep_active.updated' && device != null) {
      _publishKeepAwake(device);
    }
  }

  void _publishKeepAwake(String device) {
    for (final session in _sessions.currentSessions(deviceId: device)) {
      _publishBusiness('session.updated', device, session.toSnapshot());
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
    activities: _activities,
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

  static Future<AppRuntime>? _initializing;
  static String? _initializingDirectory;
  static String? _initializingPolicyJson;
  static String? _initializingBinaryDirectory;
  static AppRuntime? _active;
  // 组装尚未交付给 Session 时也保留精确分享所有者，关闭失败由下次启动重试。
  static FileShareService? _startingSharing;
  static NativeHost? _startingHost;

  static Future<AppRuntime> initialize({
    required String dataDirectory,
    Directory? adbBinaryDirectory,
    ConnectionPolicy connectionPolicy = const ConnectionPolicy(),
    DiagnosticLog? diagnostics,
  }) {
    if (_active case final existing? when !existing._disposed) {
      return Future.error(
        const RequestFailure(
          'application_already_initialized',
          '此引擎已有应用会话，请复用现有实例。',
        ),
      );
    }
    if (_initializing != null && _initializingDirectory != dataDirectory) {
      return Future.error(
        const RequestFailure(
          'runtime_directory_mismatch',
          '应用正在使用另一个私有目录，请重新启动应用。',
        ),
      );
    }
    final policyJson = jsonEncode(connectionPolicy.toJson());
    if (_initializing != null && _initializingPolicyJson != policyJson) {
      return Future.error(
        const RequestFailure(
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
        const RequestFailure(
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

  static Future<AppRuntime> _initialize(
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
    final host = await NativeHost.attach(
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

  static Future<AppRuntime> _assemble(
    NativeHost host,
    String dataDirectory,
    ConnectionPolicy policy,
    DiagnosticLog? diagnostics,
  ) async {
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
    await ApplicationPlatform.recoverDocuments(
      localFiles: createNativeScrcpyLocalFiles,
    );
    final documentSources = Platform.isAndroid
        ? await FileDocumentCache.open(
            cacheDirectory: Directory(
              (await FileDocumentScope.fromEnvironment(
                await ApplicationPlatform.requestPlatform(
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
            platform: ApplicationPlatform.requestPlatform,
          )
        : null;
    _startingSharing = sharing;
    final gate = ContentCacheGate();
    late final ContentCache cache;
    FileTransferService? cacheTransfers;
    AppRuntime? cacheRuntime;
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
      isDisposed: () => cacheRuntime?._disposed ?? false,
      onChanged: () {
        final owner = cacheRuntime;
        if (owner != null && !owner._disposed) {
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
    final session = AppRuntime._(
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
    cacheRuntime = session;
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
    final settings = await _preferences.read();
    final backgroundStatus = await _background.apply(
      settings.backgroundKeepAlive,
      automatic: true,
    );
    // 恢复快照安排连接前先应用宿主的显式或系统停止状态，之后仍允许手动连接。
    if (backgroundStatus?.stopped == true) {
      _reconnections.stopAutomaticConnections();
    }
    // 由已挂载的应用视图报告可见性，首次报告前不安排自动重连。
    _reconnections.setVisible(false);
    // 可信快照先建立屏幕偏好和旧连接身份，再允许第一次自动重连。
    await _stateRecovery.refresh();
    await _reconnections.start();
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> reconcileState() async {
    if (_disposed) {
      throw const RequestFailure('disposed', '连接界面已关闭。');
    }
    final watch = Stopwatch()..start();
    try {
      await _stateRecovery.refresh();
    } catch (error) {
      _diagnostics.command(
        'state.reconcile',
        const {},
        watch.elapsedMilliseconds,
        error: error,
      );
      rethrow;
    }
  }

  VideoSessions get videos => this;
  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) =>
      _videoOperation(
        'session.list',
        deviceId,
        () => _media.readVideoSessions(deviceId: deviceId),
      );
  @override
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) => _videoOperation(
    'session.start',
    plan.deviceId,
    () => _media.startVideo(plan),
    sessionId: plan.sessionId,
    verified: true,
  );
  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) => _videoOperation('session.stop', target.deviceId, () {
    if (target.sessionId case final id?) {
      _events.emit({
        'type': 'session.stop.requested',
        'data': {'sessionId': id},
      });
    }
    return _media.stopVideo(target, keepLaunchRecord: keepLaunchRecord);
  }, sessionId: target.sessionId);
  @override
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target) =>
      _videoOperation(
        'session.pause',
        target.deviceId,
        () => _media.pauseVideo(target),
        sessionId: target.sessionId,
        verified: true,
      );
  @override
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target) =>
      _videoOperation(
        'session.resume',
        target.deviceId,
        () => _media.resumeVideo(target),
        sessionId: target.sessionId,
        verified: true,
      );

  void _verifyState() {
    if (_stateRecovery.pending) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
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
  final ApplicationSnapshotReader state;
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
