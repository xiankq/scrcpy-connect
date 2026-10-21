import 'dart:async';

import '../interop_exception.dart';
import 'video_player_port.dart';

/// Combines core session state with the renderer's latest output. Player
/// receipts may also contain old core state from a resume request, so only
/// rendering evidence may override the current session snapshot.
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

/// Merges receipts for one session without replacing a newer renderer output.
/// A delayed resume may finish after a generation change; its state and frame
/// evidence belong to the old texture. Unversioned receipts cannot replace a
/// known generation, while receipts for the same generation may update state.
VideoJson mergeVideoOutputReceipt(VideoJson? current, VideoJson receipt) {
  final currentGeneration = current?['generation'];
  final receiptGeneration = receipt['generation'];
  if (currentGeneration is int &&
      (receiptGeneration is! int || receiptGeneration < currentGeneration)) {
    return {...current!};
  }
  return {...?current, ...receipt};
}

/// Coordinates local presentation with core forwarding state.
/// The official server continues capturing while presentation is paused.
class VideoPresentation {
  VideoPresentation({
    required this.core,
    required this.pauseOutput,
    required this.resumeOutput,
  });

  final VideoCoreRequest core;
  final Future<VideoJson> Function(String) pauseOutput, resumeOutput;
  final _tails = <String, Future<void>>{};
  final _queued = <String, int>{};

  Future<VideoJson> request(String command, VideoJson params) async {
    if (command != 'session.pause' && command != 'session.resume') {
      throw ArgumentError.value(command, 'command');
    }
    var id = params['sessionId'];
    if (id is! String || id.isEmpty) {
      final sessions = await core('session.list', {});
      final matches = (sessions['sessions'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .where((s) => s['deviceId'] == params['deviceId']);
      if (matches.isEmpty) {
        throw const InteropException('session_required', '请先打开这台设备的实时画面。');
      }
      if (matches.length > 1) {
        throw const InteropException(
          'ambiguous_session',
          '这台设备有多个控制会话，请选择具体画面。',
        );
      }
      id = matches.first['sessionId'];
    }
    if (id is! String || id.isEmpty) {
      throw const InteropException('session_required', '缺少控制会话。');
    }
    final session = id;
    final count = _queued[session] ?? 0;
    if (count >= 8) {
      throw const InteropException('renderer_busy', '视频状态操作过于频繁，请稍后再试。');
    }
    _queued[session] = count + 1;
    final operation = (_tails[session] ?? Future<void>.value()).then((_) async {
      final request = {...params, 'sessionId': session};
      if (command == 'session.resume') {
        // Core resumes forwarding and requests a fresh encoder session before MDK
        // is asked to confirm playing and actual decoded pixels.
        final remote = await core(command, request);
        final local = await resumeOutput(session);
        return {...remote, ...local};
      }
      try {
        final local = await pauseOutput(session);
        final remote = await core(command, request);
        return {...remote, ...local};
      } catch (_) {
        // A failed request may still have changed the asynchronous player.
        // Restore the consumer if possible.
        try {
          await resumeOutput(session);
        } catch (_) {
          // Preserve the original failure; never manufacture a rollback ACK.
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
