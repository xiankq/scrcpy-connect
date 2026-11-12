import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'remote_audio.dart';
import 'video_screenshots.dart';
import 'video_sessions.dart';

final remoteAudioProvider = Provider<RemoteAudio>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.remoteAudio)),
);
final videoSessionsProvider = Provider<VideoSessions>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.videos)),
);
final videoScreenshotsProvider = Provider<VideoScreenshots>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.screenshots)),
);
