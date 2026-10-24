import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/platform/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/media/output/audio_player_port.dart';
import 'package:scrcpy_connect/media/quality/device_quality_coordinator.dart';
import 'package:scrcpy_connect/media/capture/media_intent_registry.dart';
import 'package:scrcpy_connect/media/capture/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/media/output/audio_output_coordinator.dart';
import 'package:scrcpy_connect/media/output/video_output_coordinator.dart';
import 'package:scrcpy_connect/media/output/video_output_lifecycle.dart';
import 'package:scrcpy_connect/media/output/video_presentation.dart';
import 'package:scrcpy_connect/media/quality/video_quality_policy.dart';

import 'package:scrcpy_connect/media/output/media_output_reconciliation.dart';
import 'package:scrcpy_connect/application/lifecycle/ordered_disposal.dart';

/// 拥有当前 Dart 附着的媒体输出、启动意图与释放回执。
/// 设备连接和原生捕获仍由执行层持有。
final class MediaCoordinator {
  MediaCoordinator({
    required this.invoke,
    required this.platform,
    required this.emit,
    required this.isDisposed,
    required this.dataDirectory,
    required this.capture,
    this.diagnostics,
  });

  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  invoke;
  final AudioRequest platform;
  final void Function(Map<String, dynamic>) emit;
  final bool Function() isDisposed;
  final String dataDirectory;
  final ScrcpyCaptureAdapter capture;
  final DiagnosticLog? diagnostics;
  bool _closing = false;
  bool get _disposed => _closing || isDisposed();
  final _textures = <String, Map<String, dynamic>>{};
  final _videoMonitors = <String, Timer>{};
  final _videoPolling = <String>{};
  final _audioSources = <String, Map<String, dynamic>>{};
  final _audioClosings = <String, Future<void>>{};
  final _mediaIntents = MediaIntentRegistry();
  late final _audioOutputs = AudioOutputCoordinator(
    request: invoke,
    diagnostics: diagnostics,
    platform: platform,
    emit: _handleAudioOutput,
    isDisposed: () => _disposed,
  );
  late final _deviceQuality = DeviceQualityCoordinator(
    request: invoke,
    applyOutput: (stream) async {
      final id = stream['sessionId'] as String;
      Map<String, dynamic> output;
      try {
        output = await _videoOutputs.reconfigure(stream);
      } catch (_) {
        _videoLifecycle.retainFailedOutput(id);
        rethrow;
      }
      final merged = {...stream, ...output};
      if (_textures.containsKey(id)) _textures[id] = merged;
      await invoke('session.ready', merged);
      return merged;
    },
    beginReconfigure: (id) => _videoLifecycle.beginReconfigure(id),
    endReconfigure: (id) => _videoLifecycle.endReconfigure(id),
  );
  late final _videoOutputs = VideoOutputCoordinator(
    request: invoke,
    openSource: capture.openSource,
    emit: _handleVideoOutput,
    diagnostics: diagnostics,
    isDisposed: () => _disposed,
  );
  late final _videoPresentation = VideoPresentation(
    request: invoke,
    pauseOutput: _videoOutputs.pause,
    resumeOutput: _videoOutputs.resume,
  );
  late final VideoOutputLifecycle _videoLifecycle = VideoOutputLifecycle(
    outputs: _textures,
    request: invoke,
    closeOutput: _closeVideo,
    reattachOutput: (id, endpoint) =>
        _videoOutputs.reattach(id, endpoint: endpoint),
    emit: emit,
    isDisposed: () => _disposed,
  );
  Future<void> _closeVideo(
    String id, {
    ApplicationCommandException? failure,
  }) async {
    _videoLifecycle.forget(id);
    if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.video] close session=$id from=${StackTrace.current}',
      );
    }
    _videoMonitors.remove(id)?.cancel();
    _textures.remove(id);
    await _videoOutputs.stop(id, failure: failure);
  }

  void _handleVideoOutput(Map<String, dynamic> event) {
    _videoLifecycle.handle(event);
  }

  void _monitorVideo(String id) {
    _videoMonitors.remove(id)?.cancel();
    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_videoPolling.add(id)) return;
      unawaited(
        _pollVideo(id, timer).whenComplete(() => _videoPolling.remove(id)),
      );
    });
    _videoMonitors[id] = timer;
  }

  Future<void> _pollVideo(String id, Timer owner) async {
    await _videoLifecycle.poll(
      id,
      current: () => !_disposed && identical(_videoMonitors[id], owner),
    );
  }

  Future<void> _closeAudio(String id) {
    if (_audioClosings[id] case final pending?) return pending;
    final closing = _releaseAudio(id);
    _audioClosings[id] = closing;
    void finished() {
      if (identical(_audioClosings[id], closing)) _audioClosings.remove(id);
    }

    unawaited(
      closing.then<void>(
        (_) => finished(),
        onError: (Object _, StackTrace _) => finished(),
      ),
    );
    return closing;
  }

  Future<void> _releaseAudio(String id) async {
    _audioSources.remove(id);
    await _audioOutputs.stop(id);
  }

  void _handleAudioOutput(Map<String, dynamic> event) {
    if (_disposed) return;
    emit(event);
    final data = Map<String, dynamic>.from(event['data'] as Map);
    final id = data['sourceId'];
    final source = _audioSources[id];
    if (id is! String ||
        source == null ||
        data['deviceId'] != source['deviceId']) {
      return;
    }
    if (event['type'] == 'audio.output.failed' ||
        (event['type'] == 'audio.presentation' && _terminalAudioFocus(data))) {
      // 等待前先认领精确所有者，防止重复或迟到的焦点事件二次停止或影响其他设备的替换源。
      _audioSources.remove(id);
      _mediaIntents.stop(id, audio: true);
      unawaited(() async {
        try {
          await invoke('audio.stop', {
            'sourceId': id,
            'deviceId': source['deviceId'],
          });
        } catch (_) {
          /* 精确源可能已经结束，不能仅按设备停止。 */
        } finally {
          await _closeAudio(id);
        }
      }());
    } else if (event['type'] == 'audio.presentation') {
      unawaited(
        invoke(
          'audio.presentation',
          data,
        ).catchError((Object _) => <String, dynamic>{}),
      );
    }
  }

  bool _terminalAudioFocus(Map<String, dynamic> receipt) =>
      receipt['requiresUserResume'] == true &&
      ['permanentLoss', 'noisy'].contains(receipt['focusSignal']);

  Future<Map<String, dynamic>> capabilities() async =>
      _videoOutputs.capabilities();

  Future<void> retireUnownedAudio() async {
    final known =
        (await invoke('audio.sources', const {}))['sources'] as List? ??
        const [];
    for (final source in known.whereType<Map<Object?, Object?>>()) {
      if (source['sourceId'] is String &&
          source['deviceId'] is String &&
          !['stopped', 'failed', 'error'].contains(source['status'])) {
        await invoke('audio.stop', {
          'sourceId': source['sourceId'],
          'deviceId': source['deviceId'],
        });
      }
    }
  }

  Future<void> _ensureVideoDecoder(Map<String, dynamic> params) async {
    final settings = await invoke('settings.get', const {});
    final codec = VideoQualityPolicy.resolve(
      settings,
      params['deviceId'] as String?,
      params,
    )['videoCodec'];
    final localCapabilities = await capabilities();
    final supported = (localCapabilities['codecs'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .any(
          (item) =>
              item['id'] == codec &&
              (item['available'] == true || item['canAttempt'] == true),
        );
    if (!supported) {
      throw ApplicationCommandException(
        'decoder_unavailable',
        '本机尚未提供 $codec 解码器，请选择其他视频编码。',
      );
    }
  }

  Future<Map<String, dynamic>> snapshot(bool Function() current) =>
      readAndReconcileMediaSnapshot(
        read: () => invoke('state.snapshot', {}),
        videos: _textures,
        audios: _audioSources,
        closeVideo: _closeVideo,
        closeAudio: _closeAudio,
        current: current,
      );

  void handleApplicationEvent(Map<String, dynamic> event) {
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : const <String, dynamic>{};
    if (event['type'] == 'device.changed' &&
        data['status'] != 'connected' &&
        event['deviceId'] is String) {
      _mediaIntents.stopDevice(event['deviceId'] as String);
    }
    if (event['type'] == 'session.disconnected') {
      final id = data['sessionId'];
      if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
        debugPrint(
          '[connect.video] capture ended session=$id reason=${data['reason']}',
        );
      }
      if (id is String) {
        unawaited(
          _closeVideo(
            id,
            failure: data['status'] == 'failed'
                ? ApplicationCommandException(
                    data['failureCode'] is String
                        ? data['failureCode'] as String
                        : 'session_failed',
                    data['reason'] is String
                        ? data['reason'] as String
                        : '被控端的画面连接意外结束，请重新打开。',
                  )
                : null,
          ),
        );
      }
    } else if (event['type'] == 'audio.updated' &&
        const [
          'stopped',
          'failed',
          'error',
          'closed',
        ].contains(data['status'])) {
      final id = data['sourceId'];
      if (id is String) unawaited(_closeAudio(id));
    }
  }

  Future<void> setVisible(bool visible) => _audioOutputs.setVisible(visible);
  Future<void> policy(bool enabled) => _audioOutputs.policy(enabled);
  Future<void> handlePlatformEvent(Map<String, dynamic> event) async {
    if (event['type'] == 'connections.stopped') {
      _mediaIntents.cancelAll();
      await Future.wait(_textures.keys.toList().map(_closeVideo));
      await Future.wait(_audioSources.keys.toList().map(_closeAudio));
    } else {
      await _audioOutputs.handlePlatformEvent(event);
    }
  }

  Future<Map<String, dynamic>> dispatch(
    String command,
    Map<String, dynamic> params,
    Future<Map<String, dynamic>> Function(
      String,
      Map<String, dynamic>, {
      MediaIntent? intent,
    })
    next,
  ) async {
    _deviceQuality.beforeRequest(command, params);
    if (command == 'session.stop' && params['sessionId'] is String) {
      _videoLifecycle.forget(params['sessionId'] as String);
      _mediaIntents.stop(params['sessionId'] as String, audio: false);
    } else if (command == 'audio.stop' && params['sourceId'] is String) {
      _mediaIntents.stop(params['sourceId'] as String, audio: true);
    } else if (command == 'audio.stop' && params['deviceId'] is String) {
      _mediaIntents.stopAudioDevice(params['deviceId'] as String);
    } else if (['devices.disconnect', 'devices.forget'].contains(command)) {
      _mediaIntents.stopDevice('${params['deviceId']}');
    } else if (command == 'activities.stop' && params['activityId'] is String) {
      final id = params['activityId'] as String;
      if (id.startsWith('session:')) {
        _mediaIntents.stop(id.substring(8), audio: false);
      }
      if (id.startsWith('connection:')) {
        _mediaIntents.stopDevice(id.substring(11));
      }
    }
    final starts = [
      'session.start',
      'apps.launch',
      'audio.start',
    ].contains(command);
    final intent = starts
        ? _mediaIntents.begin(
            '${params['deviceId']}',
            audio: command == 'audio.start',
          )
        : null;

    try {
      return command == 'session.start' || command == 'apps.launch'
          ? await _deviceQuality.open(
              '${params['deviceId']}',
              () => next(command, params, intent: intent),
            )
          : await next(command, params, intent: intent);
    } finally {
      if (intent != null) _mediaIntents.finish(intent);
    }
  }

  Future<Map<String, dynamic>> execute(
    String command,
    Map<String, dynamic> params, {
    MediaIntent? intent,
  }) async {
    final stoppingAudioIds = command == 'audio.stop'
        ? _audioSources.keys
              .where(
                (id) => params['sourceId'] is String
                    ? id == params['sourceId']
                    : _audioSources[id]?['deviceId'] == params['deviceId'],
              )
              .toList()
        : const <String>[];
    if (command == 'audio.status') {
      return _audioOutputs.status(params['sourceId'] as String?);
    }
    if (command == 'session.pause' || command == 'session.resume') {
      final receipt = await _videoPresentation.request(command, params);
      final id = receipt['sessionId'];
      if (command == 'session.resume' &&
          !_disposed &&
          id is String &&
          _textures.containsKey(id) &&
          receipt['firstFrameDecoded'] == true) {
        _textures[id] = mergeVideoOutputReceipt(_textures[id], receipt);
        emit({
          'type': 'session.output.resumed',
          'deviceId': receipt['deviceId'],
          'data': receipt,
        });
      }
      return receipt;
    }
    if (command == 'video.capabilities') {
      return capabilities();
    }
    if (['session.start', 'apps.launch', 'session.quality'].contains(command)) {
      await _ensureVideoDecoder(
        command == 'session.quality'
            ? params
            : {'deviceId': params['deviceId']},
      );
    }
    if (command == 'session.quality') return _deviceQuality.change(params);
    if (command == 'session.screenshot' && params['sessionId'] is String) {
      final directory = await Directory('$dataDirectory/screenshots')
          .create(recursive: true);
      return _videoOutputs.screenshot(
        params['sessionId'] as String,
        directory: directory.path,
      );
    }
    if (command == 'audio.volume') {
      final proposed = await invoke(command, params);
      final applied = await _audioOutputs.volume(
        proposed['sourceId'] as String,
        volume: (proposed['volume'] as num).toDouble(),
        muted: proposed['muted'] == true,
      );
      final updated = await invoke(command, {
        ...params,
        ...proposed,
        ...applied,
      });
      return {...updated, ...applied};
    }
    if (command == 'audio.pause' || command == 'audio.resume') {
      final proposed = await invoke(command, params);
      final id = proposed['sourceId'] as String;
      final applied = command == 'audio.pause'
          ? await _audioOutputs.pause(id)
          : await _audioOutputs.resume(id);
      final updated = await invoke(command, {
        ...params,
        ...proposed,
        ...applied,
      });
      return {...updated, ...applied};
    }
    if (_disposed || intent?.cancelled == true) {
      throw const ApplicationCommandException(
        'cancelled',
        '已停止本次打开，不会重新启动画面或声音。',
      );
    }
    final result = await invoke(command, params);
    if (command == 'session.quality.options') {
      final local = await capabilities();
      final decoders = (local['codecs'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>();
      final choices = <Map<String, dynamic>>[];
      for (final entry
          in (result['codecs'] as List? ?? const [])
              .whereType<Map<Object?, Object?>>()) {
        final choice = Map<String, dynamic>.from(entry);
        final matching = decoders.where(
          (decoder) => decoder['id'] == choice['id'],
        );
        final decoder = matching.firstOrNull;
        final localAvailable =
            decoder?['available'] == true || decoder?['canAttempt'] == true;
        choices.add({
          ...choice,
          'targetStatus': choice['status'],
          'decoderStatus': decoder?['status'] ?? 'unknown',
          'decoders': decoder?['decoders'] ?? const <Object?>[],
          'available': choice['available'] == true && localAvailable,
          if (!localAvailable) 'reason': '本机没有可用解码器。',
        });
      }
      return {
        ...result,
        'codecs': choices,
        'codec': [
          for (final choice in choices)
            {...choice, 'label': choice['name'], 'value': choice['id']},
        ],
        'decoderProbe': local['probe'],
      };
    }
    if (result['audioSourceId'] is String && result['sourceId'] is String) {
      intent?.bind('${result['sourceId']}');
      if (_disposed || intent?.cancelled == true) {
        await invoke('audio.stop', {
          'deviceId': result['deviceId'],
          'sourceId': result['sourceId'],
        });
        throw const ApplicationCommandException('cancelled', '已停止本次声音，不会重新启动。');
      }
      final id = result['sourceId'] as String;
      _audioSources[id] = result;
      try {
        final playback = await _audioOutputs.start(
          result,
          cancelled: () => _disposed || intent?.cancelled == true,
        );
        if (_disposed || intent?.cancelled == true) {
          throw const ApplicationCommandException(
            'cancelled',
            '已停止本次声音，不会重新启动。',
          );
        }
        if (_terminalAudioFocus(playback)) {
          // 首次实际播放可能在 ready 回执到达前已丢失焦点，此时仍必须停止原生捕获。
          throw const ApplicationCommandException(
            'audio_focus_lost',
            '声音焦点已结束，请重新打开此设备声音。',
          );
        }
        final ready = await invoke('audio.ready', {...result, ...playback});
        if (_disposed || intent?.cancelled == true) {
          throw const ApplicationCommandException(
            'cancelled',
            '已停止本次声音，不会重新启动。',
          );
        }
        return {...ready, ...playback};
      } catch (_) {
        try {
          await invoke('audio.stop', {
            'deviceId': result['deviceId'],
            'sourceId': id,
          });
        } finally {
          await _closeAudio(id);
        }
        rethrow;
      }
    }
    // 进程内能力只在新建捕获时返回；状态更新和暂停、恢复继续使用已有输出。
    if (result['videoSourceId'] is String && result['sessionId'] is String) {
      final id = result['sessionId'] as String;
      intent?.bind(id);
      if (_disposed || intent?.cancelled == true) {
        await invoke('session.stop', {
          'sessionId': id,
          if (result['packageName'] is String) 'keepLaunchRecord': true,
        });
        throw const ApplicationCommandException('cancelled', '已停止本次画面，不会重新启动。');
      }
      try {
        final texture = await _videoOutputs.start(
          result,
          cancelled: () => _disposed || intent?.cancelled == true,
        );
        if (_disposed || intent?.cancelled == true) {
          throw const ApplicationCommandException(
            'cancelled',
            '已停止本次画面，不会重新启动。',
          );
        }
        _textures[id] = {...result, ...texture};
        await invoke('session.ready', {'sessionId': id, ...texture});
        if (_disposed || intent?.cancelled == true) {
          throw const ApplicationCommandException(
            'cancelled',
            '已停止本次画面，不会重新启动。',
          );
        }
        _monitorVideo(id);
        return {...result, ...texture, 'status': 'connected'};
      } catch (error) {
        final appLaunch = result['packageName'] is String;
        try {
          await invoke('session.stop', {
            'sessionId': id,
            if (appLaunch) 'keepLaunchRecord': true,
          });
        } catch (_) {
          /* 保留原始输出错误。 */
        }
        await _closeVideo(id);
        if (appLaunch) {
          throw ApplicationCommandException(
            'app_launch_unknown',
            '应用可能已在手机上打开，请先核对本次记录。',
            {
              'sessionId': id,
              'deviceId': result['deviceId'],
              'packageName': result['packageName'],
              'launchOutcome': 'unknown',
              'failureCode': error is ApplicationCommandException
                  ? error.code
                  : 'video_output_failed',
            },
          );
        }
        rethrow;
      }
    }
    if (command == 'session.list' && result['sessions'] is List) {
      return {
        ...result,
        'sessions': [
          for (final item in result['sessions'] as List)
            sessionWithVideoOutput(
              Map<String, dynamic>.from(item as Map),
              _textures[item['sessionId']],
            ),
        ],
      };
    }
    if (command == 'session.stop') {
      final id = result['sessionId'];
      if (id is String) _mediaIntents.stop(id, audio: false);
      if (id is String) await _closeVideo(id);
    }
    if (command == 'audio.stop') {
      for (final id in stoppingAudioIds) {
        await _closeAudio(id);
      }
      final source = params['sourceId'];
      final device = params['deviceId'];
      if (source is String && !stoppingAudioIds.contains(source)) {
        await _closeAudio(source);
      } else if (source == null && device is String) {
        await _audioOutputs.stopDevice(device);
      }
    }
    if (command == 'activities.stop' &&
        result['status'] == 'stopped' &&
        result['sourceId'] is String &&
        result['deviceId'] is String &&
        params['activityId'] == 'audio:${result['sourceId']}') {
      final id = result['sourceId'] as String;
      final source = _audioSources[id];
      if (source == null || source['deviceId'] == result['deviceId']) {
        // 核心回执将停止绑定到精确捕获代际；取消该启动意图并等待本地播放器释放后才返回。
        _mediaIntents.stop(id, audio: true);
        await _closeAudio(id);
      }
    }
    final activity = params['activityId'];
    final deviceId =
        command == 'devices.disconnect' || command == 'devices.forget'
        ? params['deviceId']
        : command == 'activities.stop' &&
              activity is String &&
              activity.startsWith('connection:')
        ? activity.substring(11)
        : null;
    if (deviceId is String) {
      for (final id
          in _textures.keys
              .where((id) => _textures[id]?['deviceId'] == deviceId)
              .toList()) {
        await _closeVideo(id);
      }
      for (final id
          in _audioSources.keys
              .where((id) => _audioSources[id]?['deviceId'] == deviceId)
              .toList()) {
        await _closeAudio(id);
      }
      // 页面快照已撤销也可能还有失败或超时的旧输出，仍按设备核对真实释放。
      await Future.wait([
        _videoOutputs.stopDevice(deviceId),
        _audioOutputs.stopDevice(deviceId),
      ]);
    }
    return result;
  }

  OrderedDisposal? _disposal;
  void stopAdmission() {
    _closing = true;
    _deviceQuality.dispose();
    _mediaIntents.cancelAll();
  }

  Future<void> dispose() {
    stopAdmission();
    _disposal ??= _prepareDisposal();
    return _disposal!.run();
  }

  OrderedDisposal _prepareDisposal() {
    final pending = _mediaIntents.active.toList();
    final videoIds = {
      ..._textures.keys,
      ...pending.where((i) => !i.audio).expand((i) => i.ids),
    };
    final audioIds = {
      ..._audioSources.keys,
      ...pending.where((i) => i.audio).expand((i) => i.ids),
    };
    return OrderedDisposal([
      for (final id in videoIds) () => _closeVideo(id),
      _videoOutputs.dispose,
      for (final id in audioIds)
        () async {
          final device = _audioSources[id]?['deviceId'];
          if (device is String) {
            try {
              await invoke('audio.stop', {'sourceId': id, 'deviceId': device});
            } catch (_) {
              /* 原生源可能已结束，本地输出仍需释放。 */
            }
          }
          await _closeAudio(id);
        },
      _audioOutputs.dispose,
      () async {
        _textures.clear();
        _audioSources.clear();
        try {
          await Future.wait(pending.map((i) => i.done))
              .timeout(const Duration(seconds: 45));
        } on TimeoutException {
          // 迟到的原生启动继续由原所有者完成有界取消清理。
        }
      },
    ]);
  }
}
