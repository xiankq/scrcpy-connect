import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'remote_control.dart';
import 'video_display.dart';
import 'video_quality.dart';

final remoteControlProvider = Provider<RemoteControl>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final videoDisplayProvider = Provider<VideoDisplayControl>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final videoQualityControlProvider = Provider<VideoQualityControl>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
