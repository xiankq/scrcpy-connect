import 'dart:async';

import 'package:scrcpy_connect/core/activities/activity_management.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/content/content_cache.dart'
    show ContentCacheControl;
import 'package:scrcpy_connect/core/content/content_preview.dart'
    show ContentReader;
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_connection_control.dart';
import 'package:scrcpy_connect/core/devices/device_inspection.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_observation.dart';
import 'package:scrcpy_connect/core/devices/device_setup.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart'
    show DiagnosticLog;
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/files/file_directories.dart';
import 'package:scrcpy_connect/core/files/file_mutations.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/files/system_documents.dart';
import 'package:scrcpy_connect/core/gallery/gallery_scanner.dart';
import 'package:scrcpy_connect/core/identity/identity_manager.dart'
    show IdentityManagement;
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/background_control.dart';
import 'package:scrcpy_connect/core/settings/metadata_management.dart'
    show MetadataManagement;
import 'package:scrcpy_connect/core/settings/settings_management.dart'
    show SettingsManagement;

/// 每个 provider scope 只供应一个传输；状态所有者订阅事件，并在释放时调用一次 close。
class AppDependencies {
  AppDependencies({
    required this.videos,
    required this.content,
    required this.clipboard,
    required this.control,
    required this.remoteAudio,
    required this.videoQuality,
    required this.screenshots,
    required this.displays,
    required this.reconcileState,
    required this.activities,
    required this.background,
    required this.devices,
    required this.connections,
    required this.setup,
    required this.inspection,
    required this.apps,
    required this.assessment,
    required this.observation,
    required this.calls,
    required this.notifications,
    required this.fileSearch,
    required this.directories,
    required this.fileMutations,
    required this.fileTransfers,
    required this.incomingShares,
    required this.documents,
    required this.gallery,
    required this.wake,
    required this.appInfo,
    required this.identity,
    required this.metadata,
    required this.settings,
    required this.cache,
    required this.acquireTransferCacheLease,
    this.events = const Stream<Json>.empty(),
    this.close,
    this.diagnostics,
    this.completeDocumentSelection,
    this.setVisible,
    AppState? initialState,
    this.initialize = true,
  }) : initialState = initialState ?? AppState();
  final Future<void> Function(bool)? setVisible;
  final bool Function(String, Json)? completeDocumentSelection;
  final DiagnosticLog? diagnostics;
  final VideoSessions videos;
  final ContentReader content;
  final RemoteClipboard clipboard;
  final RemoteControl control;
  final RemoteAudio remoteAudio;
  final VideoQualityControl videoQuality;
  final VideoScreenshots screenshots;
  final VideoDisplayControl displays;
  final ActivityManagement activities;
  final Future<void> Function() reconcileState;
  final BackgroundControl background;
  final DeviceManagement devices;
  final DeviceConnectionControl connections;
  final DeviceSetup setup;
  final DeviceInspection inspection;
  final DeviceApps apps;
  final DeviceAssessment assessment;
  final DeviceObservation observation;
  final DeviceCalls calls;
  final DeviceNotifications notifications;
  final FileSearch fileSearch;
  final FileDirectories directories;
  final FileMutations fileMutations;
  final FileTransfers fileTransfers;
  final IncomingShares incomingShares;
  final SystemDocuments documents;
  final GalleryScanner gallery;
  final DeviceWake wake;
  final Future<AppInfo> Function() appInfo;
  final IdentityManagement identity;
  final MetadataManagement metadata;
  final SettingsManagement settings;
  final ContentCacheControl cache;
  final Future<String> Function(String transferId) acquireTransferCacheLease;
  final Stream<Json> events;
  final Future<void> Function()? close;
  final AppState initialState;
  final bool initialize;
}
