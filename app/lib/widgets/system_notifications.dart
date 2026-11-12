import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/models/device_call.dart';
import 'package:scrcpy_connect/core/devices/models/device_notification.dart';
import 'package:scrcpy_connect/core/devices/models/device_observation_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_changed.dart';
import 'package:scrcpy_connect/core/devices/models/observed_device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/app_snapshot_notifier.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/system_notification_sink.dart';
import 'package:scrcpy_connect/widgets/system_notification_sink_provider.dart';

import 'models/system_notification_snapshot.dart';
import 'models/system_notification_target.dart';

export 'models/system_notification_target.dart';

export 'package:scrcpy_connect/widgets/system_notification_sink.dart'
    show
        SystemNotificationKind,
        systemNotificationIdMin,
        systemNotificationIdMax,
        SystemNotificationStatus,
        SystemNotice,
        SystemNotificationSink,
        NoopSystemNotificationSink;
export 'package:scrcpy_connect/widgets/system_notification_sink_provider.dart';

class SystemNotifications {
  final changes = ValueNotifier<int>(0);
  void _changed() {
    if (!_disposed && _current()) changes.value++;
  }

  SystemNotifications({
    required Stream<Json> events,
    required this._readSnapshot,
    required this._current,
    required this.sink,
  }) {
    _events = events.listen(_event);
    _activations = sink.activations.listen(_activate);
  }
  final SystemNotificationSnapshot Function() _readSnapshot;
  final bool Function() _current;
  final SystemNotificationSink sink;
  late final StreamSubscription<Json> _events;
  late final StreamSubscription<String> _activations;
  final _owners = <String, _Owner>{};
  final _invalidThrough = <String, int>{};
  final _nativeStopped = <String>{};
  final _disconnectedAfterStop = <String>{};
  final _deliveries = <String, _Delivery>{};
  final _withdrawals = <int, _Delivery>{};
  final _withdrawing = <int>{};
  Future<void> _queue = Future<void>.value();
  bool _foreground = true;
  final _notificationPages =
      <Object, ({String deviceId, bool Function() visible})>{};

  /// 当前可见通知页只更新列表；遮挡或后台后恢复系统提醒资格。
  void Function() claimNotificationPage(
    String deviceId,
    bool Function() visible,
  ) {
    final token = Object();
    _notificationPages[token] = (deviceId: deviceId, visible: visible);
    if (_notificationPageVisible(deviceId)) {
      for (final key in _deliveries.keys.where((key) {
        final target = _deliveries[key]!.target;
        return target.deviceId == deviceId &&
            target.kind == SystemNotificationKind.notification;
      }).toList()) {
        _cancel(key);
      }
    }
    return () => _notificationPages.remove(token);
  }

  bool _notificationPageVisible(String deviceId) =>
      _foreground &&
      _notificationPages.values.any(
        (page) => page.deviceId == deviceId && page.visible(),
      );
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
    if (_disposed || !_current()) return;
    try {
      await sink.initialize();
      if (!_disposed && _current()) await _readStatus();
    } catch (_) {
      if (!_disposed && _current()) {
        status = const SystemNotificationStatus(
          reason: '系统提醒暂时无法初始化，请稍后检查系统设置。',
        );
        _changed();
      }
    } finally {
      if (!_disposed && _current()) {
        _initialized = true;
        _changed();
      }
    }
  }

  Future<SystemNotificationStatus> refreshStatus() async {
    await initialize();
    if (_disposed || !_current()) return status;
    return _readStatus();
  }

  Future<SystemNotificationStatus> _readStatus() async {
    final epoch = ++_statusEpoch;
    try {
      final next = await sink.status();
      if (!_disposed && _current() && epoch == _statusEpoch) {
        status = next;
        configure();
        _changed();
      }
    } catch (_) {
      if (!_disposed && _current() && epoch == _statusEpoch) {
        status = const SystemNotificationStatus(reason: '尚未确认系统提醒权限，请稍后重试。');
        configure();
        _changed();
      }
    }
    return status;
  }

  Future<SystemNotificationStatus> requestPermission() async {
    await initialize();
    if (_disposed || !_current()) return status;
    try {
      await sink.requestPermission();
    } catch (_) {
      // 重新读取实际状态。
    }
    return refreshStatus();
  }

  Future<bool> openSettings() async {
    await initialize();
    if (_disposed || !_current()) return false;
    try {
      return await sink.openSettings();
    } catch (_) {
      return false;
    }
  }

  void configure() {
    if (_disposed || !_current()) return;
    for (final delivery in _withdrawals.values.toList()) {
      _withdraw(delivery);
    }
    if (_readSnapshot().reconciliationPending) {
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
    if (_disposed || !_current() || _foreground == foreground) return;
    _foreground = foreground;
    if (_pending.isNotEmpty) _changed();
  }

  Future<void> drain() => _queue;
  SystemNotificationActivation? get pendingActivation {
    if (_disposed ||
        !_initialized ||
        _reconciling ||
        !_foreground ||
        !_current() ||
        _pending.isEmpty ||
        _readSnapshot().loading ||
        _readSnapshot().reconciliationPending) {
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
          if (!_disposed && _current()) _changed();
        });
      }
    }
    return result;
  }

  void _activate(String payload) {
    if (_disposed || !_current()) return;
    final target = SystemNotificationTarget.decode(payload);
    if (target == null || !_consumed.add(target.encode())) return;
    if (_consumed.length > 256) _consumed.remove(_consumed.first);
    if (_pending.length >= 8) _pending.removeAt(0);
    _pending.add(target);
    _changed();
  }

  bool _connected(String deviceId) =>
      _current() &&
      !_nativeStopped.contains(deviceId) &&
      _readSnapshot().devices
          .take(32)
          .any(
            (d) =>
                d.id == deviceId &&
                d.status == DeviceConnectionStatus.connected,
          );

  bool _allowed(SystemNotificationKind kind) =>
      status.supported &&
      status.permissionGranted == true &&
      (kind == SystemNotificationKind.call
          ? _readSnapshot().settings.callAlerts
          : _readSnapshot().settings.notificationAlerts) &&
      (kind == SystemNotificationKind.call
              ? status.callChannelEnabled
              : status.notificationChannelEnabled) !=
          false;

  void _enqueue(Future<void> Function() work) {
    _queue = _queue.then((_) => work()).catchError((Object _) {
      if (_disposed || !_current()) return;
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
    if (_disposed || !_current()) return;
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
      final snapshot = event['data'] as RuntimeSnapshot;
      _connectionLifecycle(snapshot.devices);
      for (final observed in snapshot.observations) {
        _observe(observed);
      }
      _restoring = false;
      if (_pending.isNotEmpty) _changed();
      return;
    }
    if (event['type'] == 'connections.stopped') {
      _nativeStopped.addAll(_readSnapshot().devices.take(32).map((d) => d.id));
      for (final entry in _owners.entries.toList()) {
        _invalidate(entry.key, entry.value.generation);
      }
      return;
    }
    if (event['type'] == 'companion.stopped') {
      final owner = _owners[deviceId];
      if (owner != null) _invalidate(deviceId, owner.generation);
      return;
    }
    if (event['data'] case DeviceListChanged(:final devices)) {
      _connectionLifecycle(devices, complete: true);
      final connected = {
        for (final device in devices)
          if (device.status == .connected) device.id,
      };
      for (final entry in _owners.entries.toList()) {
        if (!connected.contains(entry.key)) {
          _invalidate(entry.key, entry.value.generation);
        }
      }
      return;
    }
    if (_reconciling || _readSnapshot().reconciliationPending) return;
    if (event['type'] == 'observation.changed') {
      _observe(
        ObservedDeviceSnapshot(
          observation: DeviceObservationSnapshot.fromJson({
            ...data,
            'deviceId': deviceId,
          }),
          notifications: DeviceNotificationsSnapshot.fromJson({
            ...jsonObject(data['notifications']),
            'deviceId': deviceId,
          }),
          calls: DeviceCallsSnapshot.fromJson({
            ...jsonObject(data['calls']),
            'deviceId': deviceId,
          }),
        ),
      );
    } else if (event['type'] == 'notifications.changed') {
      final owner = _owners[deviceId];
      if (owner != null && _connected(deviceId)) {
        _notifications(
          deviceId,
          owner,
          DeviceNotificationsSnapshot.fromJson({...data, 'deviceId': deviceId}),
        );
      }
    } else if ([
      'calls.incoming',
      'call.incoming',
      'calls.changed',
    ].contains(event['type'])) {
      final owner = _owners[deviceId];
      if (owner != null && _connected(deviceId)) {
        _calls(
          deviceId,
          owner,
          DeviceCallsSnapshot.fromJson({...data, 'deviceId': deviceId}),
        );
      }
    }
    if (_pending.isNotEmpty) _changed();
  }

  void _observe(ObservedDeviceSnapshot observed) {
    final observation = observed.observation;
    final deviceId = observation.deviceId, generation = observation.generation;
    if (!_connected(deviceId)) return;
    final previous = _owners[deviceId];
    if (previous != null && generation < previous.generation) return;
    if (!observation.wanted ||
        !{
          DeviceObservationPhase.observing,
          DeviceObservationPhase.limited,
        }.contains(observation.phase)) {
      _invalidate(deviceId, !observation.wanted ? generation : generation - 1);
      return;
    }
    if (generation <= (_invalidThrough[deviceId] ?? -1)) return;
    if (previous != null && generation != previous.generation) {
      _invalidate(deviceId, previous.generation);
    }
    final owner = _owners.putIfAbsent(deviceId, () => _Owner(generation));
    _notifications(deviceId, owner, observed.notifications);
    _calls(deviceId, owner, observed.calls);
  }

  void _connectionLifecycle(
    List<DeviceSnapshot> devices, {
    bool complete = false,
  }) {
    for (final deviceId in _nativeStopped.toList()) {
      final device = devices.where((d) => d.id == deviceId).firstOrNull;
      if (device == null && !complete) continue;
      if (device?.status != .connected) {
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
    final known = _readSnapshot().devices.take(32).map((d) => d.id).toSet();
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
    final occupied = {
      ..._deliveries.values.map((delivery) => delivery.id),
      ..._withdrawals.keys,
    };
    if (occupied.length >=
        systemNotificationIdMax - systemNotificationIdMin + 1) {
      return null;
    }
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
    if (delivery == null) return;
    _withdrawals[delivery.id] = delivery;
    _withdraw(delivery);
  }

  void _withdraw(_Delivery delivery) {
    if (!_withdrawing.add(delivery.id)) return;
    _enqueue(() async {
      try {
        if (delivery.issued) {
          for (var attempt = 0; ; attempt++) {
            try {
              await sink.cancel(delivery.id);
              break;
            } catch (_) {
              if (attempt == 2) rethrow;
            }
          }
        }
        _withdrawals.remove(delivery.id);
      } finally {
        _withdrawing.remove(delivery.id);
      }
    });
  }

  void _notifications(
    String deviceId,
    _Owner owner,
    DeviceNotificationsSnapshot data, {
    bool baseline = false,
  }) {
    final epoch = data.observationEpoch;
    if (epoch != null && epoch != owner.generation) return;
    if (!data.live || !data.observationEnabled || epoch != owner.generation) {
      _clearSection(deviceId, owner, SystemNotificationKind.notification);
      return;
    }
    baseline = baseline || !owner.notificationLive;
    owner.notificationLive = true;
    final next = <String, String>{};
    for (final item in data.notifications.take(1000)) {
      final id = item.id;
      final key = item.key ?? id;
      if (id.isEmpty || id.length > 512 || key.isEmpty || key.length > 1024) {
        continue;
      }
      if (!next.containsKey(key) && next.length >= 1000) break;
      final revision = item.revision ?? id;
      if (revision.isEmpty || revision.length > 512) continue;
      next[key] = id;
      final localKey = '$deviceId:${owner.generation}:notification:$key';
      // 摘要仍显示在远端列表中，不与分组内的独立通知重复触发系统提醒。
      if (item.groupSummary) {
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
          !_notificationPageVisible(deviceId) &&
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
              _notificationPageVisible(deviceId) ||
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
    if (!data.truncated) {
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
    for (final item in data.notifications.take(1000)) {
      final id = item.id;
      if (ids.contains(id)) owner.revisions[id] = item.revision ?? id;
    }
  }

  void _calls(String deviceId, _Owner owner, DeviceCallsSnapshot data) {
    final epoch = data.observationEpoch;
    if (epoch != null && epoch != owner.generation) return;
    if (!data.live || !data.observationEnabled || epoch != owner.generation) {
      _clearSection(deviceId, owner, SystemNotificationKind.call);
      return;
    }
    final next = <String>{};
    for (final item in data.calls.take(32)) {
      final id = item.id ?? '';
      if (id.isEmpty || id.length > 512 || item.state != .ringing) continue;
      next.add(id);
      final revision = item.generation?.toString() ?? id;
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
    for (final item in data.calls.take(32)) {
      final id = item.id ?? '';
      if (next.contains(id)) {
        owner.callRevisions[id] = item.generation?.toString() ?? id;
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
    for (final delivery in _withdrawals.values.toList()) {
      _withdraw(delivery);
    }
    _pending.clear();
    _notificationPages.clear();
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

/// 界面拥有提醒订阅、展示与销毁；provider 只提供可替换的系统能力。
SystemNotifications useSystemNotifications(
  BuildContext context,
  WidgetRef ref,
) {
  final shared = context
      .dependOnInheritedWidgetOfExactType<SystemNotificationsScope>()
      ?.notifications;
  final events = ref.watch(runtimeEventsProvider);
  final sink = ref.watch(systemNotificationSinkProvider);
  final notifications = useMemoized(
    () =>
        shared ??
        SystemNotifications(
          events: events,
          sink: sink,
          current: () =>
              context.mounted &&
              identical(ref.read(runtimeEventsProvider), events) &&
              identical(ref.read(systemNotificationSinkProvider), sink),
          readSnapshot: () {
            final snapshot = ref.read(appSnapshotProvider);
            return SystemNotificationSnapshot(
              devices: snapshot.devices,
              settings: snapshot.settings,
              loading: snapshot.loading,
              reconciliationPending: snapshot.reconciliationPending,
            );
          },
        ),
    [shared, events, sink],
  );
  ref.listen(
    appSnapshotProvider.select(
      (state) => (
        state.devices,
        state.settings,
        state.loading,
        state.reconciliationPending,
      ),
    ),
    (_, next) {
      if (shared == null) notifications.configure();
    },
  );
  useEffect(() {
    if (shared != null) return null;
    unawaited(notifications.initialize());
    return notifications.dispose;
  }, [shared, notifications]);
  return notifications;
}

class SystemNotificationsScope extends InheritedWidget {
  const SystemNotificationsScope({
    super.key,
    required this.notifications,
    required super.child,
  });
  final SystemNotifications notifications;
  @override
  bool updateShouldNotify(SystemNotificationsScope oldWidget) =>
      notifications != oldWidget.notifications;
}
