import 'dart:async';

import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 合并在途核验；只返回最后一次失效之后的回执，不保存展示状态。
final class CoalescedQuery<T> {
  CoalescedQuery(this._read, {required Stream<Object?> invalidations}) {
    _subscription = invalidations.listen((_) {
      if (_closed) return;
      _dirty = true;
      _changes.add(++_revision);
    }, onError: _changes.addError);
  }

  final Future<T> Function() _read;
  final _changes = StreamController<int>.broadcast(sync: true);
  late final StreamSubscription<Object?> _subscription;
  Future<T>? _pending;
  Future<void>? _closing;
  bool _dirty = false, _closed = false;
  int _revision = 0;

  Stream<int> get changes => _changes.stream;

  Future<T> read() {
    _dirty = true;
    return _pending ??= Future<T>.microtask(_drain);
  }

  Future<T> _drain() async {
    try {
      if (_closed) throw const RequestFailure('disposed', '查询已关闭。');
      while (true) {
        _dirty = false;
        try {
          final result = await _read();
          if (!_closed && _dirty) continue;
          return result;
        } catch (_) {
          if (!_closed && _dirty) continue;
          rethrow;
        }
      }
    } finally {
      _pending = null;
    }
  }

  /// 只释放自己的事件订阅，不取消或关闭借用的能力所有者。
  Future<void> close() {
    _closed = true;
    return _closing ??= _subscription.cancel().whenComplete(_changes.close);
  }
}
