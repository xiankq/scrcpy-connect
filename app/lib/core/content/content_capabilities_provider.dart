import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'content_cache.dart';
import 'content_preview.dart';

final contentCacheControlProvider = Provider<ContentCacheControl>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
final contentReaderProvider = Provider<ContentReader>(
  (ref) => throw StateError('此能力须由启动装配提供。'),
);
