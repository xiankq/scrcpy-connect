import 'dart:async';

import 'package:scrcpy_connect/services/session_views.dart';

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
  late SessionViews sessionViews;
  final _consumedShareIds = <String>{};
  String? _audioFocusTarget;
  Future<void> _audioFocusQueue = Future<void>.value();
  Future<void> _settingsQueue = Future<void>.value();
  bool _disposed = true;
  int _generation = 0;
  int _deviceRequest = 0;
  int _settingsRequest = 0;

  @override
  AppState build() {
    final dependencies = ref.watch(appDependenciesProvider);
    _dependencies = dependencies;
    sessionViews = SessionViews(dependencies.request);
    final ownedViews = sessionViews;
    final generation = ++_generation;
    _disposed = false;
    _consumedShareIds.clear();
    final events = StreamController<Json>.broadcast(sync: true);
    _events = events;
    final subscription = dependencies.events.listen(
      (event) {
        if (!_current(generation)) return;
        final frozen = immutableJson(event);
        events.add(frozen);
        // Native frames belong to their bound surface, never the global state.
        if (event['type'] == 'session.frame') return;
        var next = state.copyWith(
          lastEvent: () => frozen,
          eventRevision: state.eventRevision + 1,
        );
        if (event['type'] == 'settings.changed' &&
            event['data'] is Map<Object?, Object?>) {
          _settingsRequest++;
          next = next.copyWith(settings: jsonObject(event['data']));
        }
        if (event['type'] == 'share.received' &&
            event['data'] is Map<Object?, Object?>) {
          next = _withShare(next, jsonObject(event['data']));
        }
        state = next;
        if (value(event, 'type').startsWith('device')) {
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
      if (_generation == generation) _disposed = true;
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
  Future<Json> request(String command, [Json params = const {}]) =>
      _dependencies.request(command, params);

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
    try {
      final result = await request('sharing.pending');
      if (!_current(generation)) return;
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
    await request('sharing.consume', {'shareId': id});
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
      final result = await request('devices.list');
      if (!_current(generation) || requestId != _deviceRequest) return;
      state = state.copyWith(
        devices: objects(result['devices']),
        loading: false,
        deviceError: () => null,
      );
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
      final result = await request('settings.get');
      if (_current(generation) && requestId == _settingsRequest) {
        state = state.copyWith(settings: result, settingsError: () => null);
      }
    } catch (error) {
      if (_current(generation) && requestId == _settingsRequest) {
        state = state.copyWith(settingsError: () => '$error');
      }
    }
  }

  Future<void> updateSetting(String key, Object? next) {
    final generation = _generation;
    _settingsRequest++;
    final operation = _settingsQueue.catchError((Object _) {}).then((_) async {
      if (!_current(generation)) return;
      final result = await request('settings.update', {key: next});
      if (_current(generation)) {
        state = state.copyWith(
          settings: {...state.settings, key: next, ...result},
        );
      }
    });
    _settingsQueue = operation;
    return operation;
  }

  void rememberAudioDevices(List<Object?> ids) {
    if (isDisposed()) return;
    // A successful user stop must not be undone by focus when saving fails.
    state = state.copyWith(settings: {...state.settings, 'audioDevices': ids});
  }

  void cancelAudioFollow() {
    _audioFocusTarget = null;
    if (!isDisposed() && state.audioError != null) {
      state = state.copyWith(audioError: () => null);
    }
  }

  Future<void> focusDevice(String? id) {
    final generation = _generation;
    if (!_current(generation)) return Future<void>.value();
    if (state.focusedDeviceId != id) {
      state = state.copyWith(focusedDeviceId: () => id);
    }
    _audioFocusTarget = id;
    if (id == null) return Future<void>.value();
    _audioFocusQueue = _audioFocusQueue.then((_) async {
      bool intended() =>
          _current(generation) &&
          _audioFocusTarget == id &&
          value(state.settings, 'audioMode', 'follow') == 'follow' &&
          state.settings['audioDevices'] is List<Object?> &&
          (state.settings['audioDevices'] as List<Object?>).isNotEmpty;
      if (!intended()) return;
      try {
        final sources = objects((await request('audio.sources'))['sources']);
        if (!intended()) return;
        if (sources.any(
          (source) => source['deviceId'] == id && source['status'] == 'playing',
        )) {
          return;
        }
        for (final source in sources.where(
          (source) =>
              source['deviceId'] != id &&
              ['playing', 'starting', 'paused'].contains(source['status']),
        )) {
          if (!intended()) return;
          await request('audio.stop', {
            'deviceId': source['deviceId'],
            'sourceId': source['sourceId'] ?? source['id'],
          });
        }
        if (!intended()) return;
        final result = await request('audio.start', {'deviceId': id});
        if (!intended()) return;
        if (result['status'] != 'playing') {
          throw StateError(value(result, 'reason', '尚未确认设备声音开始播放。'));
        }
        await updateSetting('audioDevices', [id]);
        if (intended()) state = state.copyWith(audioError: () => null);
      } catch (error) {
        if (intended()) {
          state = state.copyWith(audioError: () => '声音切换未完成：$error');
        }
      }
    });
    return _audioFocusQueue;
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
