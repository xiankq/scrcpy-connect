import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

part 'system_notifications.g.dart';

enum SystemNotificationKind { notification, call }

const systemNotificationIdMin = 100000;
const systemNotificationIdMax = 199999;

@immutable
class SystemNotificationStatus {
  const SystemNotificationStatus({
    this.supported = false,
    this.permissionGranted,
    this.notificationChannelEnabled,
    this.callChannelEnabled,
    this.canRequest = false,
    this.canOpenSettings = false,
    this.reason = '',
  });
  final bool supported;
  final bool? permissionGranted;
  final bool? notificationChannelEnabled;
  final bool? callChannelEnabled;
  final bool canRequest;
  final bool canOpenSettings;
  final String reason;
}

@immutable
class SystemNotice {
  const SystemNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.payload,
  });
  final int id;
  final SystemNotificationKind kind;
  final String title;
  final String body;
  final String payload;
}

abstract interface class SystemNotificationSink {
  Stream<String> get activations;
  Future<void> initialize();
  Future<SystemNotificationStatus> status();
  Future<SystemNotificationStatus> requestPermission();
  Future<bool> openSettings();
  Future<void> show(SystemNotice notice);
  Future<void> cancel(int id);
}

/// Only locators are handed to the OS. This is never an authorization receipt.
@immutable
class SystemNotificationTarget {
  const SystemNotificationTarget({
    required this.kind,
    required this.deviceId,
    required this.objectId,
    required this.revision,
    required this.observationGeneration,
  });
  final SystemNotificationKind kind;
  final String deviceId;
  final String objectId;
  final String revision;
  final int observationGeneration;

  String encode() => jsonEncode({
    'v': 1,
    'kind': kind.name,
    'deviceId': deviceId,
    'objectId': objectId,
    'revision': revision,
    'observationGeneration': observationGeneration,
  });

  static SystemNotificationTarget? decode(String payload) {
    if (payload.length > 4096) return null;
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic> || data['v'] != 1) return null;
      final kind = SystemNotificationKind.values
          .where((kind) => kind.name == data['kind'])
          .firstOrNull;
      final generation = data['observationGeneration'];
      if (kind == null || generation is! int || generation < 0) return null;
      for (final key in ['deviceId', 'objectId', 'revision']) {
        if (data[key] is! String ||
            (data[key] as String).isEmpty ||
            (data[key] as String).length > 512) {
          return null;
        }
      }
      return SystemNotificationTarget(
        kind: kind,
        deviceId: data['deviceId'] as String,
        objectId: data['objectId'] as String,
        revision: data['revision'] as String,
        observationGeneration: generation,
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class SystemNotificationActivation {
  const SystemNotificationActivation({
    required this.target,
    required this.available,
    this.reason = '',
  });
  final SystemNotificationTarget target;
  final bool available;
  final String reason;
}

class NoopSystemNotificationSink implements SystemNotificationSink {
  const NoopSystemNotificationSink();
  @override
  Stream<String> get activations => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<SystemNotificationStatus> status() async =>
      const SystemNotificationStatus();
  @override
  Future<SystemNotificationStatus> requestPermission() => status();
  @override
  Future<bool> openSettings() async => false;
  @override
  Future<void> show(SystemNotice notice) async {}
  @override
  Future<void> cancel(int id) async {}
}

class SystemNotificationCoordinator {
  final changes = ValueNotifier<int>(0);
  void _changed() {
    if (!_disposed) changes.value++;
  }

  SystemNotificationCoordinator(this.controller, this.sink) {
    _events = controller.eventStream().listen(_event);
    _activations = sink.activations.listen(_activate);
  }
  final AppController controller;
  final SystemNotificationSink sink;
  late final StreamSubscription<Json> _events;
  late final StreamSubscription<String> _activations;
  final _owners = <String, _Owner>{};
  final _invalidThrough = <String, int>{};
  final _nativeStopped = <String>{};
  final _disconnectedAfterStop = <String>{};
  final _deliveries = <String, _Delivery>{};
  Future<void> _queue = Future<void>.value();
  bool _foreground = true;
  bool _disposed = false;
  bool _initialized = false;
  bool _reconciling = false;
  bool _restoring = false;
  int _nextId = systemNotificationIdMin;
  final _pending = <SystemNotificationTarget>[];
  SystemNotificationActivation? _presentation;
  final _consumed = <String>{};
  Future<void>? _initializing;
  int _statusEpoch = 0;
  SystemNotificationStatus status = const SystemNotificationStatus();

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      await sink.initialize();
      if (!_disposed) await _readStatus();
    } catch (_) {
      if (!_disposed) {
        status = const SystemNotificationStatus(
          reason: '系统提醒暂时无法初始化，请稍后检查系统设置。',
        );
        _changed();
      }
    } finally {
      if (!_disposed) {
        _initialized = true;
        _changed();
      }
    }
  }

  Future<SystemNotificationStatus> refreshStatus() async {
    await initialize();
    if (_disposed) return status;
    return _readStatus();
  }

  Future<SystemNotificationStatus> _readStatus() async {
    final epoch = ++_statusEpoch;
    try {
      final next = await sink.status();
      if (!_disposed && epoch == _statusEpoch) {
        status = next;
        configure();
        _changed();
      }
    } catch (_) {
      if (!_disposed && epoch == _statusEpoch) {
        status = const SystemNotificationStatus(reason: '尚未确认系统提醒权限，请稍后重试。');
        configure();
        _changed();
      }
    }
    return status;
  }

  Future<SystemNotificationStatus> requestPermission() async {
    await initialize();
    if (_disposed) return status;
    try {
      await sink.requestPermission();
    } catch (_) {
      /* Refresh actual state. */
    }
    return refreshStatus();
  }

  Future<bool> openSettings() async {
    await initialize();
    if (_disposed) return false;
    try {
      return await sink.openSettings();
    } catch (_) {
      return false;
    }
  }

  void configure() {
    if (_disposed || controller.isDisposed()) return;
    if (controller.snapshot().reconciliationPending) {
      _suspend();
      return;
    }
    _pruneTombstones();
    for (final deviceId in _owners.keys.toList()) {
      if (!_connected(deviceId)) {
        _invalidate(deviceId, _owners[deviceId]!.generation);
      }
    }
    for (final key in _deliveries.keys.toList()) {
      if (!_allowed(_deliveries[key]!.target.kind)) _cancel(key);
    }
    if (_pending.isNotEmpty) _changed();
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (_pending.isNotEmpty) _changed();
  }

  Future<void> drain() => _queue;
  SystemNotificationActivation? get pendingActivation {
    if (_disposed ||
        !_initialized ||
        _reconciling ||
        !_foreground ||
        controller.isDisposed() ||
        _pending.isEmpty ||
        controller.snapshot().loading ||
        controller.snapshot().reconciliationPending) {
      return null;
    }
    final target = _pending.first;
    final owner = _owners[target.deviceId];
    final current =
        owner != null &&
        owner.generation == target.observationGeneration &&
        (target.kind == SystemNotificationKind.call
            ? owner.callRevisions[target.objectId] == target.revision
            : owner.revisions[target.objectId] == target.revision);
    final available =
        current && _connected(target.deviceId) && _allowed(target.kind);
    if (_presentation?.target != target ||
        _presentation?.available != available) {
      _presentation = SystemNotificationActivation(
        target: target,
        available: available,
        reason: available ? '' : '这条系统提醒已失效或暂时无法核验，请查看设备当前状态。',
      );
    }
    return _presentation;
  }

  SystemNotificationActivation? takeActivation() {
    final result = pendingActivation;
    if (result != null) {
      _pending.removeAt(0);
      if (_pending.isNotEmpty) {
        scheduleMicrotask(() {
          if (!_disposed) _changed();
        });
      }
    }
    return result;
  }

  void _activate(String payload) {
    if (_disposed) return;
    final target = SystemNotificationTarget.decode(payload);
    if (target == null || !_consumed.add(target.encode())) return;
    if (_consumed.length > 256) _consumed.remove(_consumed.first);
    if (_pending.length >= 8) _pending.removeAt(0);
    _pending.add(target);
    _changed();
  }

  bool _connected(String deviceId) =>
      !controller.isDisposed() &&
      !_nativeStopped.contains(deviceId) &&
      controller
          .snapshot()
          .devices
          .take(32)
          .any((d) => d['id'] == deviceId && d['status'] == 'connected');

  bool _allowed(SystemNotificationKind kind) =>
      status.supported &&
      status.permissionGranted == true &&
      controller.snapshot().settings[kind == SystemNotificationKind.call
              ? 'callAlerts'
              : 'notificationAlerts'] ==
          true &&
      (kind == SystemNotificationKind.call
              ? status.callChannelEnabled
              : status.notificationChannelEnabled) !=
          false;

  void _enqueue(Future<void> Function() work) {
    _queue = _queue.then((_) => work()).catchError((Object _) {
      if (_disposed) return;
      status = SystemNotificationStatus(
        supported: status.supported,
        permissionGranted: status.permissionGranted,
        notificationChannelEnabled: status.notificationChannelEnabled,
        callChannelEnabled: status.callChannelEnabled,
        canRequest: status.canRequest,
        canOpenSettings: status.canOpenSettings,
        reason: '系统提醒操作尚未确认，请检查通知设置。',
      );
      _changed();
    });
  }

  void _event(Json event) {
    if (_disposed) return;
    final deviceId = value(event, 'deviceId');
    final data = jsonObject(event['data']);
    if (event['type'] == 'state.resync' ||
        event['type'] == 'state.resync.failed') {
      _suspend();
      return;
    }
    if (event['type'] == 'state.resynced') {
      _clear();
      _reconciling = false;
      _restoring = true;
      _connectionLifecycle(objects(data['devices']));
      for (final observation in objects(data['observations'])) {
        _event({
          'type': 'observation.changed',
          'deviceId': observation['deviceId'],
          'data': observation,
        });
      }
      _restoring = false;
      if (_pending.isNotEmpty) _changed();
      return;
    }
    if (event['type'] == 'connections.stopped') {
      _nativeStopped.addAll(
        controller.snapshot().devices.take(32).map((d) => value(d, 'id')),
      );
      for (final entry in _owners.entries.toList()) {
        _invalidate(entry.key, entry.value.generation);
      }
      return;
    }
    if (event['type'] == 'device.changed') {
      _connectionLifecycle([
        {...data, 'id': deviceId},
      ]);
      return;
    }
    if (event['type'] == 'companion.stopped') {
      final owner = _owners[deviceId];
      if (owner != null) _invalidate(deviceId, owner.generation);
      return;
    }
    if (event['type'] == 'devices.changed') {
      _connectionLifecycle(objects(data['devices']), complete: true);
      final connected = objects(data['devices'])
          .where((d) => d['status'] == 'connected')
          .map((d) => value(d, 'id'))
          .toSet();
      for (final entry in _owners.entries.toList()) {
        if (!connected.contains(entry.key)) {
          _invalidate(entry.key, entry.value.generation);
        }
      }
      return;
    }
    if (_reconciling || controller.snapshot().reconciliationPending) return;
    if (event['type'] == 'observation.changed') {
      final generation = data['generation'];
      if (generation is! int || !_connected(deviceId)) return;
      final previous = _owners[deviceId];
      if (previous != null && generation < previous.generation) return;
      if (data['wanted'] != true ||
          !['observing', 'limited'].contains(data['phase'])) {
        _invalidate(
          deviceId,
          data['wanted'] == false ? generation : generation - 1,
        );
        return;
      }
      if (generation <= (_invalidThrough[deviceId] ?? -1)) return;
      if (previous != null && generation != previous.generation) {
        _invalidate(deviceId, previous.generation);
      }
      final owner = _owners.putIfAbsent(deviceId, () => _Owner(generation));
      _notifications(deviceId, owner, jsonObject(data['notifications']));
      _calls(deviceId, owner, jsonObject(data['calls']));
    } else if (event['type'] == 'notifications.changed') {
      final owner = _owners[deviceId];
      if (owner != null && _connected(deviceId)) {
        _notifications(deviceId, owner, data);
      }
    } else if ([
      'calls.incoming',
      'call.incoming',
      'calls.changed',
    ].contains(event['type'])) {
      final owner = _owners[deviceId];
      if (owner != null && _connected(deviceId)) _calls(deviceId, owner, data);
    }
    if (_pending.isNotEmpty) _changed();
  }

  void _connectionLifecycle(List<Json> devices, {bool complete = false}) {
    for (final deviceId in _nativeStopped.toList()) {
      final device = devices.where((d) => d['id'] == deviceId).firstOrNull;
      if (device == null && !complete) continue;
      if (device?['status'] != 'connected') {
        _disconnectedAfterStop.add(deviceId);
      } else if (_disconnectedAfterStop.remove(deviceId)) {
        _nativeStopped.remove(deviceId);
      }
    }
  }

  void _suspend() {
    _reconciling = true;
    _clear();
  }

  void _clear() {
    _owners.clear();
    for (final key in _deliveries.keys.toList()) {
      _cancel(key);
    }
  }

  void _invalidate(String deviceId, int generation) {
    _pruneTombstones();
    final previous = _invalidThrough[deviceId] ?? -1;
    _invalidThrough[deviceId] = generation > previous ? generation : previous;
    _owners.remove(deviceId);
    for (final key
        in _deliveries.keys
            .where((key) => _deliveries[key]!.target.deviceId == deviceId)
            .toList()) {
      _cancel(key);
    }
  }

  void _pruneTombstones() {
    final known = controller
        .snapshot()
        .devices
        .take(32)
        .map((d) => value(d, 'id'))
        .toSet();
    _invalidThrough.removeWhere((id, _) => !known.contains(id));
    _nativeStopped.removeWhere((id) => !known.contains(id));
    _disconnectedAfterStop.removeWhere((id) => !known.contains(id));
  }

  _Delivery? _delivery(String key, SystemNotificationTarget target) {
    final existing = _deliveries[key];
    if (existing != null) {
      existing.target = target;
      return existing;
    }
    if (_deliveries.length >= 128 &&
        target.kind == SystemNotificationKind.call) {
      final displaced = _deliveries.keys
          .where(
            (key) =>
                _deliveries[key]!.target.kind ==
                SystemNotificationKind.notification,
          )
          .firstOrNull;
      if (displaced != null) _cancel(displaced);
    }
    if (_deliveries.length >= 128) return null;
    final occupied = _deliveries.values.map((delivery) => delivery.id).toSet();
    while (occupied.contains(_nextId)) {
      _nextId = _nextId == systemNotificationIdMax
          ? systemNotificationIdMin
          : _nextId + 1;
    }
    final next = _Delivery(_nextId, target);
    _nextId = _nextId == systemNotificationIdMax
        ? systemNotificationIdMin
        : _nextId + 1;
    _deliveries[key] = next;
    return next;
  }

  void _cancel(String key) {
    final delivery = _deliveries.remove(key);
    if (delivery != null) {
      _enqueue(() async {
        if (delivery.issued) await sink.cancel(delivery.id);
      });
    }
  }

  void _notifications(
    String deviceId,
    _Owner owner,
    Json data, {
    bool baseline = false,
  }) {
    final epoch = data['observationEpoch'];
    if (epoch is int && epoch != owner.generation) return;
    if (data['live'] != true ||
        data['observationEnabled'] != true ||
        epoch != owner.generation ||
        data['notifications'] is! List<Object?>) {
      _clearSection(deviceId, owner, SystemNotificationKind.notification);
      return;
    }
    baseline = baseline || !owner.notificationLive;
    owner.notificationLive = true;
    final next = <String, String>{};
    for (final item in objects(data['notifications']).take(1000)) {
      final id = value(item, 'id');
      final key = value(item, 'key', id);
      if (id.isEmpty || id.length > 512 || key.isEmpty || key.length > 1024) {
        continue;
      }
      if (!next.containsKey(key) && next.length >= 1000) break;
      final revision = value(item, 'revision', id);
      if (revision.isEmpty || revision.length > 512) continue;
      next[key] = id;
      final localKey = '$deviceId:${owner.generation}:notification:$key';
      // Summary content remains in the remote list. It must not generate an
      // extra OS reminder alongside the group's individual notifications.
      if (item['groupSummary'] == true) {
        _cancel(localKey);
        continue;
      }
      final changed =
          owner.notifications[key] != id || owner.revisions[id] != revision;
      if (changed && !_allowed(SystemNotificationKind.notification)) {
        _cancel(localKey);
      }
      if (changed &&
          !baseline &&
          _allowed(SystemNotificationKind.notification)) {
        final target = SystemNotificationTarget(
          kind: SystemNotificationKind.notification,
          deviceId: deviceId,
          objectId: id,
          revision: revision,
          observationGeneration: owner.generation,
        );
        final delivery = _delivery(localKey, target);
        if (delivery == null) continue;
        final payload = target.encode();
        _enqueue(() async {
          if (_disposed ||
              !_connected(deviceId) ||
              !_allowed(target.kind) ||
              _deliveries[localKey] != delivery ||
              delivery.target.encode() != payload) {
            return;
          }
          delivery.issued = true;
          await sink.show(
            SystemNotice(
              id: delivery.id,
              kind: SystemNotificationKind.notification,
              title: '设备有新通知',
              body: '请打开邻接查看',
              payload: payload,
            ),
          );
        });
      }
    }
    if (data['truncated'] != true) {
      for (final key in owner.notifications.keys.where(
        (key) => !next.containsKey(key),
      )) {
        _cancel('$deviceId:${owner.generation}:notification:$key');
      }
      owner.notifications.clear();
    }
    owner.notifications.addAll(next);
    while (owner.notifications.length > 1000) {
      final oldest = owner.notifications.keys.first;
      _cancel('$deviceId:${owner.generation}:notification:$oldest');
      owner.notifications.remove(oldest);
    }
    final ids = owner.notifications.values.toSet();
    owner.revisions.removeWhere((id, _) => !ids.contains(id));
    for (final item in objects(data['notifications']).take(1000)) {
      final id = value(item, 'id');
      if (ids.contains(id)) owner.revisions[id] = value(item, 'revision', id);
    }
  }

  void _calls(String deviceId, _Owner owner, Json data) {
    final epoch = data['observationEpoch'];
    if (epoch is int && epoch != owner.generation) return;
    if (data['live'] != true ||
        data['observationEnabled'] != true ||
        epoch != owner.generation ||
        data['calls'] is! List<Object?>) {
      _clearSection(deviceId, owner, SystemNotificationKind.call);
      return;
    }
    final next = <String>{};
    for (final item in objects(data['calls']).take(32)) {
      final id = value(item, 'id');
      if (id.isEmpty || id.length > 512 || item['state'] != 'ringing') continue;
      next.add(id);
      final revision = value(item, 'generation', id);
      if (revision.isEmpty || revision.length > 512) continue;
      final changed = owner.callRevisions[id] != revision;
      final localKey = '$deviceId:${owner.generation}:call:$id';
      if (changed && (_foreground || !_allowed(SystemNotificationKind.call))) {
        _cancel(localKey);
      }
      if (changed &&
          !_restoring &&
          !_foreground &&
          _allowed(SystemNotificationKind.call)) {
        final target = SystemNotificationTarget(
          kind: SystemNotificationKind.call,
          deviceId: deviceId,
          objectId: id,
          revision: revision,
          observationGeneration: owner.generation,
        );
        final delivery = _delivery(localKey, target);
        if (delivery == null) continue;
        final payload = target.encode();
        _enqueue(() async {
          if (_disposed ||
              _foreground ||
              !_connected(deviceId) ||
              !_allowed(target.kind) ||
              _deliveries[localKey] != delivery ||
              delivery.target.encode() != payload) {
            return;
          }
          delivery.issued = true;
          await sink.show(
            SystemNotice(
              id: delivery.id,
              kind: SystemNotificationKind.call,
              title: '设备有来电',
              body: '请打开邻接查看',
              payload: payload,
            ),
          );
        });
      }
    }
    for (final id in owner.calls.where((id) => !next.contains(id))) {
      _cancel('$deviceId:${owner.generation}:call:$id');
    }
    owner.calls
      ..clear()
      ..addAll(next);
    owner.callRevisions.clear();
    for (final item in objects(data['calls']).take(32)) {
      final id = value(item, 'id');
      if (next.contains(id)) {
        owner.callRevisions[id] = value(item, 'generation', id);
      }
    }
  }

  void _clearSection(
    String deviceId,
    _Owner owner,
    SystemNotificationKind kind,
  ) {
    for (final key in _deliveries.keys.where((key) {
      final target = _deliveries[key]!.target;
      return target.deviceId == deviceId && target.kind == kind;
    }).toList()) {
      _cancel(key);
    }
    if (kind == SystemNotificationKind.notification) {
      owner.notificationLive = false;
      owner.notifications.clear();
      owner.revisions.clear();
    } else {
      owner.calls.clear();
      owner.callRevisions.clear();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clear();
    _pending.clear();
    unawaited(_events.cancel());
    unawaited(_activations.cancel());
    changes.dispose();
  }
}

class _Owner {
  _Owner(this.generation);
  final int generation;
  bool notificationLive = false;
  final notifications = <String, String>{};
  final revisions = <String, String>{};
  final calls = <String>{};
  final callRevisions = <String, String>{};
}

class _Delivery {
  _Delivery(this.id, this.target);
  final int id;
  SystemNotificationTarget target;
  bool issued = false;
}

@Riverpod(keepAlive: true)
SystemNotificationSink systemNotificationSink(Ref ref) =>
    const NoopSystemNotificationSink();

@Riverpod(keepAlive: true)
SystemNotificationCoordinator systemNotificationCoordinator(Ref ref) {
  final controller = ref.watch(appControllerProvider.notifier);
  final coordinator = SystemNotificationCoordinator(
    controller,
    ref.watch(systemNotificationSinkProvider),
  );
  ref.listen(
    appControllerProvider.select(
      (state) => (
        state.devices,
        state.settings,
        state.loading,
        state.reconciliationPending,
      ),
    ),
    (_, next) => coordinator.configure(),
  );
  ref.onDispose(coordinator.dispose);
  unawaited(coordinator.initialize());
  return coordinator;
}
