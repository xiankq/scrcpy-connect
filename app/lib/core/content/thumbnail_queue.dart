import 'dart:async';
import 'dart:collection';

import 'package:uuid/uuid.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/content/content_cache_lease.dart';

import 'cached_content.dart';

/// 每台设备在同一传输内共享一个有界解码通道；网格项离开或换源时释放租约。
class ThumbnailQueue {
  ThumbnailQueue({
    required this.load,
    required this.cancel,
    required this.releaseLease,
    required this._keepAlive,
  });
  final Future<CachedContent> Function(String path, String operationId) load;
  final Future<void> Function(String operationId) cancel;
  final CacheLeaseRelease releaseLease;
  final void Function() Function() _keepAlive;
  final _waiting = Queue<ThumbnailLease>();
  ThumbnailLease? _active;
  bool _disposed = false;

  ThumbnailLease acquire(String path) {
    final lease = ThumbnailLease._(this, path);
    if (_disposed || _waiting.length >= 128) {
      lease._result.completeError(
        const RequestFailure('thumbnail_queue_full', '缩略图等待队列已满，请稍后重试。'),
      );
    } else {
      _waiting.add(lease);
      scheduleMicrotask(_pump);
    }
    return lease;
  }

  void _pump() {
    if (_disposed || _active != null || _waiting.isEmpty) return;
    final lease = _waiting.removeFirst();
    _active = lease;
    // 取消期间重开页面仍使用原通道；取消确认不代表原请求结束，只有终态回执释放通道。
    final releaseKeepAlive = _keepAlive();
    unawaited(
      _run(lease).whenComplete(() {
        _active = null;
        releaseKeepAlive();
        _pump();
      }),
    );
  }

  Future<void> _run(ThumbnailLease lease) async {
    for (var attempt = 0; attempt < 3 && !lease._released; attempt++) {
      try {
        lease._operationId = const Uuid().v4();
        final result = await load(lease.path, lease._operationId!);
        final id = result.leaseId;
        if (id != null) lease._cacheLease = ContentCacheLease(releaseLease, id);
        if (lease._released) lease._cacheLease?.release();
        if (!lease._released) lease._result.complete(result);
        return;
      } catch (failure, stack) {
        if (lease._released) return;
        if (failure is RequestFailure &&
            failure.code == 'busy' &&
            attempt < 2) {
          lease._operationId = null;
          final pause = Completer<void>();
          final timer = Timer(Duration(milliseconds: 150 * (attempt + 1)), () {
            pause.complete();
          });
          await Future.any([pause.future, lease._cancelled.future]);
          timer.cancel();
        } else {
          lease._result.completeError(failure, stack);
          return;
        }
      }
    }
  }

  void _release(ThumbnailLease lease) {
    if (lease._released) return;
    lease._released = true;
    lease._cacheLease?.release();
    lease._cancelled.complete();
    _waiting.remove(lease);
    if (_active == lease && lease._operationId != null) {
      unawaited(
        Future.sync(() => cancel(lease._operationId!))
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
    if (!lease._result.isCompleted) {
      lease._result.completeError(
        const RequestFailure('cancelled', '缩略图请求已取消。'),
      );
    }
  }

  void dispose() {
    _disposed = true;
    for (final lease in _waiting.toList()) {
      _release(lease);
    }
    if (_active case final active?) _release(active);
  }
}

class ThumbnailLease {
  ThumbnailLease._(this._owner, this.path);
  final ThumbnailQueue _owner;
  final String path;
  final _result = Completer<CachedContent>();
  final _cancelled = Completer<void>();
  bool _released = false;
  String? _operationId;
  ContentCacheLease? _cacheLease;
  ContentCacheLease? get cacheLease => _cacheLease;
  Future<CachedContent> get result => _result.future;
  void release() => _owner._release(this);
}
