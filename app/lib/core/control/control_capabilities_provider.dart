import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'remote_control.dart';
import 'video_display.dart';
import 'video_quality.dart';

final remoteControlProvider = Provider<RemoteControl>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.control)),
);
final videoDisplayProvider = Provider<VideoDisplayControl>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.displays)),
);
final videoQualityControlProvider = Provider<VideoQualityControl>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.videoQuality)),
);
