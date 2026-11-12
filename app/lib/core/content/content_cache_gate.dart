import 'dart:async';

/// 缓存准入、删除与交付账本提交共用的串行入口；网络或播放器等待不持有它。
/// 顺序为此 gate 再到账本队列，禁止反向获取或在 action 中调用再次排队的方法。
final class ContentCacheGate {
  Future<void> _tail = Future<void>.value();
  Future<T> runExclusive<T>(FutureOr<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
