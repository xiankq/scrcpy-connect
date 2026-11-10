import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

import 'remote_audio_views.dart';

/// 由 widget 树持有控制画面、可见性和声音租约；provider 只提供应用数据。
class RemoteViews {
  RemoteViews(this.controller) : _generation = controller.generation {
    _sessionViewRegistry = SessionViewRegistry(
      controller.request,
      current: () =>
          !_disposed &&
          !controller.isDisposed() &&
          controller.generation == _generation,
    );
    _deviceAudio = DeviceAudioViewCoordinator(
      request: controller.request,
      readSnapshot: () => DeviceAudioViewSnapshot(
        devices: controller.snapshot().devices,
        reconciliationPending: controller.snapshot().reconciliationPending,
      ),
      onError: controller.updateAudioError,
    );
    _subscription = controller.eventStream().listen(_onEvent);
    if (controller.snapshot().reconciliationPending) {
      _sessionViewRegistry.markUncertain();
    }
  }

  final AppStore controller;
  final int _generation;
  bool _disposed = false;
  late final SessionViewRegistry _sessionViewRegistry;
  late final DeviceAudioViewCoordinator _deviceAudio;
  late final StreamSubscription<Json> _subscription;

  void _onEvent(Json event) {
    if (event['type'] == 'session.frame') return;
    if (event['type'] == 'state.resync' ||
        event['type'] == 'state.resync.failed') {
      _sessionViewRegistry.markUncertain();
    } else if (event['type'] == 'state.resynced') {
      _sessionViewRegistry.reconcile(
        objects(jsonObject(event['data'])['sessions']),
      );
    }
    _deviceAudio.handleEvent(event);
    if (value(event, 'type').startsWith('session.') ||
        ['state.resynced', 'devices.changed'].contains(event['type'])) {
      reconcile();
    }
  }

  void reconcile() => _deviceAudio.reconcile();

  Future<Json> request(String command, [Json params = const {}]) async {
    final revision = _deviceAudio.playbackRequestRevision(command, params);
    final result = await controller.request(command, params);
    _deviceAudio.playbackSucceeded(command, params, result, revision);
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
    _sessionViewRegistry.invalidate();
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

typedef SessionJson = Map<String, dynamic>;
typedef SessionRequest = Future<SessionJson> Function(String, [SessionJson]);

/// 路由拥有打开的控制窗口；可见性与明确关闭分开，单会话队列先排空旧输入再恢复新画面。
class SessionViewRegistry {
  SessionViewRegistry(this.request, {bool Function()? current})
    : _current = current ?? (() => true);
  final bool Function() _current;
  bool _owns(SessionViewLease view) =>
      _current() && identical(_owners[view.id], view);
  final SessionRequest request;
  final _owners = <String, SessionViewLease>{};
  final _tails = <String, Future<void>>{};
  final _closed = <String>{};
  bool _uncertain = false;

  SessionViewLease claim(String id, {required bool visible}) {
    if (!_current()) throw StateError('画面所有者已释放。');
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    if (_closed.contains(id)) throw StateError('控制窗口已关闭，请明确打开新画面。');
    final view = SessionViewLease._(this, id, visible);
    _owners[id] = view;
    return view;
  }

  void invalidate() => _owners.clear();

  /// 取得权威快照前，旧视图只能清理自己绑定的会话。
  void markUncertain() {
    _uncertain = true;
    for (final owner in _owners.values) {
      owner._revision++;
    }
  }

  void reconcile(List<SessionJson> sessions) {
    final current = <String, SessionJson>{
      for (final session in sessions)
        if (!['stopped', 'failed', 'error'].contains(session['status']) ||
            (session['status'] == 'failed' &&
                session['qualityRetryable'] == true))
          (session['sessionId'] ?? session['id']).toString(): session,
    };
    _uncertain = false;
    _owners.removeWhere((id, _) => !current.containsKey(id));
    for (final entry in _owners.entries) {
      final session = current[entry.key]!;
      entry.value._revision++;
      entry.value._visible = session['status'] != 'paused';
    }
  }

  Future<SessionJson> _close(SessionViewLease view, Future<void>? afterInput) {
    final operation = Future<void>.value().then((_) async {
      await afterInput;
      if (!_owns(view)) return <String, dynamic>{};
      try {
        return await request('session.stop', {
          'sessionId': view.id,
          'keepTask': true,
        });
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

  Future<SessionJson> _visibility(
    SessionViewLease view,
    bool visible, {
    Future<void>? afterInput,
    bool release = false,
  }) {
    final revision = view._revision;
    final operation = (_tails[view.id] ?? Future<void>.value()).then((_) async {
      // 即使旧视图已被替换，也必须先排空其释放输入再恢复新视图。
      await afterInput;
      if (!_owns(view)) return <String, dynamic>{};
      if ((_uncertain && visible) || (revision != view._revision && !release)) {
        return <String, dynamic>{};
      }
      var succeeded = false;
      try {
        if (!visible && !view._visible && !_uncertain) {
          succeeded = true;
          return <String, dynamic>{};
        }
        // 恢复可能已显示画面但就绪回执失败；暂停成功前仍按可见状态处理。
        if (visible) view._visible = true;
        final receipt = await request(
          visible ? 'session.resume' : 'session.pause',
          {'sessionId': view.id},
        );
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
  bool get isCurrent => _registry._current() && !_released && ownsBinding;

  /// 有序释放仍在排空最后输入时，视图仍持有绑定。
  bool get ownsBinding => _registry._owns(this);

  /// 会话或传输结束后只撤销本机绑定，不暂停已移除会话，也不因远端清理失败保留旧所有者。
  void abandonEndedSession() {
    _released = true;
    _revision++;
    if (_registry._owns(this)) _registry._owners.remove(id);
  }

  Future<SessionJson> resume({Future<void>? afterInput}) => _released
      ? Future.value({})
      : _registry._visibility(this, true, afterInput: afterInput);
  Future<SessionJson> pause({Future<void>? afterInput}) => _released
      ? Future.value({})
      : _registry._visibility(this, false, afterInput: afterInput);
  Future<SessionJson> close({Future<void>? afterInput}) {
    if (_released) return Future.value({});
    _released = true;
    _revision++;
    if (ownsBinding) _registry._closed.add(id);
    return _registry._close(this, afterInput);
  }

  Future<SessionJson> release({Future<void>? afterInput}) {
    if (_released) return Future.value({});
    _released = true;
    return _registry
        ._visibility(this, false, afterInput: afterInput, release: true)
        .catchError((Object error, StackTrace stack) {
          _released = false;
          Error.throwWithStackTrace(error, stack);
        });
  }
}
