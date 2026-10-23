import 'dart:async';

import 'package:device_protocol/device_protocol.dart';

/// Keeps renderer reads and playback changes from overlapping. Closing prevents
/// further work and drains native completions before texture/player retirement.
final class VideoPlayerOperations {
  Future<void> _idle = Future<void>.value();
  bool _closed = false;
  int _pending = 0;

  Future<T> run<T>(Future<T> Function() action) {
    if (_closed) return Future<T>.error(_cancelled());
    if (_pending >= 8) {
      return Future<T>.error(
        const InteropException('renderer_busy', '画面操作仍在处理中，请稍后重试。'),
      );
    }
    _pending++;
    final operation = _idle.then((_) {
      if (_closed) throw _cancelled();
      return action();
    });
    // A failed read must reach its caller without poisoning later changes or
    // close. This tail follows actual completion, never a caller's timeout.
    _idle = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation.whenComplete(() => _pending--);
  }

  Future<void> close() {
    _closed = true;
    return _idle;
  }

  InteropException _cancelled() =>
      const InteropException('cancelled', '此视频输出已关闭。');
}
