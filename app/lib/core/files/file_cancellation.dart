import 'package:scrcpy_connect/core/files/file_failure.dart';

import 'dart:async';

class FileCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  /// 监听持续到取消或返回的移除函数被调用。
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    void registered() => listener();
    _listeners.add(registered);
    return () => _listeners.remove(registered);
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void check() {
    if (isCancelled) throw const FileFailure('cancelled', '文件任务已取消。');
  }
}
