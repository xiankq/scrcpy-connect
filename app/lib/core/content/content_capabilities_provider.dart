import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/lifecycle/app_dependencies_provider.dart';

import 'content_cache.dart';
import 'content_preview.dart';

final contentCacheControlProvider = Provider<ContentCacheControl>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.cache)),
);
final contentReaderProvider = Provider<ContentReader>(
  (ref) => ref.watch(appDependenciesProvider.select((app) => app.content)),
);
