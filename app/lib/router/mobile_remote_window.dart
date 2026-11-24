import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_focus_notifier.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_sync_notifier.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/app_window_visibility_provider.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/media/window_video_player.dart';
import 'package:scrcpy_connect/core/platform/platform_window_host.dart';
import 'package:scrcpy_connect/core/platform/window_isolate_port.dart';
import 'package:scrcpy_connect/router/mobile_remote_capabilities.dart';
import 'package:scrcpy_connect/router/models/remote_launch_intent.dart';
import 'package:uuid/uuid.dart';

String mobileRemoteWindowPort(String id) =>
    'dev.scrcpyconnect.remoteWindow.$id';

/// The workbench retains the logical window and grants the scene one playback
/// renderer. The child does not acquire an ADB or application scope.
final class MobileRemoteWindow {
  MobileRemoteWindow({
    required String deviceId,
    required this.title,
    required String location,
    required RemoteLaunchIntent? extra,
    required this.aspectRatio,
    required this.navigationHeight,
    required this.host,
    required ProviderContainer providers,
    required Future<void> Function(MobileRemoteOpen) open,
    required List<MobileRemoteEntry> Function() entries,
    required Future<void> Function(String) activate,
    required Future<void> Function() workbench,
  }) {
    _video = providers.read(videoSessionsProvider);
    final start = providers.read(windowVideoStartProvider);
    _visibility = providers.read(appWindowVisibilityProvider);
    _clipboardSync = providers.read(clipboardSyncProvider.notifier);
    _clipboard = providers
        .read(clipboardFocusProvider.notifier)
        .claim(deviceId);
    final capabilities = MobileRemoteCapabilities(
      providers,
      attach: (events, renderer) {
        if (_events != null) {
          throw const RequestFailure(
            'window_unavailable',
            '这个控制窗口已失去原画面，请回工作台重新打开。',
          );
        }
        _events = events;
        _renderer = renderer;
        _subscription = providers
            .read(runtimeEventsProvider)
            .listen(events.send);
        _attached.complete();
        return (
          state: providers.read(appSnapshotProvider),
          location: location,
          extra: extra,
          request: _pendingRequest,
        );
      },
      start: (plan) async {
        final renderer = _renderer!;
        final sessionId = plan.sessionId ?? const Uuid().v4();
        _sessionId = sessionId;
        return start(
          plan.copyWith(sessionId: sessionId),
          () => WindowVideoPlayer(renderer, _rendererDestroyed.future),
        );
      },
      open: open,
      entries: entries,
      setVisible: (visible) => _visibility.set(id, visible),
      activate: activate,
      workbench: workbench,
      close: (returnToWorkbench) async {
        if (returnToWorkbench) await workbench();
        await host.close(id);
      },
      focus: (sessionId, focused) async {
        _clipboard.focus(sessionId, focused);
        if (focused) {
          await providers.read(currentDeviceProvider.notifier).focus(deviceId);
        }
        _clipboardSync.setIndependentWindowFocus(id, focused);
      },
    );
    _owner = WindowIsolateOwner(capabilities);
    IsolateNameServer.registerPortWithName(
      _owner.port,
      mobileRemoteWindowPort(id),
    );
  }

  final id = const Uuid().v4();
  final PlatformWindowHost host;
  final double? aspectRatio;
  final double navigationHeight;
  final String title;
  late final VideoSessions _video;
  late final AppWindowVisibility _visibility;
  late final ClipboardFocusLease _clipboard;
  late final ClipboardSyncNotifier _clipboardSync;
  late final WindowIsolateOwner<MobileRemoteCapabilities> _owner;
  SendPort? _events;
  SendPort? _renderer;
  StreamSubscription<RuntimeEvent>? _subscription;
  MobileRemoteRequest? _pendingRequest;
  String? _sessionId;
  final _rendererDestroyed = Completer<void>();
  final _attached = Completer<void>();

  void rendererDestroyed() => _rendererDestroyed.complete();

  Future<bool> show() async {
    final receipt = await host.open(
      windowId: id,
      title: title,
      aspectRatio: aspectRatio,
      navigationHeight: navigationHeight,
    );
    if (!receipt.opened) return false;
    return _attached.future
        .then((_) => true)
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
  }

  void request(MobileRemoteRequest request) {
    if (_events case final events?) {
      events.send(request);
    } else {
      _pendingRequest = request;
    }
  }

  Future<VideoStopReceipt?> stop() async {
    final sessionId = _sessionId;
    if (sessionId == null) return null;
    return _video.stopVideo(ControlTarget(sessionId: sessionId));
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping(mobileRemoteWindowPort(id));
    _owner.dispose();
    _clipboard.dispose();
    _clipboardSync.setIndependentWindowFocus(id, false);
    unawaited(_visibility.set(id, false));
    unawaited(_subscription?.cancel());
  }
}
