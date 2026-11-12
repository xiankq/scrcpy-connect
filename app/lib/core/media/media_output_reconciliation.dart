import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';
import 'package:scrcpy_connect/core/media/video_output_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/state_recovery.dart';

/// 读取核心状态并回收已结束输出，再合成本机呈现状态。
/// 读取前捕获本地所有者；该读取期间新建或替换的输出不能被旧快照释放。
Future<StateJson> readAndReconcileMediaSnapshot({
  required Future<StateJson> Function() read,
  required Map<String, VideoOutputReceipt> videos,
  required Map<String, DeviceAudioSnapshot> audios,
  required Future<void> Function(String) closeVideo,
  required Future<void> Function(String) closeAudio,
  required bool Function() current,
}) async {
  final capturedVideos = {...videos}, capturedAudios = {...audios};
  final snapshot = await read();
  validateStateSnapshot(snapshot);
  final sessions = _records(snapshot['sessions'], 'sessionId');
  final sources = _records(snapshot['sources'], 'sourceId');
  final liveSessions = _live(sessions, 'sessionId'),
      liveSources = _live(sources, 'sourceId');
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
  return {
    ...snapshot,
    'sessions': [
      for (final session in sessions)
        sessionWithVideoOutput(
          session,
          videos[session['sessionId']]?.toSnapshot(),
        ),
    ],
  };
}

List<StateJson> _records(dynamic values, String id) {
  final records = <StateJson>[];
  final ids = <String>{};
  for (final Object? value in values as List) {
    if (value is! Map<String, dynamic> ||
        value[id] is! String ||
        (value[id] as String).isEmpty ||
        !ids.add(value[id] as String)) {
      throw const RequestFailure('invalid_snapshot', '状态快照包含无效或重复的媒体标识。');
    }
    records.add(value);
  }
  return records;
}

Set<String> _live(List<StateJson> records, String id) => {
  for (final record in records)
    if (!const [
          'stopped',
          'error',
          'failed',
          'closed',
          'disconnected',
        ].contains(record['status']) ||
        (id == 'sessionId' &&
            record['status'] == 'failed' &&
            record['qualityRetryable'] == true))
      record[id] as String,
};
