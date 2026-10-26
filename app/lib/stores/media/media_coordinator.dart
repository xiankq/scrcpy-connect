import 'package:scrcpy_connect/services/media/video_output_snapshot.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/generated/commands_generated.dart';
import 'package:scrcpy_connect/services/command_contract.dart';
import 'package:scrcpy_connect/services/media/media_capture_operations.dart';
import 'package:scrcpy_connect/services/platform/diagnostic_log.dart';
import 'package:scrcpy_connect/services/media/audio_player_port.dart';
import 'package:scrcpy_connect/stores/media/device_quality_coordinator.dart';
import 'package:scrcpy_connect/stores/media/media_intent_registry.dart';
import 'package:scrcpy_connect/services/media/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/stores/media/audio_output_coordinator.dart';
import 'package:scrcpy_connect/stores/media/video_output_coordinator.dart';
import 'package:scrcpy_connect/stores/media/video_output_lifecycle.dart';
import 'package:scrcpy_connect/stores/media/video_presentation.dart';
import 'package:scrcpy_connect/services/media/video_quality_policy.dart';

import 'package:scrcpy_connect/services/media/media_output_reconciliation.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';

/// 拥有当前 Dart 附着的媒体输出、启动意图与释放回执。
/// 设备连接和原生捕获仍由执行层持有。
final class MediaCoordinator {
  MediaCoordinator({
    required this.invoke,
    required this.captures,
    required this.readSnapshot,
    required this.readSettings,
    required this.platform,
    required this.emit,
    required this.isDisposed,
    required this.dataDirectory,
    required this.capture,
    this.diagnostics,
  });

  final Future<Map<String, dynamic>> Function(
    ApplicationCommand,
    Map<String, dynamic>,
  )
  invoke;
  final MediaCaptureOperations captures;
  final Future<Map<String, dynamic>> Function() readSnapshot;
  final Future<Map<String, dynamic>> Function() readSettings;

  Future<Map<String, dynamic>> _request(
    String command,
    Map<String, dynamic> params,
  ) => invoke(validateCommandRequest(command, params), params);
  final AudioRequest platform;
  final void Function(Map<String, dynamic>) emit;
  final bool Function() isDisposed;
  final String dataDirectory;
  final ScrcpyCaptureAdapter capture;
  final DiagnosticLog? diagnostics;
  bool _closing = false;
  bool get _disposed => _closing || isDisposed();
  final _textures = <String, Map<String, dynamic>>{};
  final _audioSources = <String, Map<String, dynamic>>{};
  final _audioClosings = <String, Future<void>>{};
  final _mediaIntents = MediaIntentRegistry();
  late final _audioOutputs = AudioOutputCoordinator(
    request: captures.request,
    diagnostics: diagnostics,
    platform: platform,
    emit: _handleAudioOutput,
    isDisposed: () => _disposed,
  );
  late final _deviceQuality = DeviceQualityCoordinator(
    request: _request,
    applyOutput: (stream) async {
      final id = stream['sessionId'] as String;
      Map<String, dynamic> output;
      try {
        output = await _videoOutputs.reconfigure(stream);
      } catch (error) {
        _videoLifecycle.retainFailedOutput(id);
        captures.videoOutputFailed(stream, error);
        rethrow;
      }
      final merged = {...stream, ...output};
      if (_textures.containsKey(id)) _textures[id] = merged;
      await captures.readyVideo(merged);
      return merged;
    },
    beginReconfigure: (id) => _videoLifecycle.beginReconfigure(id),
    endReconfigure: (id) => _videoLifecycle.endReconfigure(id),
  );
  late final _videoOutputs = VideoOutputCoordinator(
    request: captures.request,
    openSource: capture.openSource,
    emit: (event) => _videoLifecycle.handle(event),
    diagnostics: diagnostics,
    isDisposed: () => _disposed,
  );
  late final _videoPresentation = VideoPresentation(
    request: captures.request,
    pauseOutput: _videoOutputs.pause,
    resumeOutput: _videoOutputs.resume,
  );
  late final VideoOutputLifecycle _videoLifecycle = VideoOutputLifecycle(
    outputs: _textures,
    request: captures.request,
    closeOutput: (id, {failure}) async {
      await _videoOutputs.stop(id, failure: failure);
    },
    reattachOutput: (id, endpoint) =>
        _videoOutputs.reattach(id, endpoint: endpoint),
    emit: emit,
    isDisposed: () => _disposed,
  );
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
    if (event['type'] == 'audio.output.failed') {
      // 等待前先认领精确所有者，防止重复或迟到的焦点事件二次停止或影响其他设备的替换源。
      _audioSources.remove(id);
      _mediaIntents.stop(id, audio: true);
      unawaited(() async {
        try {
          await captures.stopAudio(id, source['deviceId'] as String);
        } catch (_) {
          /* 精确源可能已经结束，不能仅按设备停止。 */
        } finally {
          await _closeAudio(id);
        }
      }());
    } else if (event['type'] == 'audio.presentation') {
      unawaited(
        captures
            .presentAudio(data)
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
  }

  Future<Map<String, dynamic>> capabilities() async =>
      _videoOutputs.capabilities();

  Future<void> retireUnownedAudio() async {
    final known =
        (await captures.audioSources())['sources'] as List? ?? const [];
    for (final source in known.whereType<Map<Object?, Object?>>()) {
      if (source['sourceId'] is String &&
          source['deviceId'] is String &&
          !['stopped', 'failed', 'error'].contains(source['status'])) {
        await captures.stopAudio(
          source['sourceId'] as String,
          source['deviceId'] as String,
        );
      }
    }
  }

  Future<void> _ensureVideoDecoder(Map<String, dynamic> params) async {
    final settings = await readSettings();
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
        read: readSnapshot,
        videos: _textures,
        audios: _audioSources,
        closeVideo: _videoLifecycle.close,
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
          _videoLifecycle.close(
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
      await Future.wait(_textures.keys.toList().map(_videoLifecycle.close));
      await Future.wait(_audioSources.keys.toList().map(_closeAudio));
    } else {
      await _audioOutputs.handlePlatformEvent(event);
    }
  }

  Future<Map<String, dynamic>> dispatch(
    ApplicationCommand operation,
    Map<String, dynamic> params,
    Future<Map<String, dynamic>> Function(
      ApplicationCommand,
      Map<String, dynamic>, {
      MediaIntent? intent,
    })
    next,
  ) async {
    final command = operation.wire;
    _deviceQuality.beforeRequest(command, params);
    if (operation == ApplicationCommand.sessionStop &&
        params['sessionId'] is String) {
      _videoLifecycle.forget(params['sessionId'] as String);
      _mediaIntents.stop(params['sessionId'] as String, audio: false);
    } else if (operation == ApplicationCommand.audioStop &&
        params['sourceId'] is String) {
      _mediaIntents.stop(params['sourceId'] as String, audio: true);
    } else if (operation == ApplicationCommand.audioStop &&
        params['deviceId'] is String) {
      _mediaIntents.stopAudioDevice(params['deviceId'] as String);
    } else if ([
      ApplicationCommand.devicesDisconnect,
      ApplicationCommand.devicesForget,
    ].contains(operation)) {
      _mediaIntents.stopDevice('${params['deviceId']}');
    } else if (operation == ApplicationCommand.activitiesStop &&
        params['activityId'] is String) {
      final id = params['activityId'] as String;
      if (id.startsWith('session:')) {
        _mediaIntents.stop(id.substring(8), audio: false);
      }
      if (id.startsWith('connection:')) {
        _mediaIntents.stopDevice(id.substring(11));
      }
    }
    final starts = [
      ApplicationCommand.sessionStart,
      ApplicationCommand.appsLaunch,
      ApplicationCommand.audioStart,
    ].contains(operation);
    final intent = starts
        ? _mediaIntents.begin(
            '${params['deviceId']}',
            audio: operation == ApplicationCommand.audioStart,
          )
        : null;

    try {
      return operation == ApplicationCommand.sessionStart ||
              operation == ApplicationCommand.appsLaunch
          ? await _deviceQuality.open(
              '${params['deviceId']}',
              () => next(operation, params, intent: intent),
            )
          : await next(operation, params, intent: intent);
    } finally {
      if (intent != null) _mediaIntents.finish(intent);
    }
  }

  Future<Map<String, dynamic>> execute(
    ApplicationCommand operation,
    Map<String, dynamic> params, {
    MediaIntent? intent,
  }) async {
    final command = operation.wire;
    final stoppingAudioIds = operation == ApplicationCommand.audioStop
        ? _audioSources.keys
              .where(
                (id) => params['sourceId'] is String
                    ? id == params['sourceId']
                    : _audioSources[id]?['deviceId'] == params['deviceId'],
              )
              .toList()
        : const <String>[];
    if (operation == ApplicationCommand.audioStatus) {
      return _audioOutputs.status(params['sourceId'] as String?);
    }
    if (operation == ApplicationCommand.sessionPause ||
        operation == ApplicationCommand.sessionResume) {
      final receipt = await _videoPresentation.request(command, params);
      final id = receipt['sessionId'];
      if (operation == ApplicationCommand.sessionResume &&
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
    if (operation == ApplicationCommand.videoCapabilities) {
      return capabilities();
    }
    if ([
      ApplicationCommand.sessionStart,
      ApplicationCommand.appsLaunch,
      ApplicationCommand.sessionQuality,
    ].contains(operation)) {
      await _ensureVideoDecoder(
        operation == ApplicationCommand.sessionQuality
            ? params
            : {'deviceId': params['deviceId']},
      );
    }
    if (operation == ApplicationCommand.sessionQuality) {
      return _deviceQuality.change(params);
    }
    if (operation == ApplicationCommand.sessionScreenshot &&
        params['sessionId'] is String) {
      final directory = await Directory('$dataDirectory/screenshots')
          .create(recursive: true);
      return _videoOutputs.screenshot(
        params['sessionId'] as String,
        directory: directory.path,
      );
    }
    if (operation == ApplicationCommand.audioVolume ||
        operation == ApplicationCommand.audioPause ||
        operation == ApplicationCommand.audioResume) {
      return _updateAudio(operation, params);
    }
    if (_disposed || intent?.cancelled == true) {
      throw const ApplicationCommandException(
        'cancelled',
        '已停止本次打开，不会重新启动画面或声音。',
      );
    }
    final result = await invoke(operation, params);
    if (operation == ApplicationCommand.sessionQualityOptions) {
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
      return _startAudioOutput(result, intent);
    }
    if (result['videoSourceId'] is String && result['sessionId'] is String) {
      return _startVideoOutput(result, intent);
    }
    if (operation == ApplicationCommand.sessionList &&
        result['sessions'] is List) {
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
    if (operation == ApplicationCommand.sessionStop) {
      final id = result['sessionId'];
      if (id is String) _mediaIntents.stop(id, audio: false);
      if (id is String) await _videoLifecycle.close(id);
    }
    if (operation == ApplicationCommand.audioStop) {
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
    if (operation == ApplicationCommand.activitiesStop &&
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
    Object? deviceId;
    if (operation == ApplicationCommand.devicesDisconnect ||
        operation == ApplicationCommand.devicesForget) {
      deviceId = params['deviceId'];
    } else if (operation == ApplicationCommand.activitiesStop &&
        activity is String &&
        activity.startsWith('connection:')) {
      deviceId = activity.substring(11);
    }
    if (deviceId is String) {
      for (final id
          in _textures.keys
              .where((id) => _textures[id]?['deviceId'] == deviceId)
              .toList()) {
        await _videoLifecycle.close(id);
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

  Future<Map<String, dynamic>> _startAudioOutput(
    Map<String, dynamic> result,
    MediaIntent? intent,
  ) async {
    intent?.bind('${result['sourceId']}');
    if (_disposed || intent?.cancelled == true) {
      await captures.stopAudio(
        result['sourceId'] as String,
        result['deviceId'] as String,
      );
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
        throw const ApplicationCommandException('cancelled', '已停止本次声音，不会重新启动。');
      }
      final ready = await captures.readyAudio({...result, ...playback});
      if (_disposed || intent?.cancelled == true) {
        throw const ApplicationCommandException('cancelled', '已停止本次声音，不会重新启动。');
      }
      return {...ready, ...playback};
    } catch (_) {
      try {
        await captures.stopAudio(id, result['deviceId'] as String);
      } finally {
        await _closeAudio(id);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _startVideoOutput(
    Map<String, dynamic> result,
    MediaIntent? intent,
  ) async {
    final id = result['sessionId'] as String;
    intent?.bind(id);
    if (_disposed || intent?.cancelled == true) {
      await captures.stopVideo(
        id,
        keepLaunchRecord: result['packageName'] is String,
      );
      throw const ApplicationCommandException('cancelled', '已停止本次画面，不会重新启动。');
    }
    try {
      final texture = await _videoOutputs.start(
        result,
        cancelled: () => _disposed || intent?.cancelled == true,
      );
      if (_disposed || intent?.cancelled == true) {
        throw const ApplicationCommandException('cancelled', '已停止本次画面，不会重新启动。');
      }
      _textures[id] = {...result, ...texture};
      await captures.readyVideo({'sessionId': id, ...texture});
      if (_disposed || intent?.cancelled == true) {
        throw const ApplicationCommandException('cancelled', '已停止本次画面，不会重新启动。');
      }
      _videoLifecycle.monitor(id);
      return {...result, ...texture, 'status': 'connected'};
    } catch (error) {
      final appLaunch = result['packageName'] is String;
      try {
        await captures.stopVideo(id, keepLaunchRecord: appLaunch);
      } catch (_) {
        /* 保留原始输出错误。 */
      }
      await _videoLifecycle.close(id);
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

  Future<Map<String, dynamic>> _updateAudio(
    ApplicationCommand operation,
    Map<String, dynamic> params,
  ) async {
    final proposed = await captures.execute(operation, params);
    final id = proposed['sourceId'] as String;
    final applied = switch (operation) {
      ApplicationCommand.audioVolume => await _audioOutputs.volume(
        id,
        volume: (proposed['volume'] as num).toDouble(),
        muted: proposed['muted'] == true,
      ),
      ApplicationCommand.audioPause => await _audioOutputs.pause(id),
      ApplicationCommand.audioResume => await _audioOutputs.resume(id),
      _ => throw StateError('不是声音输出更新：$operation'),
    };
    final updated = await captures.execute(operation, {
      ...params,
      ...proposed,
      ...applied,
    });
    return {...updated, ...applied};
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
      for (final id in videoIds) () => _videoLifecycle.close(id),
      _videoOutputs.dispose,
      for (final id in audioIds)
        () async {
          final device = _audioSources[id]?['deviceId'];
          if (device is String) {
            try {
              await captures.stopAudio(id, device);
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
