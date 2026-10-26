import 'dart:async';

import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

class _AudioStopFailure {
  _AudioStopFailure(this.error);

  final Object? error;
}

/// 音源准入只读取当前连接与核验状态，不接管应用快照。
class DeviceAudioViewSnapshot {
  const DeviceAudioViewSnapshot({
    required this.devices,
    required this.reconciliationPending,
  });

  final List<Json> devices;
  final bool reconciliationPending;
}

/// 按设备共享声音；页面租约、启动取消、停止去重与迟到回执由同一所有者协调。
class DeviceAudioViewCoordinator {
  DeviceAudioViewCoordinator({
    required this._request,
    required this._readSnapshot,
    required this._onError,
  });

  final ApplicationRequest _request;
  final DeviceAudioViewSnapshot Function() _readSnapshot;
  final void Function(String?) _onError;
  bool _disposed = false;
  int _generation = 0;

  bool _current(int generation) => !_disposed && _generation == generation;
  Future<Json> _execute(ApplicationCommand command, [Json params = const {}]) =>
      _request(command.wire, params);

  final _remoteDeviceViews = <Object, String>{};
  final _managedAudioSources = <String, String>{};
  final _audioDeviceWork = <String, Future<void>>{};
  final _audioStops = <(String, String?), Future<void>>{};
  final _audioStopFailures = <(String, String?), _AudioStopFailure>{};
  final _audioDeviceEpochs = <String, int>{};
  final _audioFailures = <String, String>{};
  final _resumeRequired = <String, int>{};
  int _resumeRevision = 0;
  bool _deviceAudioScheduled = false;
  bool _deviceAudioDirty = false;

  void handleEvent(Json event) {
    if (_disposed || event['type'] != 'audio.resume.required') return;
    final data = jsonObject(event['data']);
    final device = value(data, 'deviceId');
    if (device.isEmpty || data['requiresUserResume'] != true) return;
    _resumeRequired[device] = ++_resumeRevision;
  }

  int playbackRequestRevision(String command, Json params) =>
      _resumeRequired[value(params, 'deviceId')] ?? 0;

  void playbackSucceeded(
    String command,
    Json params,
    Json result,
    int revision,
  ) {
    if (_disposed || !const ['audio.start', 'audio.resume'].contains(command)) {
      return;
    }
    final device = value(result, 'deviceId', value(params, 'deviceId'));
    if ((_resumeRequired[device] ?? 0) != revision ||
        result['requiresUserResume'] == true) {
      return;
    }
    _resumeRequired.remove(device);
    reconcile();
  }

  /// 页面被遮挡时仍持有声音租约，最后一个页面释放后停止该设备的共享音源。
  void Function() claimView(String deviceId) {
    if (_disposed) return () {};
    final token = Object();
    _remoteDeviceViews[token] = deviceId;
    reconcile();
    return () {
      if (_disposed) return;
      if (_remoteDeviceViews.remove(token) == null) return;
      if (!_remoteDeviceViews.containsValue(deviceId)) {
        // 新的明确关闭可重试此前耗尽的清理；事件本身不能无限重放失败停止。
        _audioStopFailures.removeWhere((key, _) => key.$1 == deviceId);
        unawaited(_stopDeviceAudio(deviceId));
      }
      reconcile();
    };
  }

  void reconcile() {
    if (_disposed || !_hasDeviceAudioWork) return;
    _deviceAudioDirty = true;
    if (_deviceAudioScheduled) return;
    _deviceAudioScheduled = true;
    final generation = _generation;
    Future<void>.microtask(() async {
      try {
        // 突发事件只要求按最新状态再核对一次，避免每个事件各积累一条异步协调任务。
        if (_current(generation)) {
          _deviceAudioDirty = false;
          await _syncDeviceAudio(generation);
        }
      } finally {
        if (_current(generation)) {
          _deviceAudioScheduled = false;
          if (_deviceAudioDirty) reconcile();
        }
      }
    });
  }

  bool get _hasDeviceAudioWork =>
      _remoteDeviceViews.isNotEmpty ||
      _managedAudioSources.isNotEmpty ||
      _audioDeviceWork.isNotEmpty ||
      _audioStops.isNotEmpty ||
      _audioStopFailures.isNotEmpty;

  bool _wantsDeviceAudio(String device, int generation, [int? epoch]) =>
      _current(generation) &&
      !_readSnapshot().reconciliationPending &&
      (epoch == null || (_audioDeviceEpochs[device] ?? 0) == epoch) &&
      _remoteDeviceViews.containsValue(device) &&
      _readSnapshot().devices.any(
        (record) => record['id'] == device && record['status'] == 'connected',
      );

  /// 首次按设备停止以撤销在途启动，后续优先绑定精确音源；最多三次，不依赖外部事件。
  Future<void> _stopDeviceAudio(String device, {String? sourceId}) {
    _audioDeviceEpochs[device] = (_audioDeviceEpochs[device] ?? 0) + 1;
    _audioDeviceWork.remove(device);
    final exactSource = sourceId ?? _managedAudioSources[device];
    final key = (device, exactSource);
    if (_audioStops[key] case final pending?) return pending;
    if (_audioStopFailures.containsKey(key)) return Future<void>.value();
    final generation = _generation;
    var stopped = false;
    late final Future<void> stopping;
    stopping =
        Future<void>.sync(() async {
          Object? lastFailure;
          for (var attempt = 0; attempt < 3; attempt++) {
            // 无精确身份时，重新取得页面租约后不能用旧清理按设备停止新声音。
            if (attempt > 0 &&
                exactSource == null &&
                _remoteDeviceViews.containsValue(device)) {
              break;
            }
            try {
              await _request('audio.stop', {
                'deviceId': device,
                'sourceId': ?(attempt == 0 ? sourceId : exactSource),
              });
              stopped = true;
              _audioStopFailures.remove(key);
              if (_current(generation)) {
                if (exactSource == null ||
                    _managedAudioSources[device] == exactSource) {
                  _managedAudioSources.remove(device);
                }
                _audioFailures.remove(device);
              }
              return;
            } catch (failure) {
              lastFailure = failure;
            }
          }
          // 耗尽后仍保留身份与错误；后续快照可确认它已结束，不能当作成功清理。
          _audioStopFailures[key] = _AudioStopFailure(lastFailure);
        }).whenComplete(() {
          if (identical(_audioStops[key], stopping)) _audioStops.remove(key);
          if (_current(generation)) {
            _publishAudioFailures();
            if (stopped) reconcile();
          }
        });
    _audioStops[key] = stopping;
    return stopping;
  }

  bool _stoppingSource(String device, String sourceId) =>
      _audioStops.containsKey((device, sourceId)) ||
      _audioStops.containsKey((device, null)) ||
      _audioStopFailures.containsKey((device, sourceId));

  void _publishAudioFailures() {
    if (_disposed || _readSnapshot().reconciliationPending) return;
    final failures = {
      ..._audioFailures.values,
      for (final failure in _audioStopFailures.values) '${failure.error}',
    };
    _onError(failures.isEmpty ? null : '设备声音未能播放：${failures.join('；')}');
  }

  Future<void> _syncDeviceAudio(int generation) async {
    if (!_current(generation) ||
        _readSnapshot().reconciliationPending ||
        !_hasDeviceAudioWork) {
      return;
    }
    // 读取快照期间启动可能已完成，旧快照缺少音源不能在本轮触发重复启动。
    final starting = _audioDeviceWork.keys.toSet();
    final observedStopFailures = Map.of(_audioStopFailures);
    try {
      final sources = objects(
        (await _execute(ApplicationCommand.audioSources))['sources'],
      );
      if (!_current(generation) || _readSnapshot().reconciliationPending) {
        return;
      }
      for (final source in sources) {
        final device = value(source, 'deviceId');
        if (device.isNotEmpty && source['requiresUserResume'] == true) {
          _resumeRequired.putIfAbsent(device, () => ++_resumeRevision);
        }
      }
      final liveSources = {
        for (final source in sources)
          if (['playing', 'starting', 'paused'].contains(source['status']))
            (
              value(source, 'deviceId'),
              value(source, 'sourceId', value(source, 'id')),
            ),
      };
      _managedAudioSources.removeWhere(
        (device, source) =>
            !liveSources.contains((device, source)) &&
            !starting.contains(device),
      );
      _audioStopFailures.removeWhere(
        // 快照只能核销读取前已经观察到的同一次失败，不能覆盖期间新增或替换的清理。
        (key, failure) =>
            identical(observedStopFailures[key], failure) &&
            (key.$2 == null
                ? !liveSources.any((live) => live.$1 == key.$1)
                : !liveSources.contains(key)),
      );
      final sessions = _remoteDeviceViews.isEmpty
          ? <Json>[]
          : objects(
              (await _execute(ApplicationCommand.sessionList))['sessions'],
            );
      if (!_current(generation) || _readSnapshot().reconciliationPending) {
        return;
      }
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
        } else if (!_stoppingSource(device, sourceId)) {
          unawaited(_stopDeviceAudio(device, sourceId: sourceId));
        }
      }
      for (final device in wanted.difference(active)) {
        if (_resumeRequired.containsKey(device)) continue;
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
            reconcile();
          }
        });
        _audioDeviceWork[device] = work;
      }
      _publishAudioFailures();
    } catch (error) {
      if (_current(generation) && !_readSnapshot().reconciliationPending) {
        _onError('设备声音未能播放：$error');
      }
    }
  }

  Future<void> _startDeviceAudio(
    String device,
    int generation,
    int epoch,
  ) async {
    try {
      await Future.wait([
        for (final entry in _audioStops.entries)
          if (entry.key.$1 == device) entry.value,
      ]);
      if (!_wantsDeviceAudio(device, generation, epoch)) return;
      final source = await _execute(ApplicationCommand.audioStart, {
        'deviceId': device,
      });
      final sourceId = value(source, 'sourceId', value(source, 'id'));
      if (!_wantsDeviceAudio(device, generation, epoch)) {
        await _stopDeviceAudio(device, sourceId: sourceId);
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

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _remoteDeviceViews.clear();
    final devices = {..._managedAudioSources.keys, ..._audioDeviceWork.keys};
    final failedSources = _audioStopFailures.keys.toList();
    _audioStopFailures.clear();
    for (final device in devices) {
      unawaited(_stopDeviceAudio(device));
    }
    // 迟到音源可能仅剩失败记录持有身份；释放所有者时仍给它一次有界的精确清理。
    for (final (device, sourceId) in failedSources) {
      unawaited(_stopDeviceAudio(device, sourceId: sourceId));
    }
  }
}
