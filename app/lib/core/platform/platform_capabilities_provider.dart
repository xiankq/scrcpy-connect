import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'background_control.dart';
import 'models/app_info.dart';

final backgroundControlProvider = Provider<BackgroundControl>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final appInfoReaderProvider = Provider<Future<AppInfo> Function()>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
