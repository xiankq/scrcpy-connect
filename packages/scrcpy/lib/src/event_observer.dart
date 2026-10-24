import 'dart:async';

import 'models.dart';

/// 单个原生观察者的精确关闭权；流暂停时最多保留一个已读取事件。
/// 取消订阅会调用 close；失败后调用方仍须持有本对象并重试 close。
final class ScrcpyEventObserver {
  ScrcpyEventObserver({
    required this._open,
    required this._next,
    required this._cancel,
  }) {
    _controller = StreamController<ScrcpyEvent>(
      onListen: () {
        if (_cancelled) {
          _finishStream();
        } else {
          unawaited(_pump());
        }
      },
      onPause: () => _resuming ??= Completer<void>(),
      onResume: _resume,
      onCancel: () => _streamEnding ? null : close(),
    );
  }
  final Future<String> Function() _open;
  final Future<ScrcpyEvent?> Function(String) _next;
  final Future<void> Function(String) _cancel;
  late final StreamController<ScrcpyEvent> _controller;
  final _closed = Completer<void>();
  Future<String>? _opening;
  Future<void>? _closing;
  Completer<void>? _resuming;
  bool _cancelled = false, _streamEnding = false;

  void _finishStream() {
    if (_streamEnding) return;
    _streamEnding = true;
    unawaited(_controller.close());
  }

  Stream<ScrcpyEvent> get stream => _controller.stream;

  /// 仅实际释放确认后完成；关闭失败不会触发此回执或撤销所有者登记。
  Future<void> get whenClosed => _closed.future;

  void _resume() {
    final resuming = _resuming;
    _resuming = null;
    resuming?.complete();
  }

  Future<void> _pump() async {
    try {
      final id = await (_opening = Future<String>.sync(_open));
      while (!_cancelled) {
        await _resuming?.future;
        if (_cancelled) break;
        final event = await _next(id);
        if (_cancelled) break;
        if (event == null) {
          throw const ScrcpyException('result_unknown', '观察流缺少捕获停止终态。');
        }
        await _resuming?.future;
        if (_cancelled) break;
        _controller.add(event);
        if (event is ScrcpyStopped) break;
      }
    } catch (error, stack) {
      if (!_cancelled) _controller.addError(error, stack);
    } finally {
      final wasCancelled = _cancelled;
      try {
        await close();
      } catch (error, stack) {
        if (!wasCancelled) _controller.addError(error, stack);
      }
      _finishStream();
    }
  }

  /// 同步撤准入，等待迟到登记并精确取消；失败保留同一 ID，可再次调用。
  /// 暂停的消费者不会阻塞原生观察者释放，本方法不停止捕获。
  Future<void> close() {
    _cancelled = true;
    _resume();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      final opening = _opening;
      if (opening != null) {
        String? id;
        try {
          id = await opening;
        } catch (_) {
          // 登记失败没有交付原生观察者；原始失败仍由事件流报告。
        }
        if (id != null) await _cancel(id);
      }
      if (!_closed.isCompleted) _closed.complete();
      _finishStream();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}
