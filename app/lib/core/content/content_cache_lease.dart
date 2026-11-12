import 'package:scrcpy_connect/core/application/request_failure.dart'
    show RequestFailure;

import 'dart:async';

typedef CacheLeaseRelease = Future<void> Function(String leaseId);

/// 一个核心租约可由页面和异步本机消费者共享，所有消费者关闭后文件才能回收。
class ContentCacheLease {
  ContentCacheLease(this.releaseLease, this.id);
  final CacheLeaseRelease releaseLease;
  final String id;
  int _references = 1;
  bool _ownerReleased = false;

  void Function() hold() {
    if (_references == 0) throw StateError('The cache lease has ended.');
    _references++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _releaseReference();
    };
  }

  void release() {
    if (_ownerReleased) return;
    _ownerReleased = true;
    _releaseReference();
  }

  void _releaseReference() {
    if (--_references != 0) return;
    unawaited(
      Future.sync(() => releaseLease(id)).then<void>(
        (_) {},
        // 释放失败时保守保留核心保护，不删除文件或改为释放其他令牌。
        onError: (Object _, StackTrace _) {},
      ),
    );
  }
}

/// 即使页面已离开，仍拥有请求并负责回收迟到回执携带的租约。
class ContentCacheRequest<T> {
  ContentCacheRequest(this.load, this.releaseLease, {required this.leaseId});
  final Future<T> Function() load;
  final String? Function(T) leaseId;
  final CacheLeaseRelease releaseLease;
  bool _disposed = false;
  ContentCacheLease? lease;
  late final Future<T> result = _load();

  Future<T> _load() async {
    final data = await load();
    final id = leaseId(data);
    if (id != null && id.isNotEmpty) {
      lease = ContentCacheLease(releaseLease, id);
    }
    if (_disposed) {
      lease?.release();
      throw const RequestFailure('cancelled', '已离开本次内容。');
    }
    return data;
  }

  void dispose() {
    _disposed = true;
    lease?.release();
  }
}
