import 'dart:async';
import 'dart:math';

import 'connection_policy.dart';

typedef ReconnectJson = Map<String, dynamic>;
typedef ReconnectRequest = Future<ReconnectJson> Function(
  String command,
  ReconnectJson params,
);
typedef ReconnectTimer = Timer Function(Duration delay, void Function() run);

/// Application retry scheduling. Native leases fence queued and running work;
/// admitted device transports retain their independent native lifetime.
class ReconnectionCoordinator {
  ReconnectionCoordinator({
    required this.request,
    required this.policy,
    ReconnectTimer? schedule,
    String? ownerPrefix,
  }) : _schedule = schedule ?? Timer.new,
       _ownerPrefix = ownerPrefix ?? _randomOwner();

  final ReconnectRequest request;
  final ConnectionPolicy policy;
  final ReconnectTimer _schedule;
  final String _ownerPrefix;
  final _devices = <String, ReconnectJson>{};
  final _work = <String, _ReconnectWork>{};
  final _stopped = <String>{};
  final _commands = <String, int>{};
  ReconnectJson _settings = {};
  Future<void> _ownership = Future<void>.value();
  Future<void>? _starting, _refreshing;
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

  /// Initial attachment and non-event command receipts use the same native
  /// snapshot as gap recovery. An older reply cannot undo newer device events.
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _refreshing ??= _readSnapshot().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _readSnapshot() async {
    for (var attempt = 0; attempt < 4 && !_disposed; attempt++) {
      final snapshot = await request('state.snapshot', {});
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
    _settings = _object(snapshot['settings']);
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
      _sync();
      return;
    }
    final data = _object(event['data']);
    if (type == 'state.resynced') {
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
      _settings = data;
    } else if (type == 'adb.discovery.changed') {
      // Fresh DNS answers invalidate retry delay, never authorization intent.
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
      _stopped.addAll(_devices.keys);
      _quiet(refresh());
    }
    _sync();
  }

  void setVisible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    _sync();
  }

  /// Called before user commands, so delayed snapshots cannot replay a stop.
  /// The returned completion runs after the command even when its result is
  /// unknown; the next retry always starts from a fresh native projection.
  Future<void> Function() beforeRequest(String command, ReconnectJson params) {
    final rawId = params['deviceId'];
    String? id = rawId is String ? rawId : null;
    final connectionStop =
        command == 'activities.stop' &&
        params['activityId'] is String &&
        (params['activityId'] as String).startsWith('connection:');
    if (connectionStop) id = (params['activityId'] as String).substring(11);
    final stop =
        command == 'devices.disconnect' ||
        command == 'devices.forget' ||
        connectionStop ||
        (command == 'devices.cancel' && id != null);
    final manual = const [
      'devices.connect',
      'devices.pair',
      'devices.pair.qr',
      'devices.usb',
      'devices.wireless',
    ].contains(command);
    final authorityChange =
        (command.startsWith('identity.') && !command.endsWith('.get')) ||
        command == 'settings.import';
    final affected = stop || manual;
    if (affected && id != null) {
      _commands[id] = (_commands[id] ?? 0) + 1;
      if (stop) _stopped.add(id);
      if (manual) _stopped.remove(id);
      _cancel(id);
    }
    if (authorityChange) _pauses++;
    _sync();
    return () async {
      if (_disposed) return;
      if (affected || authorityChange) {
        try {
          await refresh();
        } catch (_) {
          // Failed recovery cannot authorize another automatic attempt.
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
      (_visible ||
          (_settings['backgroundConnection'] == true &&
              _settings['backgroundKeepAlive'] == true));

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
  }

  void _sync() {
    if (!_allowed) {
      for (final id in _work.keys.toList()) {
        _cancel(id);
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
      // Our own in-flight attempt publishes connecting before it completes.
      final ownsConnecting =
          work.running &&
          device?['status'] == 'connecting' &&
          device?['autoReconnect'] == true &&
          !_stopped.contains(id) &&
          !_commands.containsKey(id);
      if (device == null || (!_eligible(id, device) && !ownsConnecting)) {
        _cancel(id);
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
        await request('devices.reconnect.owner', {
          'ownerId': owner,
          'active': true,
        });
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
      await request('devices.reconnect.owner', {
        'ownerId': owner,
        'active': false,
      });
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
      await request('devices.connect', {
        'deviceId': id,
        'attemptId': work.attemptId,
        'automatic': true,
        'ownerId': owner,
      });
    } catch (_) {
      // Native state distinguishes cancellation, lost trust and a retryable
      // failure. No display-string error parsing decides product eligibility.
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

  void _cancel(String id) {
    final work = _work.remove(id);
    work?.timer?.cancel();
    if (work?.attemptId case final attempt?) {
      _quiet(request('devices.cancel', {'attemptId': attempt}));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return _ownership;
    _disposed = true;
    _sync();
    try {
      await _ownership;
    } catch (_) {
      // A lost host cannot acknowledge release; continue local owner cleanup.
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
