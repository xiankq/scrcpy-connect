import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'remote_audio.dart';
import 'video_screenshots.dart';
import 'video_sessions.dart';
import 'video_player.dart';
import '../control/models/video_session.dart';

final remoteAudioProvider = Provider<RemoteAudio>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final videoSessionsProvider = Provider<VideoSessions>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final videoScreenshotsProvider = Provider<VideoScreenshots>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);

final windowVideoStartProvider =
    Provider<
      Future<VideoSessionView> Function(VideoSessionPlan, VideoPlayerFactory)
    >((ref) => throw StateError('此能力须由启动装配提供。'));
