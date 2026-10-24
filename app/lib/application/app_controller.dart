import 'package:scrcpy_connect/media/device_audio_view_coordinator.dart';
import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:scrcpy_connect/media/session_view_registry.dart';
import 'package:scrcpy_connect/media/control_page_registry.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/application/app_dependencies.dart';
import 'package:scrcpy_connect/application/app_state.dart';

part 'app_controller.g.dart';

@Riverpod(keepAlive: true)
class AppController extends _$AppController {
  late AppDependencies _dependencies;
  late StreamController<Json> _events;
  late SessionViewRegistry _sessionViewRegistry;
  late ControlPageRegistry _controlPages;
  late DeviceAudioViewCoordinator _deviceAudio;

  /// 调用者只能释放一次，仅最后一个实际画面可请求锁屏。
  bool Function() claimControlPage(String deviceId, {String? sessionId}) {
    final pages = _controlPages;
    final token = pages.claim(deviceId, sessionId: sessionId);
    return () => pages.release(token);
  }

  bool hasControlPages(String deviceId) => _controlPages.hasPages(deviceId);

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

  final _consumedShareIds = <String>{};
  Future<void> _settingsQueue = Future<void>.value();
  bool _disposed = true;
  int _generation = 0;
  int _deviceRequest = 0;
  int _settingsRequest = 0;
  // 权威状态变化单独作废保存回执，不与排队写入的顺序混为一谈。
  int _settingsEpoch = 0;
  int _shareRequest = 0;

  @override
  AppState build() {
    final dependencies = ref.watch(appDependenciesProvider);
    _dependencies = dependencies;
    _sessionViewRegistry = SessionViewRegistry(dependencies.request);
    _controlPages = ControlPageRegistry();
    final ownedViews = _sessionViewRegistry;
    final generation = ++_generation;
    _disposed = false;
    final ownedAudio = _deviceAudio = DeviceAudioViewCoordinator(
      request: dependencies.request,
      readSnapshot: () => DeviceAudioViewSnapshot(
        devices: state.devices,
        reconciliationPending: state.reconciliationPending,
      ),
      onError: (error) {
        if (_current(generation)) {
          state = state.copyWith(audioError: () => error);
        }
      },
    );
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
        // 原生帧只属于绑定画面，不进入全局状态。
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
            deviceError: () => null,
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
        if (event['type'] == 'share.consumed') {
          final id = value(data, 'shareId');
          if (id.isNotEmpty) {
            _shareRequest++;
            _consumedShareIds.add(id);
            next = next.copyWith(
              pendingShares: next.pendingShares
                  .where((share) => share['shareId'] != id)
                  .toList(),
            );
          }
        }
        if (event['type'] == 'share.received' &&
            event['data'] is Map<Object?, Object?>) {
          next = _withShare(next, jsonObject(event['data']));
        }
        state = next;
        // 绑定页面处理事件前必须先看到校准后的状态。
        events.add(frozen);
        if (value(event, 'type').startsWith('session.') ||
            ['state.resynced', 'devices.changed'].contains(event['type'])) {
          _deviceAudio.reconcile();
        }
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
      if (_generation == generation) {
        _disposed = true;
      }
      ownedAudio.dispose();
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
  Future<Json> execute(ApplicationCommand command, [Json params = const {}]) =>
      request(command.wire, params);

  Future<Json> request(String command, [Json params = const {}]) {
    // 回执前先发布用户停止意图，避免传输失败与停止竞争时页面重建画面；桥接内部清理不走此入口。
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
      // 附着快照可能晚于导入终态；保留队列位置并接受更新，不能用旧导入态覆盖已完成回执。
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
      final result = await execute(ApplicationCommand.sharingPending);
      if (!_current(generation) || requestId != _shareRequest) return;
      var next = state;
      for (final share in objects(result['shares'])) {
        next = _withShare(next, share);
      }
      if (!identical(state, next)) state = next;
    } catch (_) {
      // 不支持分享的平台没有队列；内容错误仍保留在对应分享记录上。
    }
  }

  Future<void> consumeShare(String id) async {
    final generation = _generation;
    await execute(ApplicationCommand.sharingConsume, {'shareId': id});
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
      final result = await execute(ApplicationCommand.devicesList);
      if (!_current(generation) || requestId != _deviceRequest) return;
      state = state.copyWith(
        devices: objects(result['devices']),
        loading: false,
        deviceError: () => null,
      );
      _deviceAudio.reconcile();
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
      final result = await execute(ApplicationCommand.settingsGet);
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
      final result = await execute(ApplicationCommand.settingsUpdate, patch);
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
      final result = await execute(ApplicationCommand.settingsUpdate, {
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
