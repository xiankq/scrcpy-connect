import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'background_control.dart';
import 'models/app_info.dart';

final backgroundControlProvider = Provider<BackgroundControl>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.background)),
);
final appInfoReaderProvider = Provider<Future<AppInfo> Function()>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.appInfo)),
);
