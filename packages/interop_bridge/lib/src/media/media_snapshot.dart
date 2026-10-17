import '../interop_exception.dart';
import '../state_recovery.dart';
import 'video_presentation.dart';

/// Captures local owners before reading core state. A replacement or a new
/// output created during that read is never retired by the older snapshot.
Future<StateJson> readMediaSnapshot({
  required Future<StateJson> Function() read,
  required Map<String, StateJson> videos,
  required Map<String, StateJson> audios,
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
    if (!current()) throw const InteropException('cancelled', '状态恢复已结束。');
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
        sessionWithVideoOutput(session, videos[session['sessionId']]),
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
      throw const InteropException('invalid_snapshot', '状态快照包含无效或重复的媒体标识。');
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
    ].contains(record['status']))
      record[id] as String,
};
