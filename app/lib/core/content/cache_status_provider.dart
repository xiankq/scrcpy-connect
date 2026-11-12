import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/content/models/cache_status.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';

import 'content_capabilities_provider.dart';

export 'package:scrcpy_connect/core/content/models/cache_status.dart';

part 'cache_status_provider.g.dart';

/// 同一 scope 共享占用核验；依赖替换或缓存变更使旧回执失效。
@Riverpod(retry: _noRetry)
Future<CacheStatus> cacheStatus(Ref ref) {
  final source = ref.watch(contentCacheControlProvider);
  final subscription = ref.watch(runtimeEventsProvider).listen((event) {
    if (event['type'] == 'media.cache.changed' ||
        event['type'] == 'state.resynced') {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  return source.status();
}

// 存储核验失败由用户或权威变更重新触发，不对不可核验的磁盘状态后台重试。
Duration? _noRetry(int _, Object _) => null;
