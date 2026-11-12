import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/recovered_video_session.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/recovery/models/runtime_snapshot.dart';

/// 读取核心状态并回收已结束输出，再借用本机呈现证据。
/// 读取前捕获本地所有者；读取期间新建或替换的输出不能被旧快照释放。
Future<RuntimeSnapshot> readAndReconcileMediaSnapshot({
  required Future<RuntimeSnapshot> Function() read,
  required Map<String, VideoOutputReceipt> videos,
  required Map<String, DeviceAudioSnapshot> audios,
  required Future<void> Function(String) closeVideo,
  required Future<void> Function(String) closeAudio,
  required bool Function() current,
}) async {
  final capturedVideos = {...videos}, capturedAudios = {...audios};
  final snapshot = await read();
  final liveSessions = {
    for (final item in snapshot.sessions)
      if (item.live) item.session.sessionId,
  };
  final liveSources = {
    for (final source in snapshot.sources)
      if (source.status != .stopped && source.status != .error) source.sourceId,
  };
  void check() {
    if (!current()) {
      throw const RequestFailure('cancelled', '状态恢复已结束。');
    }
  }

  check();
  for (final entry in capturedVideos.entries) {
    check();
    if (!liveSessions.contains(entry.key) &&
        identical(videos[entry.key], entry.value)) {
      await closeVideo(entry.key);
    }
  }
  for (final entry in capturedAudios.entries) {
    check();
    if (!liveSources.contains(entry.key) &&
        identical(audios[entry.key], entry.value)) {
      await closeAudio(entry.key);
    }
  }
  check();
  return snapshot.withSessions([
    for (final item in snapshot.sessions)
      RecoveredVideoSession(
        session: item.session,
        keepAwake: item.keepAwake,
        output: videos[item.session.sessionId],
      ),
  ]);
}
