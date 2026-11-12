import 'package:scrcpy_connect/core/media/models/video_session_view.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/clipboard/models/clipboard_sync_state.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/current_device_notifier.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_focus_notifier.dart';
import 'package:scrcpy_connect/core/lifecycle/state_subscription_provider.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

part 'clipboard_sync_notifier.g.dart';

/// 同步状态、计数和资源由同一个 scope 所有者维护。
@Riverpod(keepAlive: true)
class ClipboardSyncNotifier extends _$ClipboardSyncNotifier {
  late _ClipboardCoordinator _coordinator;
  bool _foreground = false;
  bool _focused = true;

  @override
  ClipboardSyncState build() {
    final clipboard = ref.watch(remoteClipboardProvider);
    final session = ref.watch(stateSubscriptionProvider);
    _ClipboardContext? context() {
      if (!ref.mounted ||
          session.disposed ||
          !identical(ref.read(remoteClipboardProvider), clipboard)) {
        return null;
      }
      final status = ref.read(recoveryStateProvider);
      final target = ref.read(currentDeviceProvider);
      final device = ref
          .read(deviceListProvider)
          .devices
          .where((device) => device.id == target)
          .firstOrNull;
      final focus = ref.read(clipboardFocusProvider);
      return (
        enabled:
            target != null &&
            ref
                    .read(preferencesProvider)
                    .values
                    .deviceSettings[target]
                    ?.clipboardSync ==
                true,
        deviceId: target,
        connectionId: device?.connectionId,
        connected: device?.status == DeviceConnectionStatus.connected,
        sessionId: focus?.deviceId == target ? focus?.sessionId : null,
        reconciliationPending: status.reconciliationPending,
        reconciliationError: status.reconciliationError,
      );
    }

    late final _ClipboardCoordinator coordinator;
    bool current() => ref.mounted && identical(_coordinator, coordinator);
    coordinator = _ClipboardCoordinator(
      clipboard,
      session.events,
      context,
      (status, error) {
        if (current()) state = state.copyWith(status: status, error: error);
      },
      (operation) {
        if (!current()) return;
        state = switch (operation) {
          _ClipboardOperation.read => state.copyWith(
            readCount: state.readCount + 1,
          ),
          _ClipboardOperation.write => state.copyWith(
            writeCount: state.writeCount + 1,
          ),
          _ClipboardOperation.send => state.copyWith(
            sendCount: state.sendCount + 1,
          ),
        };
      },
    );
    _coordinator = coordinator;
    void configure() {
      // 原子状态交付期间不准入；全部投影提交后才重新检查同步资格。
      if (!session.applyingState) coordinator.configure();
    }

    ref.listen(
      deviceListProvider.select((state) => state.devices),
      (_, _) => configure(),
    );
    ref.listen(
      preferencesProvider.select((state) => state.values.deviceSettings),
      (_, _) => configure(),
    );
    ref.listen(
      recoveryStateProvider.select(
        (state) => (state.reconciliationPending, state.reconciliationError),
      ),
      (_, _) => configure(),
    );
    ref.listen(currentDeviceProvider, (_, _) => configure());
    ref.listen(clipboardFocusProvider, (_, _) => configure());
    final commits = session.stateCommits.listen((_) => coordinator.configure());
    ref.onDispose(() => unawaited(commits.cancel()));
    ref.onDispose(coordinator.dispose);
    scheduleMicrotask(() {
      if (current()) {
        coordinator.setVisibility(foreground: _foreground, focused: _focused);
      }
    });
    return const ClipboardSyncState();
  }

  void setVisibility({bool? foreground, bool? focused}) {
    if (foreground != null) _foreground = foreground;
    if (focused != null) _focused = focused;
    _coordinator.setVisibility(foreground: foreground, focused: focused);
  }
}

enum _ClipboardOperation { read, write, send }

typedef _ClipboardContext = ({
  bool enabled,
  String? deviceId,
  String? connectionId,
  bool connected,
  String? sessionId,
  bool reconciliationPending,
  String? reconciliationError,
});

/// 当前获焦控制画面只同步基线之后的新复制，恢复不回灌任一端旧值。
class _ClipboardCoordinator {
  _ClipboardCoordinator(
    this.clipboard,
    Stream<Json> events,
    this.readContext,
    this.onStatus,
    this.onOperation,
  ) {
    _events = events.listen(_event);
    _releaseAdmission = clipboard.bindClipboardAdmission(
      (device, session, generation) =>
          session == _sessionId && _active(device, generation),
    );
  }
  final _ClipboardContext? Function() readContext;
  final RemoteClipboard clipboard;
  final void Function(ClipboardSyncStatus, String?) onStatus;
  final void Function(_ClipboardOperation) onOperation;
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
  ClipboardCapture? _capture;
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
  bool _foreground = false;
  bool _active(String target, int generation) {
    if (_disposed) return false;
    final context = readContext();
    return context != null &&
        !_reconciling &&
        !context.reconciliationPending &&
        _foreground &&
        _viewFocused &&
        _sessionId != null &&
        context.sessionId == _sessionId &&
        _target == target &&
        _generation == generation &&
        context.deviceId == target &&
        context.connected &&
        context.connectionId == _connectionId &&
        context.enabled;
  }

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
    final context = readContext();
    if (context == null) return;
    if (_reconciling || context.reconciliationPending) {
      _suspendForVerification(context.reconciliationError);
      return;
    }
    final candidate = context.deviceId;
    final enabled = context.enabled;
    final connected =
        candidate != null && candidate.isNotEmpty && context.connected;
    final connectionId = context.connectionId;
    final configuration = (
      enabled: enabled,
      deviceId: candidate,
      connectionId: connectionId,
      connected: connected,
      foreground: _foreground && _viewFocused,
      sessionId: context.sessionId,
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
      onStatus(ClipboardSyncStatus.disabled, null);
    } else if (target == null) {
      onStatus(ClipboardSyncStatus.waitingDevice, null);
    } else if (!_foreground || !_viewFocused || _sessionId == null) {
      onStatus(ClipboardSyncStatus.waitingForeground, null);
    } else {
      onStatus(ClipboardSyncStatus.checking, null);
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
    if (readContext()?.enabled == true) {
      onStatus(
        ClipboardSyncStatus.waitingVerification,
        reason ?? '正在核验设备状态，剪贴板同步已暂停。',
      );
    } else {
      onStatus(ClipboardSyncStatus.disabled, null);
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
    onOperation(_ClipboardOperation.read);
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  Future<void> _activate(String target, int generation) async {
    if (!_active(target, generation)) return;
    try {
      final result = await clipboard
          .readClipboard(
            ClipboardTarget.window(
              deviceId: target,
              sessionId: _sessionId!,
              synchronizationGeneration: generation,
            ),
          )
          .timeout(const Duration(seconds: 25));
      if (!_active(target, generation)) return;
      final remote = result.text;
      final local = await _readLocal(target, generation);
      if (!_active(target, generation)) return;
      if (local == null) throw StateError('无法读取本机文字剪贴板，自动同步已暂停。');
      _capture = result.capture;
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
        if (!_active(target, generation) || !_initialized) {
          return;
        }
        if (current == null) {
          throw StateError('无法读取本机文字剪贴板，自动同步已暂停。');
        }
        if (current == _local) return;
        if (current == _remote) {
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
    if (event['type'] == 'device.disconnect.requested' &&
        event['deviceId'] == _target) {
      _generation++;
      _target = null;
      _configuration = null;
      _initialized = false;
      _pendingRemote = null;
      _timer?.cancel();
      _timer = null;
      onStatus(ClipboardSyncStatus.waitingDevice, null);
      return;
    }
    if (event['type'] == 'state.resync' ||
        event['type'] == 'state.resync.failed') {
      _suspendForVerification(readContext()?.reconciliationError);
      return;
    }
    if (event['type'] == 'state.resynced') {
      if (readContext()?.reconciliationPending == true) return;
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
        readContext()?.reconciliationPending == true ||
        event['deviceId'] != _target) {
      return;
    }
    final data = event['data'] is Map<Object?, Object?>
        ? jsonObject(event['data'])
        : <String, dynamic>{};
    if (event['data'] case VideoSessionView(:final session)
        when session.sessionId == _sessionId &&
            session.deviceId == _target &&
            (session.captureRef != _capture?.reference ||
                session.captureGeneration != _capture?.generation)) {
      _configuration = null;
      configure();
      return;
    }
    if (event['type'] == 'clipboard.changed' &&
        (data['sessionId'] != _sessionId ||
            data['captureRef'] != _capture?.reference ||
            data['captureGeneration'] != _capture?.generation)) {
      return;
    }
    final connectionId = data['connectionId'] ?? event['connectionId'];
    if (connectionId != null && connectionId != _connectionId) return;
    if (event['type'] == 'clipboard.unavailable') {
      _failed(StateError(value(data, 'reason', '设备当前不允许访问剪贴板。')));
    } else if (event['type'] == 'clipboard.changed' &&
        _initialized &&
        data['text'] is String &&
        data['available'] != false &&
        data['live'] != false) {
      _pendingRemote = data['text'] as String;
      _scheduleRemote();
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
    onOperation(_ClipboardOperation.send);
    await clipboard
        .writeClipboard(
          ClipboardTarget.window(
            deviceId: target,
            sessionId: _sessionId!,
            capture: _capture,
            synchronizationGeneration: generation,
          ),
          text,
        )
        .timeout(const Duration(seconds: 25));
    if (!_active(target, generation)) return;
    _watching();
  }

  Future<void> _writeLocal(String target, int generation, String text) async {
    if (!_active(target, generation)) return;
    _local = text;
    _remote = text;
    onOperation(_ClipboardOperation.write);
    await Clipboard.setData(ClipboardData(text: text));
    if (!_active(target, generation)) return;
    final confirmed = await _readLocal(target, generation);
    if (!_active(target, generation)) return;
    if (confirmed != text) {
      throw const RequestFailure(
        'clipboard_write_unverified',
        '本机剪贴板写入尚未核验一致，已暂停自动同步；请核对系统粘贴权限后重试。',
      );
    }
    _watching();
  }

  void _watching() => onStatus(ClipboardSyncStatus.watching, null);

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
    onStatus(ClipboardSyncStatus.limited, message);
  }

  void setVisibility({bool? foreground, bool? focused}) {
    if (foreground != null) _foreground = foreground;
    if (focused != null) _viewFocused = focused;
    configure();
  }

  void dispose() {
    _disposed = true;
    _releaseAdmission();
    _generation++;
    _timer?.cancel();
    _events?.cancel();
  }
}
