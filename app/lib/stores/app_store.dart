import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/services/gallery_history_cache.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/models/app_state.dart';

part 'app_store.g.dart';

@Riverpod(keepAlive: true)
class AppStore extends _$AppStore {
  bool completeDocumentSelection(String id, Json result) =>
      !_disposed &&
      (_dependencies.completeDocumentSelection?.call(id, result) ?? false);

  final galleryHistory = GalleryHistoryCache();
  late AppDependencies _dependencies;
  late StreamController<Json> _events;

  ({String device, String session})? _clipboardFocus;

  void Function() bindClipboardAdmission(
    bool Function(String, String, int) check,
  ) => _dependencies.bindClipboardAdmission?.call(check) ?? () {};

  String? clipboardSessionFor(String device) =>
      _clipboardFocus?.device == device ? _clipboardFocus?.session : null;

  /// Only a visible control page owns automatic clipboard admission.
  void focusClipboardSession(String device, String session, bool focused) {
    final current = _clipboardFocus;
    final next = focused
        ? (device: device, session: session)
        : current?.device == device && current?.session == session
        ? null
        : current;
    if (_disposed || next == current) return;
    _clipboardFocus = next;
    scheduleMicrotask(() {
      if (!_disposed) _events.add({'type': 'clipboard.focus'});
    });
  }

  final _consumedShareIds = <String>{};
  final _appOpenClaims = <(String, String), Object>{};
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
    galleryHistory.clear();
    _dependencies = dependencies;
    final generation = ++_generation;
    _disposed = false;
    _consumedShareIds.clear();
    _appOpenClaims.clear();
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
      if (_generation == generation) {
        _disposed = true;
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
  int get generation => _generation;

  void updateAudioError(String? error) {
    if (!isDisposed() && state.audioError != error) {
      state = state.copyWith(audioError: () => error);
    }
  }

  Future<Json> execute(ApplicationCommand command, [Json params = const {}]) =>
      _dependencies.execute(command, params);

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

  Future<void> _updateSettings(Json? Function(Json) changes) {
    final generation = _generation;
    _settingsRequest++;
    final operation = _settingsQueue.catchError((Object _) {}).then((_) async {
      if (!_current(generation)) return;
      final patch = changes(state.settings);
      if (patch == null) return;
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

  Future<void> updateSettings(Json patch) => _updateSettings((_) => patch);

  Future<void> updateSetting(String key, Object? next) =>
      updateSettings({key: next});

  Future<void> updateDeviceSetting(String deviceId, String key, Object? next) =>
      updateDeviceSettings(deviceId, {key: next});

  Future<void> updateDeviceSettings(String deviceId, Json patch) =>
      _updateSettings((current) {
        final devices = jsonObject(current['deviceSettings']);
        return {
          'deviceSettings': {
            ...devices,
            deviceId: {...jsonObject(devices[deviceId]), ...patch},
          },
        };
      });

  String? appOpenMode(String deviceId, String packageName) {
    final modes = jsonObject(state.settings['appOpenModes']);
    final mode = jsonObject(modes[deviceId])[packageName];
    return mode == 'phone' || mode == 'window' ? mode as String : null;
  }

  Future<void> rememberAppOpenMode(
    String deviceId,
    String packageName,
    String mode,
  ) {
    if (mode != 'phone' && mode != 'window') {
      throw ArgumentError.value(mode, 'mode');
    }
    return _updateSettings((current) {
      final previous = jsonObject(current['appOpenModes']);
      final device = jsonObject(previous[deviceId]);
      if (device[packageName] == mode) return null;
      return {
        'appOpenModes': {
          ...previous,
          deviceId: {...device, packageName: mode},
        },
      };
    });
  }

  void Function()? claimAppOpen(String deviceId, String packageName) {
    if (_disposed) return null;
    final key = (deviceId, packageName);
    if (_appOpenClaims.containsKey(key)) return null;
    final token = Object();
    _appOpenClaims[key] = token;
    return () {
      if (identical(_appOpenClaims[key], token)) _appOpenClaims.remove(key);
    };
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
