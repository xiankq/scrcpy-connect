import 'dart:async';

import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';

/// 协调本地呈现与核心转发状态；官方服务在本地呈现暂停时仍继续捕获。
class VideoPlaybackService {
  VideoPlaybackService({
    required this.pauseCapture,
    required this.resumeCapture,
    required this.sessionsForDevice,
    required this.pauseOutput,
    required this.resumeOutput,
  });

  final Future<VideoSessionSnapshot> Function(ControlTarget) pauseCapture,
      resumeCapture;
  final Future<List<VideoSessionSnapshot>> Function(String deviceId)
  sessionsForDevice;
  final Future<VideoOutputReceipt> Function(String) pauseOutput, resumeOutput;
  final _tails = <String, Future<void>>{};
  final _queued = <String, int>{};

  Future<VideoPlaybackReceipt> setPaused(
    ControlTarget target, {
    required bool paused,
  }) async {
    var id = target.sessionId;
    if (id == null || id.isEmpty) {
      if (target.deviceId == null || target.deviceId!.isEmpty) {
        throw const RequestFailure('session_required', '缺少控制会话。');
      }
      final matches = await sessionsForDevice(target.deviceId!);
      if (matches.isEmpty) {
        throw const RequestFailure('session_required', '请先打开这台设备的实时画面。');
      }
      if (matches.length > 1) {
        throw const RequestFailure('ambiguous_session', '这台设备有多个控制会话，请选择具体画面。');
      }
      id = matches.single.sessionId;
    }
    if (id.isEmpty) {
      throw const RequestFailure('session_required', '缺少控制会话。');
    }
    final session = id;
    final count = _queued[session] ?? 0;
    if (count >= 8) {
      throw const RequestFailure('renderer_busy', '视频状态操作过于频繁，请稍后再试。');
    }
    _queued[session] = count + 1;
    final operation = (_tails[session] ?? Future<void>.value()).then((_) async {
      final bound = target.copyWith(sessionId: session);
      if (!paused) {
        // 核心先恢复转发并请求新的编码画面，再要求解码器确认播放状态和实际解码像素。
        final remote = await resumeCapture(bound);
        final local = await resumeOutput(session);
        return VideoPlaybackReceipt(session: remote, output: local);
      }
      try {
        final local = await pauseOutput(session);
        final remote = await pauseCapture(bound);
        return VideoPlaybackReceipt(session: remote, output: local);
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
