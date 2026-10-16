import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

part 'clipboard_coordinator.g.dart';

/// Coordinates one explicitly enabled clipboard object while this application
/// is in the foreground. Existing values form a baseline rather than a write.
class ClipboardCoordinator with WidgetsBindingObserver {
  ClipboardCoordinator(this.controller) {
    WidgetsBinding.instance.addObserver(this);
    _events = controller.eventStream().listen(_event);
  }
  final AppController controller;
  StreamSubscription<Json>? _events;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  String _configuration = '';
  String? _target;
  String? _local;
  String? _remote;
  String? _pendingRemote;
  int _generation = 0;
  bool _initialized = false;
  bool _disposed = false;
  bool _pollQueued = false;
  bool _remoteQueued = false;
  bool _conflict = false;
  final Set<int> _activations = {};
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _active(String target, int generation) =>
      !_disposed &&
      !controller.isDisposed() &&
      _foreground &&
      _target == target &&
      _generation == generation &&
      controller.snapshot().settings['clipboardSync'] == true;

  void _enqueue(Future<void> Function() work) {
    final generation = _generation;
    _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await work();
      } catch (error) {
        if (!_disposed && generation == _generation) _failed(error);
      }
    });
  }

  void configure() {
    final enabled = controller.snapshot().settings['clipboardSync'] == true;
    final mode = value(
      controller.snapshot().settings,
      'clipboardMode',
      'follow',
    );
    final candidate = mode == 'fixed'
        ? value(controller.snapshot().settings, 'clipboardDevice')
        : controller.snapshot().focusedDeviceId;
    final connected =
        candidate != null &&
        candidate.isNotEmpty &&
        controller.snapshot().devices.any(
          (d) => d['id'] == candidate && d['status'] == 'connected',
        );
    final configuration = '$enabled:$mode:$candidate:$connected:$_foreground';
    if (_disposed || configuration == _configuration) return;
    _configuration = configuration;
    final generation = ++_generation;
    _pendingRemote = null;
    _timer?.cancel();
    _timer = null;
    final target = enabled && connected ? candidate : null;
    if (target != _target || !enabled) {
      _initialized = false;
      _pendingRemote = null;
      _local = null;
      _remote = null;
      _conflict = false;
    }
    _target = target;
    if (!enabled) {
      controller.updateClipboardState('disabled');
    } else if (target == null) {
      controller.updateClipboardState('waitingDevice');
    } else if (!_foreground) {
      controller.updateClipboardState('waitingForeground');
    } else {
      controller.updateClipboardState('checking');
      _scheduleActivation(target, generation);
    }
  }

  void _scheduleActivation(String target, int generation) {
    if (!_activations.add(generation)) return;
    _enqueue(() async {
      try {
        await _activate(target, generation);
      } finally {
        _activations.remove(generation);
      }
    });
  }

  Future<String?> _readLocal(String target, int generation) async {
    if (!_active(target, generation)) return null;
    controller.recordClipboardRead();
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  Future<void> _activate(String target, int generation) async {
    if (!_active(target, generation)) return;
    try {
      final local = await _readLocal(target, generation);
      if (!_active(target, generation)) return;
      final result = await controller
          .request('clipboard.get', {'deviceId': target})
          .timeout(const Duration(seconds: 25));
      if (!_active(target, generation)) return;
      if (result['text'] is! String || result['available'] == false) {
        throw StateError(value(result, 'reason', '尚未获得设备的文字剪贴板。'));
      }
      final remote = result['text'] as String;
      if (!_initialized) {
        _local = local;
        _remote = remote;
        _initialized = true;
      } else {
        final localChanged = local != _local;
        final remoteChanged = remote != _remote;
        if (localChanged && remoteChanged && local != remote) {
          _local = local;
          _remote = remote;
          _markConflict();
        } else if (localChanged && local != null && local != remote) {
          await _sendLocal(target, generation, local);
        } else if (remoteChanged && local != remote) {
          await _writeLocal(target, generation, remote);
        } else {
          _local = local;
          _remote = remote;
        }
      }
      if (!_active(target, generation) || !_initialized) return;
      _watching();
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _schedulePoll(),
      );
      _scheduleRemote();
    } catch (error) {
      if (_active(target, generation)) _failed(error);
    }
  }

  void _schedulePoll() {
    final target = _target;
    final generation = _generation;
    if (target == null ||
        !_initialized ||
        !_active(target, generation) ||
        _pollQueued) {
      return;
    }
    _pollQueued = true;
    _enqueue(() async {
      try {
        if (!_active(target, generation) || !_initialized) return;
        final current = await _readLocal(target, generation);
        if (!_active(target, generation) ||
            !_initialized ||
            current == _local) {
          return;
        }
        if (current == null || current == _remote) {
          _local = current;
          return;
        }
        await _sendLocal(target, generation, current);
      } finally {
        _pollQueued = false;
      }
    });
  }

  void _event(Json event) {
    if (_disposed || !_foreground || event['deviceId'] != _target) return;
    final data = event['data'] is Map<Object?, Object?>
        ? jsonObject(event['data'])
        : <String, dynamic>{};
    if (event['type'] == 'clipboard.unavailable') {
      _generation++;
      _failed(StateError(value(data, 'reason', '设备当前不允许访问剪贴板。')));
    } else if (event['type'] == 'clipboard.changed' &&
        data['text'] is String &&
        data['available'] != false &&
        data['live'] != false) {
      _pendingRemote = data['text'] as String;
      if (!_initialized && _target != null) {
        final target = _target!;
        final generation = _generation;
        _scheduleActivation(target, generation);
      } else {
        _scheduleRemote();
      }
    }
  }

  void _scheduleRemote() {
    final target = _target;
    final generation = _generation;
    if (target == null ||
        !_initialized ||
        _pendingRemote == null ||
        _remoteQueued ||
        !_active(target, generation)) {
      return;
    }
    _remoteQueued = true;
    _enqueue(() async {
      try {
        while (_pendingRemote != null &&
            _active(target, generation) &&
            _initialized) {
          final remote = _pendingRemote!;
          _pendingRemote = null;
          if (remote == _remote) continue;
          final local = await _readLocal(target, generation);
          if (!_active(target, generation)) return;
          if (local != _local && local != remote) {
            _local = local;
            _remote = remote;
            _markConflict();
          } else {
            await _writeLocal(target, generation, remote);
          }
        }
      } finally {
        _remoteQueued = false;
        if (_pendingRemote != null) _scheduleRemote();
      }
    });
  }

  Future<void> _sendLocal(String target, int generation, String text) async {
    if (!_active(target, generation)) return;
    _local = text;
    _remote = text; // The Binder echo can arrive before the request completes.
    controller.recordClipboardSend();
    final result = await controller
        .request('clipboard.set', {'deviceId': target, 'text': text})
        .timeout(const Duration(seconds: 25));
    if (!_active(target, generation)) return;
    if (result['applied'] != true) {
      throw StateError(value(result, 'reason', '设备尚未确认剪贴板写入结果，请主动核对。'));
    }
    _conflict = false;
    _watching();
  }

  Future<void> _writeLocal(String target, int generation, String text) async {
    if (!_active(target, generation)) return;
    _local = text;
    _remote = text;
    controller.recordClipboardWrite();
    await Clipboard.setData(ClipboardData(text: text));
    if (!_active(target, generation)) return;
    _conflict = false;
    _watching();
  }

  void _markConflict() {
    _conflict = true;
    controller.updateClipboardState(
      'needsReview',
      '两端剪贴板都已变化，尚未自动覆盖。请主动选择发送或获取。',
    );
  }

  void _watching() {
    if (!_conflict) controller.updateClipboardState('watching');
  }

  void _failed(Object error) {
    _timer?.cancel();
    _timer = null;
    _initialized = false;
    _pendingRemote = null;
    final message = switch (error) {
      RequestFailure(code: 'clipboard_locked') => '设备已锁定，请在原手机上解锁后重新核对。',
      RequestFailure(code: 'permission_denied') => '设备系统暂不允许访问剪贴板，请在原手机上处理。',
      RequestFailure(code: 'clipboard_not_text') => '设备当前是非文字剪贴板，未自动同步。',
      RequestFailure(:final message) => message,
      PlatformException(:final message) => message ?? '本机系统暂不允许访问剪贴板。',
      TimeoutException() => '剪贴板核对超时，请主动确认两端内容。',
      StateError(:final message) => message,
      _ => '剪贴板同步未完成，请主动核对两端内容。',
    };
    controller.updateClipboardState('limited', message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => configure();
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

@Riverpod(keepAlive: true)
ClipboardCoordinator clipboardCoordinator(Ref ref) {
  final controller = ref.watch(appControllerProvider.notifier);
  final coordinator = ClipboardCoordinator(controller);
  ref.listen(
    appControllerProvider.select(
      (state) => (state.settings, state.devices, state.focusedDeviceId),
    ),
    (_, next) => coordinator.configure(),
  );
  ref.onDispose(coordinator.dispose);
  Future<void>.microtask(coordinator.configure);
  return coordinator;
}
