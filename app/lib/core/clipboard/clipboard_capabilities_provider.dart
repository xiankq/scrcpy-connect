import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'remote_clipboard.dart';

final remoteClipboardProvider = Provider<RemoteClipboard>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.clipboard)),
);
