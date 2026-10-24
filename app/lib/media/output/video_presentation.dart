import 'dart:async';

import 'package:scrcpy_connect/application/transport/application_command_exception.dart';

import 'package:scrcpy_connect/media/output/video_player_port.dart';

/// 合并核心会话状态与最新渲染输出。
/// 播放器回执可能携带恢复请求时的旧核心状态，因此只有渲染证据可覆盖当前会话快照。
VideoJson sessionWithVideoOutput(VideoJson session, VideoJson? output) {
  final capture = session['captureGeneration'];
  final outputCapture = output?['captureGeneration'];
  final renderer = session['rendererGeneration'];
  final outputRenderer = output?['generation'];
  final previousCapture =
      capture is int && output != null && capture != outputCapture;
  final previousRenderer =
      renderer is int && outputRenderer is int && outputRenderer < renderer;
  if (previousCapture || previousRenderer) {
    return {
      ...session,
      for (final key in const [
        'textureId',
        'decodedWidth',
        'decodedHeight',
        'backend',
      ])
        if (output?.containsKey(key) == true) key: output![key],
      'outputCaptureGeneration': outputCapture,
      'outputGeneration': outputRenderer,
      'outputRetained': true,
      'firstFrameDecoded': false,
      'evidence': 'retained_previous_output',
    };
  }
  return {
    ...session,
    for (final key in const [
      'relayId',
      'textureId',
      'decodedWidth',
      'decodedHeight',
      'decoderName',
      'hardwareAccelerated',
      'generation',
      'backend',
      'firstFrameDecoded',
      'evidence',
      'snapshotReceipts',
      'decodedReceipts',
      'platformTexturePrepared',
      'presentedSequence',
      'presentationPath',
      'presentedToWidget',
      'continuousFrameTelemetry',
      'outputStartupTimingMs',
    ])
      if (output?.containsKey(key) == true) key: output![key],
    if (outputCapture is int) 'outputCaptureGeneration': outputCapture,
    if (outputCapture is int && outputRenderer is int)
      'outputGeneration': outputRenderer,
  };
}

/// 合并同一会话的回执，不覆盖更新的渲染输出。
/// 迟到恢复的状态及帧证据属于旧纹理；无代际回执不能替换已知代际，同代际可更新渲染证据。
VideoJson mergeVideoOutputReceipt(VideoJson? current, VideoJson receipt) {
  final currentGeneration = current?['generation'];
  final receiptGeneration = receipt['generation'];
  if (currentGeneration is int &&
      (receiptGeneration is! int || receiptGeneration < currentGeneration)) {
    return {...current!};
  }
  return {...?current, ...receipt};
}

/// 协调本地呈现与核心转发状态；官方服务在本地呈现暂停时仍继续捕获。
class VideoPresentation {
  VideoPresentation({
    required this._request,
    required this.pauseOutput,
    required this.resumeOutput,
  });

  final VideoRequest _request;
  final Future<VideoJson> Function(String) pauseOutput, resumeOutput;
  final _tails = <String, Future<void>>{};
  final _queued = <String, int>{};

  Future<VideoJson> request(String command, VideoJson params) async {
    if (command != 'session.pause' && command != 'session.resume') {
      throw ArgumentError.value(command, 'command');
    }
    var id = params['sessionId'];
    if (id is! String || id.isEmpty) {
      final sessions = await _request('session.list', {});
      final matches = (sessions['sessions'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .where((s) => s['deviceId'] == params['deviceId']);
      if (matches.isEmpty) {
        throw const ApplicationCommandException(
          'session_required',
          '请先打开这台设备的实时画面。',
        );
      }
      if (matches.length > 1) {
        throw const ApplicationCommandException(
          'ambiguous_session',
          '这台设备有多个控制会话，请选择具体画面。',
        );
      }
      id = matches.first['sessionId'];
    }
    if (id is! String || id.isEmpty) {
      throw const ApplicationCommandException('session_required', '缺少控制会话。');
    }
    final session = id;
    final count = _queued[session] ?? 0;
    if (count >= 8) {
      throw const ApplicationCommandException(
        'renderer_busy',
        '视频状态操作过于频繁，请稍后再试。',
      );
    }
    _queued[session] = count + 1;
    final operation = (_tails[session] ?? Future<void>.value()).then((_) async {
      final request = {...params, 'sessionId': session};
      if (command == 'session.resume') {
        // 核心先恢复转发并请求新的编码画面，再要求解码器确认播放状态和实际解码像素。
        final remote = await _request(command, request);
        final local = await resumeOutput(session);
        return {...remote, ...local};
      }
      try {
        final local = await pauseOutput(session);
        final remote = await _request(command, request);
        return {...remote, ...local};
      } catch (_) {
        // 失败请求仍可能已改变异步播放器，应尽可能恢复消费者。
        try {
          await resumeOutput(session);
        } catch (_) {
          // 保留原错误，不能伪造回滚确认。
        }
        rethrow;
      }
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[session] = tail;
    return operation.whenComplete(() {
      final remaining = (_queued[session] ?? 1) - 1;
      if (remaining == 0) {
        _queued.remove(session);
      } else {
        _queued[session] = remaining;
      }
      if (identical(_tails[session], tail)) _tails.remove(session);
    });
  }
}
