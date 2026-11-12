import '../media/video_sessions.dart';

import 'package:scrcpy_connect/core/control/video_display.dart';

import 'package:scrcpy_connect/core/media/video_screenshot.dart';

import 'package:scrcpy_connect/core/control/video_quality.dart';

import 'activities.dart';

import 'package:scrcpy_connect/core/media/audio_sources.dart';

import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_directory.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scan.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_observation.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart'
    show SettingsManagement;
import 'package:scrcpy_connect/core/settings/metadata_management.dart'
    show MetadataManagement;
import 'package:scrcpy_connect/core/identity/identity_manager.dart'
    show IdentityManagement;
import 'package:scrcpy_connect/core/content/content_cache.dart'
    show ContentCacheControl;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app_state.dart';
import 'request_failure.dart';
import 'application_session.dart';
import 'application_session_provider.dart';
import 'application_status_notifier.dart';

import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/files/share_inbox_notifier.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/core/content/content_preview.dart'
    show ContentReader;

part 'app_notifier.g.dart';

/// 跨能力只读投影及作用域入口；各能力独立拥有状态与异步写入。
@Riverpod(keepAlive: true)
class AppNotifier extends _$AppNotifier {
  late ApplicationSession _session;

  @override
  AppState build() {
    _session = ref.watch(applicationSessionProvider);
    // 同步组合只读投影，保证页面事件前已可读取状态；入口本身不随投影重建。
    void project() {
      if (ref.mounted && !_session.applyingState) state = _project();
    }

    ref.listen(deviceListProvider, (_, _) => project());
    ref.listen(preferencesProvider, (_, _) => project());
    ref.listen(shareInboxProvider, (_, _) => project());
    ref.listen(applicationStatusProvider, (_, _) => project());
    final commits = _session.stateCommits.listen((_) => project());
    ref.onDispose(() => unawaited(commits.cancel()));
    return _project();
  }

  AppState _project() {
    final devices = ref.read(deviceListProvider);
    final preferences = ref.read(preferencesProvider);
    final shares = ref.read(shareInboxProvider);
    final status = ref.read(applicationStatusProvider);
    return AppState(
      devices: devices.devices,
      loading: devices.loading,
      deviceError: devices.error,
      settings: preferences.values,
      settingsError: preferences.error,
      pendingShares: shares.shares,
      lastEvent: status.lastEvent,
      eventRevision: status.eventRevision,
      audioError: status.audioError,
      focusedDeviceId: status.focusedDeviceId,
      reconciliationPending: status.reconciliationPending,
      reconciliationError: status.reconciliationError,
      reconciledSnapshot: status.reconciledSnapshot,
    );
  }

  DeviceListNotifier get deviceList => ref.read(deviceListProvider.notifier);
  PreferencesNotifier get preferences => ref.read(preferencesProvider.notifier);
  ShareInboxNotifier get shareInbox => ref.read(shareInboxProvider.notifier);
  IdentityManagement get identity => _session.dependencies.identity;
  MetadataManagement get metadata => _session.dependencies.metadata;
  SettingsManagement get settings => _session.dependencies.settings;
  ContentReader get content => _session.dependencies.content;
  RemoteClipboard get clipboard => _session.dependencies.clipboard;
  RemoteControl get control => _session.dependencies.control;
  RemoteAudio get remoteAudio => _session.dependencies.remoteAudio;
  VideoQualityControl get videoQuality => _session.dependencies.videoQuality;
  VideoScreenshots get screenshots => _session.dependencies.screenshots;
  VideoDisplayControl get displays => _session.dependencies.displays;
  ActivityManagement get activities => _session.dependencies.activities;
  BackgroundControl get background => _session.dependencies.background;
  DeviceManagement get deviceManagement => _session.dependencies.devices;
  DeviceConnectionControl get connections => _session.dependencies.connections;
  DeviceSetup get setup => _session.dependencies.setup;
  DeviceInspection get inspection => _session.dependencies.inspection;
  DeviceApps get apps => _session.dependencies.apps;
  DeviceAssessment get assessment => _session.dependencies.assessment;
  DeviceCalls get calls => _session.dependencies.calls;
  DeviceNotifications get notifications => _session.dependencies.notifications;
  GalleryScanner get gallery => _session.dependencies.gallery;

  FileDirectories get directories => _session.dependencies.directories;
  FileMutations get fileMutations => _session.dependencies.fileMutations;
  SystemDocuments get documents => _session.dependencies.documents;
  IncomingShares get incomingShares => _session.dependencies.incomingShares;
  FileTransfers get fileTransfers => _session.dependencies.fileTransfers;

  FileSearch get fileSearch => _session.dependencies.fileSearch;
  DeviceObservation get observation => _session.dependencies.observation;
  DeviceWake get deviceWake => _session.dependencies.wake;
  ContentCacheControl get cache => _session.dependencies.cache;
  Future<String> Function(String) get acquireTransferCacheLease =>
      _session.dependencies.acquireTransferCacheLease;

  AppState snapshot() => state;
  bool isDisposed() => !ref.mounted || _session.disposed;
  int get generation => _session.generation;
  Stream<Json> eventStream() => _session.events;
  Future<void> reconcileState() => _session.dependencies.reconcileState();
  VideoSessions get videos => _session.dependencies.videos;

  Future<void> initialize() async {
    await Future.wait([
      deviceList.refresh(),
      preferences.load(),
      shareInbox.load(),
    ]);
  }

  bool completeDocumentSelection(String id, Json result) =>
      !isDisposed() &&
      (_session.dependencies.completeDocumentSelection?.call(id, result) ??
          false);
  void focusClipboardSession(String device, String session, bool focused) =>
      _session.focusClipboardSession(device, session, focused);
  void Function()? claimAppOpen(String device, String package) =>
      _session.claimAppOpen(device, package);
  void updateAudioError(String? error) =>
      ref.read(applicationStatusProvider.notifier).updateAudioError(error);
  Future<void> focusDevice(String? id) =>
      ref.read(applicationStatusProvider.notifier).focusDevice(id);
}
