import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/widgets/remote_audio_views.dart';

/// 由 widget 树持有控制画面、可见性和声音租约；provider 只提供应用数据。
class RemoteViews {
  RemoteViews({
    required VideoSessions videos,
    required RemoteAudio audio,
    required Stream<RuntimeEvent> events,
    required DeviceAudioViewSnapshot Function() readSnapshot,
    required void Function(String?) onAudioError,
    required bool Function() current,
  }) : _audio = audio,
       _current = current {
    _sessionViewRegistry = SessionViewRegistry(
      videos,
      current: () => !_disposed && current(),
    );
    _deviceAudio = DeviceAudioViewCoordinator(
      audio: audio,
      readSnapshot: readSnapshot,
      onError: onAudioError,
    );
    _subscription = events.listen(_onEvent);
    if (readSnapshot().reconciliationPending) {
      _sessionViewRegistry.markUncertain();
    }
  }

  final RemoteAudio _audio;
  final bool Function() _current;
  bool _disposed = false;
  late final SessionViewRegistry _sessionViewRegistry;
  late final DeviceAudioViewCoordinator _deviceAudio;
  late final StreamSubscription<RuntimeEvent> _subscription;

  void _onEvent(RuntimeEvent event) {
    if (event.telemetry) return;
    final payload = event.data;
    if (payload is RecoveryStarted || payload is RecoveryFailed) {
      _sessionViewRegistry.markUncertain();
    } else if (payload case RecoveryCompleted(:final snapshot)) {
      _sessionViewRegistry.reconcile(snapshot.sessions);
    }
    _deviceAudio.handleEvent(event);
    if (payload is RecoveryCompleted ||
        event.type.startsWith('session.') ||
        event.type == 'devices.changed') {
      reconcile();
    }
  }

  void reconcile() => _deviceAudio.reconcile();

  Future<DeviceAudioPlayback> startAudio(String deviceId) async {
    if (_disposed || !_current()) {
      throw const RequestFailure('stale_view', '画面所有者已释放。');
    }
    final revision = _deviceAudio.playbackRequestRevision(deviceId);
    final result = await _audio.startAudio(deviceId);
    _deviceAudio.playbackSucceeded(result, revision);
    return result;
  }

  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target) async {
    if (_disposed || !_current()) {
      throw const RequestFailure('stale_view', '画面所有者已释放。');
    }
    final revision = _deviceAudio.playbackRequestRevision(target.deviceId);
    final result = await _audio.resumeAudio(target);
    _deviceAudio.playbackSucceeded(result, revision);
    return result;
  }

  final _pages = <Object, ({String device, String? sessionId})>{};

  bool Function() claimControlPage(String deviceId, {String? sessionId}) {
    if (sessionId != null && sessionId.isNotEmpty) {
      _pages.removeWhere(
        (_, page) => page.device == deviceId && page.sessionId == sessionId,
      );
    }
    final token = Object();
    _pages[token] = (device: deviceId, sessionId: sessionId);
    return () => _pages.remove(token) != null && !hasControlPages(deviceId);
  }

  bool hasControlPages(String deviceId) =>
      _pages.values.any((page) => page.device == deviceId);

  SessionViewLease claimSessionViewLease(
    String sessionId, {
    required bool visible,
  }) {
    final view = _sessionViewRegistry.claim(sessionId, visible: visible);
    _deviceAudio.reconcile();
    return view;
  }

  /// 页面即使暂被遮挡仍持有声音租约，最后一个页面释放时停止该设备音源。
  void Function() claimRemoteDeviceView(String deviceId) =>
      _deviceAudio.claimView(deviceId);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessionViewRegistry.retire();
    _deviceAudio.dispose();
    unawaited(_subscription.cancel());
  }
}

class RemoteViewsScope extends InheritedWidget {
  const RemoteViewsScope({
    super.key,
    required this.views,
    required super.child,
  });
  final RemoteViews views;

  static RemoteViews of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RemoteViewsScope>()!.views;

  @override
  bool updateShouldNotify(RemoteViewsScope oldWidget) =>
      views != oldWidget.views;
}

/// 路由拥有打开的控制窗口；可见性与明确关闭分开，单会话队列先排空旧输入再恢复新画面。
class SessionViewRegistry {
  SessionViewRegistry(this.videos, {bool Function()? current})
    : _current = current ?? (() => true);
  final bool Function() _current;
  bool get _accepting => !_retired && _current();
  bool _owns(SessionViewLease view) => identical(_owners[view.id], view);
  final VideoSessions videos;
  final _owners = <String, SessionViewLease>{};
  final _tails = <String, Future<void>>{};
  final _closed = <String>{};
  bool _uncertain = false;
  bool _retired = false;

  SessionViewLease claim(String id, {required bool visible}) {
    if (!_accepting) throw StateError('画面所有者已释放。');
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    if (_closed.contains(id)) throw StateError('控制窗口已关闭，请明确打开新画面。');
    final view = SessionViewLease._(this, id, visible);
    _owners[id] = view;
    return view;
  }

  void invalidate() => _owners.clear();

  /// 退役后禁止新操作，原租约仍可排空输入并清理自己绑定的原能力。
  void retire() => _retired = true;

  /// 取得权威快照前，旧视图只能清理自己绑定的会话。
  void markUncertain() {
    _uncertain = true;
    for (final owner in _owners.values) {
      owner._revision++;
    }
  }

  void reconcile(List<RecoveredVideoSession> sessions) {
    final current = {
      for (final item in sessions)
        if (item.live) item.session.sessionId: item.session,
    };
    _uncertain = false;
    _owners.removeWhere((id, _) => !current.containsKey(id));
    for (final entry in _owners.entries) {
      final session = current[entry.key]!;
      entry.value._revision++;
      entry.value._visible = session.status != .paused;
    }
  }

  Future<VideoStopReceipt?> _close(
    SessionViewLease view,
    Future<void>? afterInput,
  ) {
    final operation = (_tails[view.id] ?? Future<void>.value()).then((_) async {
      await afterInput;
      if (!_owns(view)) return null;
      try {
        return await videos.stopVideo(ControlTarget(sessionId: view.id));
      } finally {
        if (_owns(view)) _owners.remove(view.id);
      }
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[view.id] = tail;
    return operation.whenComplete(() {
      if (identical(_tails[view.id], tail)) _tails.remove(view.id);
    });
  }

  Future<VideoPlaybackReceipt?> _visibility(
    SessionViewLease view,
    bool visible, {
    Future<void>? afterInput,
    bool release = false,
  }) {
    final revision = view._revision;
    final operation = (_tails[view.id] ?? Future<void>.value()).then((_) async {
      // 即使旧视图已被替换，也必须先排空其释放输入再恢复新视图。
      await afterInput;
      if (!_owns(view)) return null;
      if (visible && !_accepting) return null;
      if ((_uncertain && visible) || (revision != view._revision && !release)) {
        return null;
      }
      var succeeded = false;
      try {
        if (!visible && !view._visible && !_uncertain) {
          succeeded = true;
          return null;
        }
        // 恢复可能已显示画面但就绪回执失败；暂停成功前仍按可见状态处理。
        if (visible) view._visible = true;
        final target = ControlTarget(sessionId: view.id);
        final receipt = await (visible
            ? videos.resumeVideo(target)
            : videos.pauseVideo(target));
        if (revision == view._revision && _owns(view)) {
          view._visible = visible;
        }
        succeeded = true;
        return receipt;
      } finally {
        if (release && succeeded && _owns(view)) {
          _owners.remove(view.id);
        }
      }
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[view.id] = tail;
    return operation.whenComplete(() {
      if (identical(_tails[view.id], tail)) _tails.remove(view.id);
    });
  }
}

class SessionViewLease {
  SessionViewLease._(this._registry, this.id, this._visible);
  final SessionViewRegistry _registry;
  final String id;
  bool _visible;
  bool _released = false;
  int _revision = 0;
  bool get isCurrent => _registry._accepting && !_released && ownsBinding;

  /// 有序释放仍在排空最后输入时，视图仍持有绑定。
  bool get ownsBinding => _registry._owns(this);

  /// 会话或传输结束后只撤销本机绑定，不暂停已移除会话，也不因远端清理失败保留旧所有者。
  void abandonEndedSession() {
    _released = true;
    _revision++;
    if (_registry._owns(this)) _registry._owners.remove(id);
  }

  Future<VideoPlaybackReceipt?> resume({Future<void>? afterInput}) => _released
      ? Future.value(null)
      : _registry._visibility(this, true, afterInput: afterInput);
  Future<VideoPlaybackReceipt?> pause({Future<void>? afterInput}) => _released
      ? Future.value(null)
      : _registry._visibility(this, false, afterInput: afterInput);
  Future<VideoStopReceipt?> close({Future<void>? afterInput}) {
    if (_released) return Future.value(null);
    _released = true;
    _revision++;
    if (ownsBinding) _registry._closed.add(id);
    return _registry._close(this, afterInput);
  }

  Future<VideoPlaybackReceipt?> release({Future<void>? afterInput}) {
    if (_released) return Future.value(null);
    _released = true;
    return _registry
        ._visibility(this, false, afterInput: afterInput, release: true)
        .catchError((Object error, StackTrace stack) {
          _released = false;
          Error.throwWithStackTrace(error, stack);
        });
  }
}
