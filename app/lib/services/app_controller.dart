import 'dart:async';

import 'package:device_runtime/device_runtime.dart' show InteropCommand;

export 'package:device_runtime/device_runtime.dart' show InteropCommand;

import 'package:scrcpy_connect/services/session_views.dart';
import 'package:scrcpy_connect/services/device_screen_policy.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/services/app_state.dart';

part 'app_controller.g.dart';

typedef Json = Map<String, dynamic>;

class RequestFailure implements Exception {
  const RequestFailure(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;
  @override
  String toString() => message;
}

typedef BridgeRequest = Future<Json> Function(String command, [Json params]);

Json jsonObject(Object? value) => value is Map<Object?, Object?>
    ? {
        for (final entry in value.entries)
          if (entry.key case final String key) key: entry.value,
      }
    : <String, dynamic>{};
List<String> strings(Object? value) =>
    value is List<Object?> ? value.whereType<String>().toList() : <String>[];
List<Object?> values(Object? value) =>
    value is List<Object?> ? value : const <Object?>[];
List<Json> objects(Object? value) => value is List<Object?>
    ? value.whereType<Map<Object?, Object?>>().map(jsonObject).toList()
    : <Json>[];
String value(Json data, String key, [String fallback = '']) =>
    data[key]?.toString() ?? fallback;
String deviceName(Json device) =>
    value(device, 'name', value(device, 'model', 'Android 设备'));
String statusText(String status) => switch (status) {
  'connected' => '已连接',
  'checking' => '正在检查',
  'connecting' => '正在连接',
  'reconnecting' => '正在恢复连接',
  'paired' => '已配对，尚未连接',
  'unauthorized' => '需要重新授权',
  'available' => '可用',
  'limited' => '受限',
  'unavailable' => '不可用',
  'needsSetup' => '需要设置',
  'unknown' => '尚未检查',
  'completed' => '已完成',
  'failed' => '失败',
  'cancelled' => '已取消',
  'running' => '传输中',
  'pending' => '等待中',
  'queued' => '等待传输',
  'finalizing' => '正在校验并保存',
  'interrupted' => '已中断，等待核对',
  'skipped' => '已跳过',
  'ready' => '画面可用',
  'active' => '进行中',
  'ringing' => '来电响铃',
  'dialing' => '正在拨号',
  'holding' => '已保持通话',
  'ended' => '已结束',
  'starting' => '正在启动',
  'playing' => '正在播放',
  'stopped' => '已停止',
  'offline' => '离线',
  'paused' => '已暂停',
  'conflict' => '等待处理同名文件',
  'partial' => '部分完成',
  'partialFailure' => '部分传输失败',
  'completedWithSkips' => '部分内容已跳过',
  _ => '状态待核验',
};
String bytes(dynamic input) {
  final n = num.tryParse('$input') ?? 0;
  if (n < 1024) return '${n.toInt()} B';
  if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1073741824).toStringAsFixed(1)} GB';
}

@Riverpod(keepAlive: true)
class AppController extends _$AppController {
  late AppDependencies _dependencies;
  late StreamController<Json> _events;
  late SessionViews _sessionViews;
  late DeviceScreenPolicy _screenPolicy;
  ({String deviceId, String connectionId, String reason})? _screenFailure;

  String? _screenFailureFor(List<Json> devices) {
    final failure = _screenFailure;
    if (failure == null) return null;
    if (!devices.any(
      (device) =>
          device['id'] == failure.deviceId &&
          device['connectionId'] == failure.connectionId,
    )) {
      _screenFailure = null;
      return null;
    }
    return '未能自动点亮设备：${failure.reason}';
  }

  /// The caller releases once; only the last actual picture may request locking.
  bool Function() claimPhoneControlPage(String deviceId, {String? sessionId}) {
    final policy = _screenPolicy;
    final token = policy.claimPhonePage(deviceId, sessionId: sessionId);
    return () => policy.releasePhonePage(token);
  }

  bool hasPhoneControlPages(String deviceId) =>
      _screenPolicy.hasPhonePages(deviceId);

  SessionView claimSessionView(String sessionId, {required bool visible}) {
    final view = _sessionViews.claim(sessionId, visible: visible);
    _scheduleDeviceAudio();
    return view;
  }

  /// A page owns device sound even while another route covers its surface.
  /// Releasing the last page stops that device's one shared output source.
  void Function() claimRemoteDeviceView(String deviceId) {
    final token = Object();
    _remoteDeviceViews[token] = deviceId;
    _scheduleDeviceAudio();
    return () {
      if (_remoteDeviceViews.remove(token) == null) return;
      if (!_remoteDeviceViews.containsValue(deviceId)) {
        _stopDeviceAudio(deviceId);
      }
      _scheduleDeviceAudio();
    };
  }

  final _consumedShareIds = <String>{};
  final _remoteDeviceViews = <Object, String>{};
  final _managedAudioSources = <String, String>{};
  final _audioDeviceWork = <String, Future<void>>{};
  final _audioStops = <String, Future<void>>{};
  final _audioDeviceEpochs = <String, int>{};
  final _audioFailures = <String, String>{};
  bool _deviceAudioScheduled = false;
  bool _deviceAudioDirty = false;
  Future<void> _settingsQueue = Future<void>.value();
  bool _disposed = true;
  int _generation = 0;
  int _deviceRequest = 0;
  int _settingsRequest = 0;
  // Authority changes invalidate save receipts independently of queued writes.
  int _settingsEpoch = 0;
  int _shareRequest = 0;

  @override
  AppState build() {
    final dependencies = ref.watch(appDependenciesProvider);
    _dependencies = dependencies;
    _sessionViews = SessionViews(dependencies.request);
    _screenPolicy = DeviceScreenPolicy();
    _screenFailure = null;
    final ownedViews = _sessionViews;
    final generation = ++_generation;
    _disposed = false;
    _deviceAudioScheduled = false;
    _deviceAudioDirty = false;
    _audioDeviceWork.clear();
    _audioStops.clear();
    _audioDeviceEpochs.clear();
    _audioFailures.clear();
    _consumedShareIds.clear();
    final events = StreamController<Json>.broadcast(sync: true);
    _events = events;
    final subscription = dependencies.events.listen(
      (event) {
        if (!_current(generation)) return;
        final frozen = immutableJson(event);
        final data = jsonObject(event['data']);
        if (event['type'] == 'state.resynced' &&
            !state.reconciliationPending &&
            data['sequence'] != null &&
            data['sequence'] == state.reconciledSnapshot?['sequence']) {
          return;
        }
        // Native frames belong to their bound surface, never the global state.
        if (event['type'] == 'session.frame') {
          events.add(frozen);
          return;
        }
        var next = state.copyWith(
          lastEvent: () => frozen,
          eventRevision: state.eventRevision + 1,
        );
        if (event['type'] == 'state.resync' ||
            event['type'] == 'state.resync.failed') {
          ownedViews.markUncertain();
          _deviceRequest++;
          _settingsRequest++;
          _settingsEpoch++;
          _shareRequest++;
          next = next.copyWith(
            reconciliationPending: true,
            reconciliationError: () => event['type'] == 'state.resync.failed'
                ? value(data, 'reason', '状态检查未完成，请重试。')
                : null,
          );
        } else if (event['type'] == 'state.resynced') {
          final snapshot = jsonObject(event['data']);
          ownedViews.reconcile(objects(snapshot['sessions']));
          _deviceRequest++;
          _settingsRequest++;
          _settingsEpoch++;
          _shareRequest++;
          next = next.copyWith(
            devices: objects(snapshot['devices']),
            settings: jsonObject(snapshot['settings']),
            pendingShares: objects(snapshot['shares'])
                .where(
                  (share) =>
                      !_consumedShareIds.contains(value(share, 'shareId')),
                )
                .toList(),
            loading: false,
            deviceError: () => _screenFailureFor(objects(snapshot['devices'])),
            settingsError: () => null,
            reconciliationPending: false,
            reconciliationError: () => null,
            reconciledSnapshot: () => snapshot,
          );
        }
        if (event['type'] == 'settings.changed' &&
            event['data'] is Map<Object?, Object?>) {
          _settingsRequest++;
          _settingsEpoch++;
          next = next.copyWith(settings: jsonObject(event['data']));
        }
        if (event['type'] == 'share.received' &&
            event['data'] is Map<Object?, Object?>) {
          next = _withShare(next, jsonObject(event['data']));
        }
        state = next;
        if (event['type'] == 'device.screen.failed') {
          _screenFailure = (
            deviceId: value(event, 'deviceId'),
            connectionId: value(data, 'connectionId'),
            reason: value(data, 'reason'),
          );
          state = state.copyWith(
            deviceError: () => '未能自动点亮设备：${data['reason']}',
          );
        }
        // Bound pages must see the calibrated state while handling this event.
        events.add(frozen);
        if (value(event, 'type').startsWith('session.') ||
            ['state.resynced', 'devices.changed'].contains(event['type'])) {
          _scheduleDeviceAudio();
        }
        if (value(event, 'type').startsWith('device') &&
            event['type'] != 'device.screen.failed') {
          unawaited(refreshDevices());
        }
      },
      onError: (Object error) {
        if (!_current(generation)) return;
        state = state.copyWith(deviceError: () => '连接状态更新中断：$error');
        unawaited(refreshDevices());
      },
    );
    ref.onDispose(() {
      ownedViews.invalidate();
      if (_generation == generation) {
        _disposed = true;
        _remoteDeviceViews.clear();
        final devices = {
          ..._managedAudioSources.keys,
          ..._audioDeviceWork.keys,
        };
        _managedAudioSources.clear();
        for (final device in devices) {
          unawaited(
            dependencies
                .request('audio.stop', {'deviceId': device})
                .catchError((Object _) => <String, dynamic>{}),
          );
        }
      }
      unawaited(subscription.cancel());
      unawaited(events.close());
      final close = dependencies.close;
      if (close != null) unawaited(close());
    });
    if (dependencies.initialize) {
      Future<void>.microtask(() async {
        if (_current(generation)) await initialize();
      });
    }
    return dependencies.initialState;
  }

  bool _current(int generation) =>
      !_disposed && _generation == generation && ref.mounted;
  bool isDisposed() => _disposed || !ref.mounted;
  AppState snapshot() => state;
  Stream<Json> eventStream() => _events.stream;
  Future<Json> execute(InteropCommand command, [Json params = const {}]) =>
      request(command.wire, params);

  Future<Json> request(String command, [Json params = const {}]) {
    // Publish user stop intent before its acknowledgement. A transport failure
    // may otherwise race the stop and make a visible page recreate the stream.
    // Bridge-internal failed-output cleanup bypasses this public UI entry.
    final activity = command == 'activities.stop' ? params['activityId'] : null;
    final sessionStop = command == 'session.stop'
        ? params['sessionId']
        : activity is String && activity.startsWith('session:')
        ? activity.substring(8)
        : null;
    final deviceStop =
        ['devices.disconnect', 'devices.forget'].contains(command)
        ? params['deviceId']
        : activity is String && activity.startsWith('connection:')
        ? activity.substring(11)
        : null;
    if (!_events.isClosed && sessionStop is String) {
      _events.add({
        'type': 'session.stop.requested',
        'data': {'sessionId': sessionStop},
      });
    } else if (!_events.isClosed && deviceStop is String) {
      _events.add({
        'type': 'device.disconnect.requested',
        'deviceId': deviceStop,
        'data': <String, dynamic>{},
      });
    }
    return _dependencies.request(command, params);
  }

  Future<void> initialize() =>
      Future.wait([refreshDevices(), loadSettings(), loadPendingShares()]);

  AppState _withShare(AppState source, Json share) {
    final id = value(share, 'shareId');
    if (id.isEmpty || _consumedShareIds.contains(id)) {
      return source;
    }
    final index = source.pendingShares.indexWhere(
      (item) => item['shareId'] == id,
    );
    if (index >= 0) {
      // An attachment snapshot may race the import's terminal event. Keep its
      // position in the queue while accepting ready/error updates, and never
      // replace a terminal receipt with an earlier importing snapshot.
      final current = source.pendingShares[index];
      if (['ready', 'error'].contains(current['status']) &&
          ['starting', 'importing'].contains(share['status'])) {
        return source;
      }
      return source.copyWith(
        pendingShares: [
          for (var i = 0; i < source.pendingShares.length; i++)
            i == index ? share : source.pendingShares[i],
        ],
      );
    }
    return source.copyWith(pendingShares: [...source.pendingShares, share]);
  }

  Future<void> loadPendingShares() async {
    final generation = _generation;
    final requestId = ++_shareRequest;
    try {
      final result = await execute(InteropCommand.sharingPending);
      if (!_current(generation) || requestId != _shareRequest) return;
      var next = state;
      for (final share in objects(result['shares'])) {
        next = _withShare(next, share);
      }
      if (!identical(state, next)) state = next;
    } catch (_) {
      // Unsupported platforms have no share queue; payload errors stay attached.
    }
  }

  Future<void> consumeShare(String id) async {
    final generation = _generation;
    await execute(InteropCommand.sharingConsume, {'shareId': id});
    if (!_current(generation)) return;
    _consumedShareIds.add(id);
    state = state.copyWith(
      pendingShares: state.pendingShares
          .where((share) => share['shareId'] != id)
          .toList(),
    );
  }

  Future<void> refreshDevices() async {
    final generation = _generation;
    if (!_current(generation)) return;
    final requestId = ++_deviceRequest;
    state = state.copyWith(loading: true);
    try {
      final result = await execute(InteropCommand.devicesList);
      if (!_current(generation) || requestId != _deviceRequest) return;
      state = state.copyWith(
        devices: objects(result['devices']),
        loading: false,
        deviceError: () => _screenFailureFor(objects(result['devices'])),
      );
      _scheduleDeviceAudio();
    } catch (error) {
      if (_current(generation) && requestId == _deviceRequest) {
        state = state.copyWith(loading: false, deviceError: () => '$error');
      }
    }
  }

  Future<void> loadSettings() async {
    final generation = _generation;
    final requestId = ++_settingsRequest;
    try {
      final result = await execute(InteropCommand.settingsGet);
      if (_current(generation) && requestId == _settingsRequest) {
        _settingsEpoch++;
        state = state.copyWith(settings: result, settingsError: () => null);
      }
    } catch (error) {
      if (_current(generation) && requestId == _settingsRequest) {
        state = state.copyWith(settingsError: () => '$error');
      }
    }
  }

  Future<void> updateSettings(Json patch) {
    final generation = _generation;
    _settingsRequest++;
    final operation = _settingsQueue.catchError((Object _) {}).then((_) async {
      if (!_current(generation)) return;
      final epoch = _settingsEpoch;
      final result = await execute(InteropCommand.settingsUpdate, patch);
      if (_current(generation) && epoch == _settingsEpoch) {
        state = state.copyWith(
          settings: {...state.settings, ...patch, ...result},
        );
      }
    });
    _settingsQueue = operation;
    return operation;
  }

  Future<void> updateSetting(String key, Object? next) =>
      updateSettings({key: next});

  Future<void> updateDeviceSetting(String deviceId, String key, Object? next) =>
      updateDeviceSettings(deviceId, {key: next});

  Future<void> updateDeviceSettings(String deviceId, Json patch) {
    final generation = _generation;
    _settingsRequest++;
    final operation = _settingsQueue.catchError((Object _) {}).then((_) async {
      if (!_current(generation)) return;
      final epoch = _settingsEpoch;
      final settings = jsonObject(state.settings['deviceSettings']);
      final devices = <String, dynamic>{
        ...settings,
        deviceId: {...jsonObject(settings[deviceId]), ...patch},
      };
      final result = await execute(InteropCommand.settingsUpdate, {
        'deviceSettings': devices,
      });
      if (_current(generation) && epoch == _settingsEpoch) {
        state = state.copyWith(
          settings: {...state.settings, 'deviceSettings': devices, ...result},
        );
      }
    });
    _settingsQueue = operation;
    return operation;
  }

  Future<void> focusDevice(String? id) async {
    if (isDisposed()) return;
    if (state.focusedDeviceId != id) {
      state = state.copyWith(focusedDeviceId: () => id);
    }
  }

  void _scheduleDeviceAudio() {
    if (isDisposed() || !_hasDeviceAudioWork) return;
    _deviceAudioDirty = true;
    if (_deviceAudioScheduled) return;
    _deviceAudioScheduled = true;
    final generation = _generation;
    Future<void>.microtask(() async {
      try {
        // Intermediate events only require one further pass over current state.
        // Never accumulate an async reconciliation for every event in a burst.
        if (_current(generation)) {
          _deviceAudioDirty = false;
          await _syncDeviceAudio(generation);
        }
      } finally {
        if (_current(generation)) {
          _deviceAudioScheduled = false;
          if (_deviceAudioDirty) _scheduleDeviceAudio();
        }
      }
    });
  }

  bool get _hasDeviceAudioWork =>
      _remoteDeviceViews.isNotEmpty ||
      _managedAudioSources.isNotEmpty ||
      _audioDeviceWork.isNotEmpty ||
      _audioStops.isNotEmpty;

  bool _wantsDeviceAudio(String device, int generation, [int? epoch]) =>
      _current(generation) &&
      !state.reconciliationPending &&
      (epoch == null || (_audioDeviceEpochs[device] ?? 0) == epoch) &&
      _remoteDeviceViews.containsValue(device) &&
      state.devices.any(
        (record) => record['id'] == device && record['status'] == 'connected',
      );

  /// Device stop also cancels the bridge's pending start intent synchronously.
  /// It must never wait behind any device's player startup or ready receipt.
  void _stopDeviceAudio(String device, {String? sourceId}) {
    _audioDeviceEpochs[device] = (_audioDeviceEpochs[device] ?? 0) + 1;
    _audioDeviceWork.remove(device);
    if (_audioStops.containsKey(device)) return;
    final generation = _generation;
    var stopped = false;
    late final Future<void> stopping;
    stopping = _dependencies
        .request('audio.stop', {'deviceId': device, 'sourceId': ?sourceId})
        .then<void>((_) {
          stopped = true;
          if (!_current(generation)) return;
          if (sourceId == null || _managedAudioSources[device] == sourceId) {
            _managedAudioSources.remove(device);
          }
          _audioFailures.remove(device);
          _publishAudioFailures();
        })
        .catchError((Object error) {
          if (_current(generation)) {
            _audioFailures[device] = '$error';
            _publishAudioFailures();
          }
        })
        .whenComplete(() {
          if (identical(_audioStops[device], stopping)) {
            _audioStops.remove(device);
          }
          if (stopped && _current(generation)) _scheduleDeviceAudio();
        });
    _audioStops[device] = stopping;
  }

  void _publishAudioFailures() {
    if (isDisposed() || state.reconciliationPending) return;
    state = state.copyWith(
      audioError: () => _audioFailures.isEmpty
          ? null
          : '设备声音未能播放：${_audioFailures.values.join('；')}',
    );
  }

  Future<void> _syncDeviceAudio(int generation) async {
    if (!_current(generation) ||
        state.reconciliationPending ||
        !_hasDeviceAudioWork) {
      return;
    }
    // A start can finish while these snapshots are in flight. Its absence from
    // an older source snapshot must not trigger another start in this pass.
    final starting = _audioDeviceWork.keys.toSet();
    try {
      final sources = objects(
        (await execute(InteropCommand.audioSources))['sources'],
      );
      if (!_current(generation) || state.reconciliationPending) return;
      final sessions = _remoteDeviceViews.isEmpty
          ? <Json>[]
          : objects((await execute(InteropCommand.sessionList))['sessions']);
      if (!_current(generation) || state.reconciliationPending) return;
      final wanted = _remoteDeviceViews.values
          .where(
            (device) =>
                _wantsDeviceAudio(device, generation) &&
                sessions.any(
                  (session) =>
                      session['deviceId'] == device &&
                      [
                        'streaming',
                        'active',
                        'ready',
                        'paused',
                        'starting',
                      ].contains(session['status']),
                ),
          )
          .toSet();
      final active = <String>{};
      for (final source in sources) {
        if (!['playing', 'starting', 'paused'].contains(source['status'])) {
          continue;
        }
        final device = value(source, 'deviceId');
        final sourceId = value(source, 'sourceId', value(source, 'id'));
        if (wanted.contains(device)) {
          active.add(device);
          _managedAudioSources[device] = sourceId;
        } else if (!_audioStops.containsKey(device)) {
          _stopDeviceAudio(device, sourceId: sourceId);
        }
      }
      for (final device in wanted.difference(active)) {
        if (starting.contains(device) || _audioDeviceWork.containsKey(device)) {
          continue;
        }
        final epoch = _audioDeviceEpochs[device] ?? 0;
        late final Future<void> work;
        work = _startDeviceAudio(device, generation, epoch).whenComplete(() {
          if (identical(_audioDeviceWork[device], work)) {
            _audioDeviceWork.remove(device);
          }
          if (_current(generation) &&
              (_audioDeviceEpochs[device] ?? 0) != epoch) {
            _scheduleDeviceAudio();
          }
        });
        _audioDeviceWork[device] = work;
      }
      _publishAudioFailures();
    } catch (error) {
      if (_current(generation) && !state.reconciliationPending) {
        state = state.copyWith(audioError: () => '设备声音未能播放：$error');
      }
    }
  }

  Future<void> _startDeviceAudio(
    String device,
    int generation,
    int epoch,
  ) async {
    final dependencies = _dependencies;
    try {
      await _audioStops[device];
      if (!_wantsDeviceAudio(device, generation, epoch)) return;
      final source = await execute(InteropCommand.audioStart, {
        'deviceId': device,
      });
      final sourceId = value(source, 'sourceId', value(source, 'id'));
      if (!_wantsDeviceAudio(device, generation, epoch)) {
        await dependencies.request('audio.stop', {
          'deviceId': device,
          'sourceId': sourceId,
        });
        return;
      }
      _managedAudioSources[device] = sourceId;
      if (!['playing', 'paused'].contains(source['status'])) {
        throw StateError(value(source, 'reason', '尚未确认设备声音开始播放。'));
      }
      _audioFailures.remove(device);
    } catch (error) {
      if (_wantsDeviceAudio(device, generation, epoch)) {
        _audioFailures[device] = '$error';
      }
    }
    if (_current(generation)) _publishAudioFailures();
  }

  Json currentDevice(Json original) => state.devices.firstWhere(
    (device) => device['id'] == original['id'],
    orElse: () => original,
  );
  void updateClipboardState(String next, [String? error]) {
    if (isDisposed() ||
        state.clipboardState == next && state.clipboardError == error) {
      return;
    }
    state = state.copyWith(clipboardState: next, clipboardError: () => error);
  }

  void recordClipboardRead() {
    if (!isDisposed()) {
      state = state.copyWith(clipboardReadCount: state.clipboardReadCount + 1);
    }
  }

  void recordClipboardWrite() {
    if (!isDisposed()) {
      state = state.copyWith(
        clipboardWriteCount: state.clipboardWriteCount + 1,
      );
    }
  }

  void recordClipboardSend() {
    if (!isDisposed()) {
      state = state.copyWith(clipboardSendCount: state.clipboardSendCount + 1);
    }
  }
}
