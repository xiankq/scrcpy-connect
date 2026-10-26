import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';

import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

part 'clipboard_coordinator.g.dart';

/// 当前获焦控制画面只同步基线之后的新复制，恢复不回灌任一端旧值。
class ClipboardCoordinator with WidgetsBindingObserver {
  ClipboardCoordinator(this.controller) {
    WidgetsBinding.instance.addObserver(this);
    _events = controller.eventStream().listen(_event);
    _releaseAdmission = controller.bindClipboardAdmission(
      (device, session, generation) =>
          session == _sessionId && _active(device, generation),
    );
  }
  final AppController controller;
  late final void Function() _releaseAdmission;
  StreamSubscription<Json>? _events;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  ({
    bool enabled,
    String? deviceId,
    String? connectionId,
    bool connected,
    bool foreground,
    String? sessionId,
  })?
  _configuration;
  bool _viewFocused = true;
  String? _sessionId;
  String? _captureRef;
  int? _captureGeneration;
  String? _target;
  String? _connectionId;
  String? _local;
  String? _remote;
  String? _pendingRemote;
  int _generation = 0;
  bool _initialized = false;
  bool _disposed = false;
  bool _pollQueued = false;
  bool _remoteQueued = false;
  bool _reconciling = false;
  final Set<int> _activations = {};
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool _active(String target, int generation) =>
      !_disposed &&
      !controller.isDisposed() &&
      !_reconciling &&
      !controller.snapshot().reconciliationPending &&
      _foreground &&
      _viewFocused &&
      _sessionId != null &&
      controller.clipboardSessionFor(target) == _sessionId &&
      _target == target &&
      _generation == generation &&
      controller.snapshot().focusedDeviceId == target &&
      controller.snapshot().devices.any(
        (device) =>
            device['id'] == target &&
            device['status'] == 'connected' &&
            device['connectionId'] == _connectionId,
      ) &&
      _enabled(target);

  bool _enabled(String? device) =>
      device != null &&
      jsonObject(
            jsonObject(
              controller.snapshot().settings['deviceSettings'],
            )[device],
          )['clipboardSync'] ==
          true;

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
    if (_disposed) return;
    if (_reconciling || controller.snapshot().reconciliationPending) {
      _suspendForVerification(controller.snapshot().reconciliationError);
      return;
    }
    final candidate = controller.snapshot().focusedDeviceId;
    final enabled = _enabled(candidate);
    final device = controller
        .snapshot()
        .devices
        .where((device) => device['id'] == candidate)
        .firstOrNull;
    final connected =
        candidate != null &&
        candidate.isNotEmpty &&
        device?['status'] == 'connected';
    final connectionId = device?['connectionId'] as String?;
    final configuration = (
      enabled: enabled,
      deviceId: candidate,
      connectionId: connectionId,
      connected: connected,
      foreground: _foreground && _viewFocused,
      sessionId: candidate == null
          ? null
          : controller.clipboardSessionFor(candidate),
    );
    if (_disposed || configuration == _configuration) return;
    _configuration = configuration;
    _initialized = false;
    final generation = ++_generation;
    _queue = Future<void>.value();
    _pollQueued = false;
    _remoteQueued = false;
    _pendingRemote = null;
    _timer?.cancel();
    _timer = null;
    final target = enabled && connected ? candidate : null;
    if (target != _target || connectionId != _connectionId || !enabled) {
      _initialized = false;
      _pendingRemote = null;
      _local = null;
      _remote = null;
    }
    _sessionId = configuration.sessionId;
    _target = target;
    _connectionId = connectionId;
    if (!enabled) {
      controller.updateClipboardState('disabled');
    } else if (target == null) {
      controller.updateClipboardState('waitingDevice');
    } else if (!_foreground || !_viewFocused || _sessionId == null) {
      controller.updateClipboardState('waitingForeground');
    } else {
      controller.updateClipboardState('checking');
      _scheduleActivation(target, generation);
    }
  }

  void _suspendForVerification([String? reason]) {
    _reconciling = true;
    _generation++;
    _configuration = null;
    _timer?.cancel();
    _timer = null;
    _initialized = false;
    _pendingRemote = null;
    _local = null;
    _remote = null;
    if (_enabled(controller.snapshot().focusedDeviceId)) {
      controller.updateClipboardState(
        'waitingVerification',
        reason ?? '正在核验设备状态，剪贴板同步已暂停。',
      );
    } else {
      controller.updateClipboardState('disabled');
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
      final result = await controller
          .execute(ApplicationCommand.clipboardGet, {
            'deviceId': target,
            'sessionId': _sessionId,
            'automatic': true,
            'clipboardGeneration': generation,
          })
          .timeout(const Duration(seconds: 25));
      if (!_active(target, generation)) return;
      if (result['text'] is! String || result['available'] == false) {
        throw StateError(value(result, 'reason', '尚未获得设备的文字剪贴板。'));
      }
      final remote = result['text'] as String;
      final local = await _readLocal(target, generation);
      if (!_active(target, generation)) return;
      if (local == null) throw StateError('无法读取本机文字剪贴板，自动同步已暂停。');
      _captureRef = result['captureRef'] as String?;
      _captureGeneration = result['captureGeneration'] as int?;
      _remote = remote;
      _local = local;
      _pendingRemote = null;
      _initialized = true;
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
        if (generation == _generation) _pollQueued = false;
      }
    });
  }

  void _event(Json event) {
    if (_disposed) return;
    if (event['type'] == 'clipboard.focus') {
      configure();
      return;
    }
    if (event['type'] == 'device.disconnect.requested' &&
        event['deviceId'] == _target) {
      _generation++;
      _target = null;
      _configuration = null;
      _initialized = false;
      _pendingRemote = null;
      _timer?.cancel();
      _timer = null;
      controller.updateClipboardState('waitingDevice');
      return;
    }
    if (event['type'] == 'state.resync' ||
        event['type'] == 'state.resync.failed') {
      _suspendForVerification(controller.snapshot().reconciliationError);
      return;
    }
    if (event['type'] == 'state.resynced') {
      if (controller.snapshot().reconciliationPending) return;
      _reconciling = false;
      _configuration = null;
      _initialized = false;
      _pendingRemote = null;
      _local = null;
      _remote = null;
      configure();
      return;
    }
    if (!_foreground ||
        _reconciling ||
        controller.snapshot().reconciliationPending ||
        event['deviceId'] != _target) {
      return;
    }
    final data = event['data'] is Map<Object?, Object?>
        ? jsonObject(event['data'])
        : <String, dynamic>{};
    if (event['type'] == 'session.updated' &&
        data['sessionId'] == _sessionId &&
        (data['captureRef'] != _captureRef ||
            data['captureGeneration'] != _captureGeneration)) {
      _configuration = null;
      configure();
      return;
    }
    if (event['type'] == 'clipboard.changed' &&
        (data['sessionId'] != _sessionId ||
            data['captureRef'] != _captureRef ||
            data['captureGeneration'] != _captureGeneration)) {
      return;
    }
    final connectionId = data['connectionId'] ?? event['connectionId'];
    if (connectionId != null && connectionId != _connectionId) return;
    if (event['type'] == 'clipboard.unavailable') {
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
          await _writeLocal(target, generation, remote);
        }
      } finally {
        if (generation == _generation) {
          _remoteQueued = false;
          if (_pendingRemote != null) _scheduleRemote();
        }
      }
    });
  }

  Future<void> _sendLocal(String target, int generation, String text) async {
    if (!_active(target, generation)) return;
    _local = text;
    _remote = text; // scrcpy listener 回声可能早于读回确认。
    controller.recordClipboardSend();
    final result = await controller
        .execute(ApplicationCommand.clipboardSet, {
          'deviceId': target,
          'sessionId': _sessionId,
          'expectedCaptureRef': _captureRef,
          'captureGeneration': _captureGeneration,
          'automatic': true,
          'clipboardGeneration': generation,
          'text': text,
        })
        .timeout(const Duration(seconds: 25));
    if (!_active(target, generation)) return;
    if (result['applied'] != true) {
      throw StateError(value(result, 'reason', '设备尚未确认剪贴板写入结果，请主动核对。'));
    }
    _watching();
  }

  Future<void> _writeLocal(String target, int generation, String text) async {
    if (!_active(target, generation)) return;
    _local = text;
    _remote = text;
    controller.recordClipboardWrite();
    await Clipboard.setData(ClipboardData(text: text));
    if (!_active(target, generation)) return;
    _watching();
  }

  void _watching() => controller.updateClipboardState('watching');

  void _failed(Object error) {
    // A UI timeout does not cancel the original native Future. Revoke its admission.
    _generation++;
    _queue = Future<void>.value();
    _pollQueued = false;
    _remoteQueued = false;
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

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    _viewFocused = event.state == ViewFocusState.focused;
    configure();
  }

  void dispose() {
    _disposed = true;
    _releaseAdmission();
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
      (state) => (
        state.settings,
        state.devices,
        state.focusedDeviceId,
        state.reconciliationPending,
        state.reconciliationError,
      ),
    ),
    (_, next) => coordinator.configure(),
  );
  ref.onDispose(coordinator.dispose);
  Future<void>.microtask(coordinator.configure);
  return coordinator;
}
