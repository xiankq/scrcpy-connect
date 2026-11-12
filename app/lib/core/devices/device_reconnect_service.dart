import 'connection_change.dart';

import 'dart:async';
import 'dart:math';

import 'package:scrcpy_connect/core/devices/connection_policy.dart';

typedef ReconnectJson = Map<String, dynamic>;

/// 自动重连只需要快照和精确尝试租约，不具有执行任意应用命令的权限。
abstract interface class DeviceReconnectHost {
  Future<ReconnectJson> readSnapshot();
  Future<void> setOwner(String ownerId, bool active);
  Future<void> connect(String deviceId, String attemptId, String ownerId);
  Future<void> cancel(String attemptId);
}

typedef ReconnectTimer = Timer Function(Duration delay, void Function() run);

/// 调度应用重试；设备所有者的租约隔离待定尝试，已交付连接保持独立生命周期。
class DeviceReconnectService {
  DeviceReconnectService({
    required this.host,
    required this.policy,
    ReconnectTimer? schedule,
    String? ownerPrefix,
  }) : _schedule = schedule ?? Timer.new,
       _ownerPrefix = ownerPrefix ?? _randomOwner();

  final DeviceReconnectHost host;
  final ConnectionPolicy policy;
  final ReconnectTimer _schedule;
  final String _ownerPrefix;
  final _devices = <String, ReconnectJson>{};
  final _work = <String, _ReconnectWork>{};
  final _stopped = <String>{};
  bool _hostStopped = false;
  final _manuallyResumed = <String>{};
  final _commands = <String, int>{};
  bool _backgroundKeepAlive = false;
  Future<void> _ownership = Future<void>.value();
  Future<void>? _starting, _refreshing;
  var _refreshInterrupted = Completer<void>();
  String? _owner;
  bool _ownerReady = false,
      _known = false,
      _uncertain = false,
      _recovering = false;
  bool _visible = true, _disposed = false;
  int _sequence = -1, _lease = 0, _attempt = 0, _pauses = 0;

  static String _randomOwner() {
    final random = Random.secure();
    return List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16),
    ).join('-');
  }

  Future<void> start() {
    policy.validate();
    return _starting ??= refresh();
  }

  /// 初次附着、非事件命令回执与缺口恢复共用应用快照；旧回复不能覆盖新设备事件。
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _refreshing ??= _readSnapshot().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _readSnapshot() async {
    for (var attempt = 0; attempt < 4 && !_disposed; attempt++) {
      final snapshot = await host.readSnapshot();
      if (_disposed) return;
      final sequence = snapshot['sequence'];
      if (sequence is! int || sequence < _sequence) continue;
      _snapshot(snapshot);
      return;
    }
    if (!_disposed) {
      throw StateError('No current device snapshot for reconnection');
    }
  }

  void _snapshot(ReconnectJson snapshot) {
    final sequence = snapshot['sequence'];
    if (_disposed || sequence is! int || sequence < _sequence) return;
    _sequence = sequence;
    _backgroundKeepAlive =
        _object(snapshot['settings'])['backgroundKeepAlive'] == true;
    _replaceDevices(snapshot['devices']);
    _known = true;
    _uncertain = _recovering;
    _sync();
  }

  void handleEvent(ReconnectJson event) {
    if (_disposed) return;
    final type = event['type'];
    if (type == 'session.frame' || type == 'runtime.heartbeat') return;
    if (type == 'state.resync' || type == 'state.resync.failed') {
      _recovering = true;
      _uncertain = true;
      if (!_refreshInterrupted.isCompleted) _refreshInterrupted.complete();
      _sync();
      return;
    }
    final data = _object(event['data']);
    if (type == 'state.resynced') {
      if (_recovering) _refreshInterrupted = Completer<void>();
      _recovering = false;
      _snapshot(data);
      return;
    }
    final sequence = event['sequence'];
    if (sequence is! int || sequence <= _sequence) return;
    _sequence = sequence;
    if (type == 'devices.changed') {
      if (data['devices'] is List) {
        _replaceDevices(data['devices']);
      } else {
        _quiet(refresh());
      }
    } else if (type == 'device.changed') {
      final id = data['id'];
      if (id is String && _devices.containsKey(id)) _devices[id] = data;
    } else if (type == 'settings.changed') {
      _backgroundKeepAlive = data['backgroundKeepAlive'] == true;
    } else if (type == 'adb.discovery.changed') {
      // 新 DNS 结果可重置重试延迟，但不能改变授权意图。
      for (final entry in _devices.entries) {
        if (entry.value['guid'] == data['guid']) {
          final pending = _work[entry.key];
          if (pending != null && !pending.running) {
            pending.timer?.cancel();
            _work.remove(entry.key);
          }
        }
      }
    } else if (type == 'connections.stopped') {
      stopAutomaticConnections();
      _quiet(refresh());
    }
    _sync();
  }

  void setVisible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    _sync();
  }

  /// 本地持久偏好由偏好所有者明确更新。
  void updateBackgroundKeepAlive(bool enabled) {
    if (_disposed) return;
    _backgroundKeepAlive = enabled;
    _sync();
  }

  /// 系统 Task Manager 或显式停止也约束附着期间的快照，不能因新发现设备 ID 而撤销。
  void stopAutomaticConnections() {
    _hostStopped = true;
    _manuallyResumed.clear();
    _stopped.addAll(_devices.keys);
    // 换租约会等待旧释放回执；不能让这段等待延后旧定时器与在途尝试的撤销。
    for (final id in _work.keys.toList()) {
      _cancel(id);
    }
    // 宿主同时撤销设备所有者中的旧租约；本地不能继续把旧 ownerId 当成有效权限。
    // 新技术租约不恢复设备意图，只有后续明确手动连接才解除该设备的停止状态。
    _releaseOwner();
    _sync();
  }

  /// 用户命令前调用，防止迟到快照重放停止状态。
  /// 即使命令结果未知也执行返回的完成函数，下次重试始终重新读取应用投影。
  Future<void> Function() beginChange(ConnectionChange change) {
    final id = change.deviceId;
    final stop = change.stop;
    final manual = change.manual;
    final authorityChange = change.authorityChange;
    final affected = stop || manual;
    if (affected && id != null) {
      _commands[id] = (_commands[id] ?? 0) + 1;
      if (stop) {
        _stopped.add(id);
        _manuallyResumed.remove(id);
      }
      if (manual) {
        _stopped.remove(id);
        _manuallyResumed.add(id);
      }
      _cancel(id);
    }
    if (authorityChange) _pauses++;
    _sync();
    return () async {
      if (_disposed) return;
      if ((affected || authorityChange) && !_recovering) {
        // 核验期间由 state.resynced 交付权威快照；清理不能反向等待阻塞的核验读取。
        // 核验失败仍保留 _uncertain，不能借跳过刷新恢复自动连接。
        try {
          // 刷新开始后也可能进入核验；仅释放命令收尾，原刷新仍由 _refreshing 持有。
          final interrupted = _refreshInterrupted.future;
          await Future.any([refresh(), interrupted]);
        } catch (_) {
          // 恢复失败不能准入新的自动尝试。
          _uncertain = true;
        }
      }
      if (affected && id != null) {
        final count = (_commands[id] ?? 1) - 1;
        if (count == 0) {
          _commands.remove(id);
        } else {
          _commands[id] = count;
        }
      }
      if (authorityChange) _pauses--;
      _sync();
    };
  }

  bool get _allowed =>
      !_disposed &&
      _known &&
      !_uncertain &&
      _pauses == 0 &&
      policy.reconnectEnabled &&
      (_visible || _backgroundKeepAlive);

  bool _eligible(String id, ReconnectJson device) =>
      !_stopped.contains(id) &&
      !_commands.containsKey(id) &&
      device['autoReconnect'] == true &&
      device['transport'] != 'usb' &&
      device['status'] == 'offline';

  void _replaceDevices(Object? value) {
    if (value is! List) return;
    _devices.clear();
    for (final entry in value) {
      final device = _object(entry);
      final id = device['id'];
      if (id is String) _devices[id] = device;
    }
    if (_hostStopped) {
      _stopped.addAll(
        _devices.keys.where((id) => !_manuallyResumed.contains(id)),
      );
    }
  }

  void _sync() {
    if (!_allowed) {
      for (final id in _work.keys.toList()) {
        // 暂停调度只释放技术租约；用户取消表达停止连接，会清除持久连接意图。
        _cancel(id, stopConnection: false);
      }
      _releaseOwner();
      return;
    }
    if (_owner == null) {
      _acquireOwner();
      return;
    }
    if (!_ownerReady) return;
    for (final id in _work.keys.toList()) {
      final device = _devices[id];
      final work = _work[id]!;
      // 连接会在命令 Future 返回前同步发布成功；此时只结束调度责任。
      // 再发送同一 attemptId 的取消会反向撤回已经实际交付的连接。
      if (device?['status'] == 'connected' &&
          !_stopped.contains(id) &&
          !_commands.containsKey(id)) {
        _work.remove(id);
        work.timer?.cancel();
        continue;
      }
      // 本模块的在途连接会在完成前发布 connecting。
      final ownsConnecting =
          work.running &&
          device?['status'] == 'connecting' &&
          device?['autoReconnect'] == true &&
          !_stopped.contains(id) &&
          !_commands.containsKey(id);
      if (device == null || (!_eligible(id, device) && !ownsConnecting)) {
        // 终止状态由连接层发布；退出调度不能再用主动断开覆盖失败原因。
        _cancel(id, stopConnection: false);
      }
    }
    for (final entry in _devices.entries) {
      if (_eligible(entry.key, entry.value) && !_work.containsKey(entry.key)) {
        _scheduleAttempt(entry.key, 0);
      }
    }
  }

  void _acquireOwner() {
    final owner = '$_ownerPrefix-${++_lease}';
    _owner = owner;
    _ownerReady = false;
    _ownership = _ownership.catchError((Object _) {}).then((_) async {
      if (_disposed || _owner != owner || !_allowed) return;
      try {
        await host.setOwner(owner, true);
      } catch (_) {
        if (_owner == owner) {
          _uncertain = true;
          _sync();
        }
        return;
      }
      if (!_disposed && _owner == owner && _allowed) {
        _ownerReady = true;
        _sync();
      }
    });
    _quiet(_ownership);
  }

  void _releaseOwner() {
    final owner = _owner;
    if (owner == null) return;
    _owner = null;
    _ownerReady = false;
    _ownership = _ownership.catchError((Object _) {}).then((_) async {
      await host.setOwner(owner, false);
    });
    _quiet(_ownership);
  }

  void _scheduleAttempt(String id, int failures) {
    final work = _ReconnectWork(failures);
    _work[id] = work;
    final delay = failures == 0 ? Duration.zero : _delay(failures);
    work.timer = _schedule(delay, () {
      work.timer = null;
      if (!_allowed ||
          !_ownerReady ||
          !identical(_work[id], work) ||
          !_eligible(id, _devices[id] ?? {})) {
        return;
      }
      work.running = true;
      work.attemptId = '$_owner-a${++_attempt}';
      _quiet(_connect(id, work, _owner!));
    });
  }

  Future<void> _connect(String id, _ReconnectWork work, String owner) async {
    try {
      await host.connect(id, work.attemptId!, owner);
    } catch (_) {
      // 通过设备状态区分取消、信任失效与可重试失败；不解析展示文本决定产品资格。
    }
    if (_disposed || !identical(_work[id], work) || _owner != owner) return;
    work.running = false;
    try {
      await refresh();
    } catch (_) {
      _uncertain = true;
    }
    if (_disposed || !identical(_work[id], work) || _owner != owner) return;
    _work.remove(id);
    if (_allowed && _eligible(id, _devices[id] ?? {})) {
      _scheduleAttempt(id, work.failures + 1);
    }
    _sync();
  }

  Duration _delay(int failures) {
    final maximum = policy.reconnectMaxDelay.inMilliseconds;
    var milliseconds = policy.reconnectInitialDelay.inMilliseconds;
    for (var count = 1; count < failures && milliseconds < maximum; count++) {
      milliseconds = min(maximum, milliseconds * 2);
    }
    return Duration(milliseconds: min(maximum, milliseconds));
  }

  void _cancel(String id, {bool stopConnection = true}) {
    final work = _work.remove(id);
    work?.timer?.cancel();
    if (stopConnection && work?.attemptId != null) {
      final attempt = work!.attemptId!;
      _quiet(host.cancel(attempt));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return _ownership;
    _disposed = true;
    if (!_refreshInterrupted.isCompleted) _refreshInterrupted.complete();
    _sync();
    try {
      await _ownership;
    } catch (_) {
      // 宿主失联时无法确认释放，仍继续清理本地所有者。
    }
  }

  static ReconnectJson _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static void _quiet(Future<dynamic> operation) {
    unawaited(
      operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
}

class _ReconnectWork {
  _ReconnectWork(this.failures);
  final int failures;
  Timer? timer;
  String? attemptId;
  bool running = false;
}
