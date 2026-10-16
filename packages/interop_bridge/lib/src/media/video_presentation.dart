import 'dart:async';

import '../interop_exception.dart';
import 'video_player_port.dart';

/// Coordinates the local consumer and the existing remote capture process.
/// Pausing capture first would starve the local reader's state acknowledgement.
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
        // Core resumes capture and requests a fresh encoder session before MDK
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
        // Keep the remote source running and restore the consumer if possible.
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
