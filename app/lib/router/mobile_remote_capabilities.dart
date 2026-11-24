import 'dart:async';
import 'dart:isolate';

import 'package:adb/adb.dart' show AdbCancellation;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/activities/activity_management.dart';
import 'package:scrcpy_connect/core/control/control_capabilities_provider.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart';
import 'package:scrcpy_connect/core/content/content_capabilities_provider.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/file_capabilities_provider.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/media/window_video_player.dart';
import 'package:scrcpy_connect/core/platform/window_isolate_port.dart';
import 'package:scrcpy_connect/core/recovery/recovery_actions_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/router/models/remote_control_intent.dart';
import 'package:scrcpy_connect/router/models/remote_launch_intent.dart';

typedef MobileRemoteRequest = ({RemoteControlIntent? action, bool keyboard});

typedef MobileRemoteOpen = ({
  String deviceId,
  String? sessionId,
  String? packageName,
  String? appName,
  bool onPhoneScreen,
  bool moveForegroundApp,
  bool keyboard,
  RemoteControlIntent? action,
});

typedef MobileRemoteEntry = ({
  String windowId,
  String deviceId,
  String deviceName,
  String? packageName,
  String? name,
});

typedef MobileRemoteAttachment = ({
  AppState state,
  String location,
  RemoteLaunchIntent? extra,
  MobileRemoteRequest? request,
});

/// Remote pages borrow the same typed capabilities as inline control pages.
/// The texture registry and route remain local to each engine.
final class MobileRemoteCapabilities {
  MobileRemoteCapabilities(
    this._container, {
    required this.attach,
    required this.start,
    required this.open,
    required this.entries,
    required this.activate,
    required this.workbench,
    required this.close,
    required this.focus,
    required this.setVisible,
  });

  final ProviderContainer _container;
  final MobileRemoteAttachment Function(SendPort events, SendPort video) attach;
  final Future<VideoSessionView> Function(VideoSessionPlan) start;
  final Future<void> Function(MobileRemoteOpen) open;
  final List<MobileRemoteEntry> Function() entries;
  final Future<void> Function(String) activate;
  final Future<void> Function() workbench;
  final Future<void> Function(bool) close;
  final Future<void> Function(String, bool) focus;
  final Future<void> Function(bool) setVisible;

  Future<void> reconcile() => _container.read(reconcileStateProvider)();
  VideoSessions get video => _container.read(videoSessionsProvider);
  RemoteControl get control => _container.read(remoteControlProvider);
  VideoDisplayControl get display => _container.read(videoDisplayProvider);
  VideoScreenshots get screenshots => _container.read(videoScreenshotsProvider);
  VideoQualityControl get quality =>
      _container.read(videoQualityControlProvider);
  DeviceReader get devices => _container.read(deviceReaderProvider);
  DeviceInspection get inspection => _container.read(deviceInspectionProvider);
  DeviceApps get apps => _container.read(deviceAppsProvider);
  DeviceWake get wake => _container.read(deviceWakeProvider);
  RemoteAudio get audio => _container.read(remoteAudioProvider);
  SettingsManagement get settings =>
      _container.read(settingsManagementProvider);
  ActivityManagement get activities =>
      _container.read(activityManagementProvider);
  ContentCacheControl get cache => _container.read(contentCacheControlProvider);
  SystemDocuments get documents => _container.read(systemDocumentsProvider);
}

final class MobileRemoteClient
    implements
        VideoSessions,
        RemoteControl,
        VideoDisplayControl,
        VideoScreenshots,
        VideoQualityControl,
        DeviceReader,
        DeviceInspection,
        DeviceApps,
        DeviceWake,
        RemoteAudio,
        SettingsManagement,
        ActivityManagement,
        ContentCacheControl,
        SystemDocuments {
  MobileRemoteClient(this.windowId, SendPort port)
    : _host = WindowIsolatePort(port);
  final String windowId;
  final WindowIsolatePort<MobileRemoteCapabilities> _host;
  final players = WindowVideoPlayers();

  MobileRemoteAttachment? attachment;
  Stream<MobileRemoteRequest> requests = const Stream.empty();

  Future<MobileRemoteAttachment> attach(SendPort events) async {
    final joined = await _host.call(
      (owner, request) => owner.attach(request.$1, request.$2),
      (events, players.port),
    );
    attachment = joined;
    return joined;
  }

  List<Override> get overrides => [
    videoSessionsProvider.overrideWithValue(this),
    remoteControlProvider.overrideWithValue(this),
    videoDisplayProvider.overrideWithValue(this),
    videoScreenshotsProvider.overrideWithValue(this),
    videoQualityControlProvider.overrideWithValue(this),
    deviceReaderProvider.overrideWithValue(this),
    deviceInspectionProvider.overrideWithValue(this),
    deviceAppsProvider.overrideWithValue(this),
    deviceWakeProvider.overrideWithValue(this),
    remoteAudioProvider.overrideWithValue(this),
    settingsManagementProvider.overrideWithValue(this),
    activityManagementProvider.overrideWithValue(this),
    contentCacheControlProvider.overrideWithValue(this),
    systemDocumentsProvider.overrideWithValue(this),
    documentSelectionResponderProvider.overrideWithValue(null),
    reconcileStateProvider.overrideWithValue(reconcile),
  ];

  Future<void> reconcile() => _host.call((owner, _) => owner.reconcile(), null);
  Future<void> open(MobileRemoteOpen request) =>
      _host.call((owner, req) => owner.open(req), request);
  Future<List<MobileRemoteEntry>> entries() =>
      _host.call((owner, _) => owner.entries(), null);
  Future<void> activate(String id) =>
      _host.call((owner, id) => owner.activate(id), id);
  Future<void> workbench() => _host.call((owner, _) => owner.workbench(), null);
  Future<void> close({bool returnToWorkbench = true}) =>
      _host.call((owner, result) => owner.close(result), returnToWorkbench);
  Future<void> focus(String sessionId, bool focused) => _host.call(
    (owner, req) => owner.focus(req.$1, req.$2),
    (sessionId, focused),
  );

  Future<void> setVisible(bool visible) =>
      _host.call((owner, visible) => owner.setVisible(visible), visible);

  @override
  Future<VideoSessionView> startVideo(VideoSessionPlan plan) =>
      _host.call((owner, plan) => owner.start(plan), plan);
  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) =>
      _host.call(
        (owner, id) => owner.video.readVideoSessions(deviceId: id),
        deviceId,
      );
  @override
  Future<VideoStopReceipt> stopVideo(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) => _host.call(
    (owner, req) => owner.video.stopVideo(req.$1, keepLaunchRecord: req.$2),
    (target, keepLaunchRecord),
  );
  @override
  Future<VideoPlaybackReceipt> pauseVideo(ControlTarget target) =>
      _host.call((owner, target) => owner.video.pauseVideo(target), target);
  @override
  Future<VideoPlaybackReceipt> resumeVideo(ControlTarget target) =>
      _host.call((owner, target) => owner.video.resumeVideo(target), target);
  @override
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  ) => _host.call((owner, req) => owner.control.sendControl(req.$1, req.$2), (
    target,
    action,
  ));
  @override
  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size) =>
      _host.call((owner, req) => owner.display.resizeDisplay(req.$1, req.$2), (
        target,
        size,
      ));
  @override
  Future<VideoScreenshot> captureScreenshot(String sessionId) => _host.call(
    (owner, id) => owner.screenshots.captureScreenshot(id),
    sessionId,
  );
  @override
  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) => _host
      .call((owner, id) => owner.quality.readVideoQualityOptions(id), deviceId);
  @override
  Future<VideoQualityApplication> changeVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) => _host.call(
    (owner, req) => owner.quality.changeVideoQuality(req.$1, req.$2),
    (deviceId, patch),
  );

  @override
  Future<List<DeviceSnapshot>> readDevices() =>
      _host.call((owner, _) => owner.devices.readDevices(), null);
  @override
  Future<DeviceSnapshot> readDevice(String id) =>
      _host.call((owner, id) => owner.devices.readDevice(id), id);
  @override
  Future<DeviceReading<DeviceScreenState>> readScreenState(
    String id, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) =>
        owner.inspection.readScreenState(req.$1, connectionId: req.$2),
    (id, connectionId),
  );
  @override
  Future<DeviceReading<String>> readForegroundApp(
    String id, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) =>
        owner.inspection.readForegroundApp(req.$1, connectionId: req.$2),
    (id, connectionId),
  );
  @override
  Future<DeviceReading<({int width, int height})?>> readScreenSize(String id) =>
      _host.call((owner, id) => owner.inspection.readScreenSize(id), id);
  @override
  Future<DeviceReading<DeviceDetails>> readDetails(
    String id, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) => owner.inspection.readDetails(req.$1, connectionId: req.$2),
    (id, connectionId),
  );
  @override
  Future<DeviceReading<DeviceBattery>> readBattery(
    String id, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) => owner.inspection.readBattery(req.$1, connectionId: req.$2),
    (id, connectionId),
  );
  @override
  Future<DeviceReading<DeviceCapacity>> readSharedStorageCapacity(
    String id, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) => owner.inspection.readSharedStorageCapacity(
      req.$1,
      connectionId: req.$2,
    ),
    (id, connectionId),
  );
  @override
  Future<DeviceReading<DeviceNetworkInfo>> readNetwork(
    String id, {
    String? connectionId,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) => owner.inspection.readNetwork(req.$1, connectionId: req.$2),
    (id, connectionId),
  );
  @override
  Future<DeviceWakeReceipt> wakeDevice(String id, {String? connectionId}) =>
      _host.call(
        (owner, req) => owner.wake.wakeDevice(req.$1, connectionId: req.$2),
        (id, connectionId),
      );
  @override
  Future<List<DeviceApp>> readInstalledApps(
    String id, {
    AdbCancellation? cancellation,
  }) => _host.call((owner, id) => owner.apps.readInstalledApps(id), id);
  @override
  Future<RunningDeviceApps> readRunningApps(
    String id, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) => owner.apps.readRunningApps(req.$1, allowStart: req.$2),
    (id, allowStart),
  );
  @override
  Future<DeviceAppIcon> readAppIcon(
    String id,
    String packageName, {
    int? userId,
    bool allowStart = true,
    AdbCancellation? cancellation,
  }) => _host.call(
    (owner, req) => owner.apps.readAppIcon(
      req.$1,
      req.$2,
      userId: req.$3,
      allowStart: req.$4,
    ),
    (id, packageName, userId, allowStart),
  );

  @override
  Future<List<DeviceAudioSnapshot>> readAudioSources({String? deviceId}) =>
      _host.call(
        (owner, id) => owner.audio.readAudioSources(deviceId: id),
        deviceId,
      );
  @override
  Future<Set<String>> readAudioEligibleDevices() =>
      _host.call((owner, _) => owner.audio.readAudioEligibleDevices(), null);
  @override
  Future<DeviceAudioPlayback> startAudio(String deviceId) =>
      _host.call((owner, id) => owner.audio.startAudio(id), deviceId);
  @override
  Future<void> stopAudio(DeviceAudioTarget target) =>
      _host.call((owner, target) => owner.audio.stopAudio(target), target);
  @override
  Future<DeviceAudioPlayback> pauseAudio(DeviceAudioTarget target) =>
      _host.call((owner, target) => owner.audio.pauseAudio(target), target);
  @override
  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target) =>
      _host.call((owner, target) => owner.audio.resumeAudio(target), target);
  @override
  Future<DeviceAudioPlayback> changeAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  }) => _host.call(
    (owner, req) =>
        owner.audio.changeAudioVolume(req.$1, volume: req.$2, muted: req.$3),
    (target, volume, muted),
  );

  @override
  Future<Preferences> read() =>
      _host.call((owner, _) => owner.settings.read(), null);
  @override
  Future<Preferences> update(
    PreferenceChanges changes, {
    int? expectedRevision,
  }) => _host.call(
    (owner, req) => owner.settings.update(req.$1, expectedRevision: req.$2),
    (changes, expectedRevision),
  );
  @override
  Future<ActivityCollection> readActivities({String? deviceId}) => _host.call(
    (owner, id) => owner.activities.readActivities(deviceId: id),
    deviceId,
  );
  @override
  Future<void> stopActivity(ActivityTarget target) => _host.call(
    (owner, target) => owner.activities.stopActivity(target),
    target,
  );
  @override
  Future<CacheStatus> status() =>
      _host.call((owner, _) => owner.cache.status(), null);
  @override
  Future<void> configure({int? budgetBytes, String? outgoingDirectory}) =>
      _host.call(
        (owner, req) => owner.cache.configure(
          budgetBytes: req.$1,
          outgoingDirectory: req.$2,
        ),
        (budgetBytes, outgoingDirectory),
      );
  @override
  Future<int> clear() => _host.call((owner, _) => owner.cache.clear(), null);
  @override
  Future<bool> retain(String path, {bool ifManaged = false}) => _host.call(
    (owner, req) => owner.cache.retain(req.$1, ifManaged: req.$2),
    (path, ifManaged),
  );
  @override
  Future<void> release(String leaseId) =>
      _host.call((owner, id) => owner.cache.release(id), leaseId);

  @override
  Future<DocumentOutcome> importDocuments(
    String operationId,
    DocumentImportKind kind,
  ) => _host.call(
    (owner, req) => owner.documents.importDocuments(req.$1, req.$2),
    (operationId, kind),
  );
  @override
  Future<DocumentOutcome> exportDocument(DocumentExportPlan plan) =>
      _host.call((owner, plan) => owner.documents.exportDocument(plan), plan);
  @override
  Future<void> cancelDocument(String operationId) => _host.call(
    (owner, id) => owner.documents.cancelDocument(id),
    operationId,
  );
  @override
  Future<void> releaseDocumentSource(String managedSourceId) => _host.call(
    (owner, id) => owner.documents.releaseDocumentSource(id),
    managedSourceId,
  );
  @override
  Future<DocumentConflict?> readDocumentConflict(String operationId) =>
      _host.call(
        (owner, id) => owner.documents.readDocumentConflict(id),
        operationId,
      );
  @override
  Future<bool> resolveDocumentConflict(
    String operationId,
    String conflictId,
    DocumentConflictDecision decision, {
    bool applyToRemaining = false,
  }) => _host.call(
    (owner, req) => owner.documents.resolveDocumentConflict(
      req.$1,
      req.$2,
      req.$3,
      applyToRemaining: req.$4,
    ),
    (operationId, conflictId, decision, applyToRemaining),
  );
  @override
  Future<FileDeliveryRecord?> readDelivery(DocumentSource source) => _host.call(
    (owner, source) => owner.documents.readDelivery(source),
    source,
  );
}

final mobileRemoteClientProvider = Provider<MobileRemoteClient?>((ref) => null);

final class MobileRemoteScope extends InheritedWidget {
  const MobileRemoteScope({
    super.key,
    required this.client,
    required super.child,
  });
  final MobileRemoteClient client;

  static MobileRemoteClient? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MobileRemoteScope>()?.client;

  @override
  bool updateShouldNotify(MobileRemoteScope oldWidget) =>
      !identical(oldWidget.client, client);
}
