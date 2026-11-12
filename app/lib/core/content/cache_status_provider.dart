import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:scrcpy_connect/core/application/application_session_provider.dart';

import 'cache_status.dart';

export 'cache_status.dart';

part 'cache_status_provider.g.dart';

/// 同一 scope 共享占用核验；依赖替换或缓存变更使旧回执失效。
@Riverpod(retry: _noRetry)
Future<CacheStatus> cacheStatus(Ref ref) {
  final session = ref.watch(applicationSessionProvider);
  final subscription = session.events.listen((event) {
    if (event['type'] == 'media.cache.changed' ||
        event['type'] == 'state.resynced') {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  return session.dependencies.cache.status();
}

// 存储核验失败由用户或权威变更重新触发，不对不可核验的磁盘状态后台重试。
Duration? _noRetry(int _, Object _) => null;
