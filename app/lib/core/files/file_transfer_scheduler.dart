import 'dart:async';

/// 批次按入队顺序取得执行名额；取消排队不占用名额，运行中的任务自行收尾。
final class FileTransferScheduler {
  FileTransferScheduler({this.concurrency = 2}) {
    if (concurrency < 1) throw ArgumentError.value(concurrency, 'concurrency');
  }

  final int concurrency;
  final _waiting = <String, _ScheduledTransfer>{};
  final _running = <String>{};
  bool _closed = false;
  bool _pumpScheduled = false;

  Future<void> schedule(String batch, Future<void> Function() run) {
    if (_closed) return Future.value();
    if (_waiting.containsKey(batch) || _running.contains(batch)) {
      throw StateError('传输批次已调度。');
    }
    final work = _ScheduledTransfer(run);
    _waiting[batch] = work;
    _schedulePump();
    return work.finished.future;
  }

  void cancelQueued(String batch) =>
      _waiting.remove(batch)?.finished.complete();

  /// 撤销所有等待名额的批次；调用者继续等待原 schedule 回执以排空在途任务。
  void close() {
    _closed = true;
    for (final batch in _waiting.keys.toList()) {
      cancelQueued(batch);
    }
  }

  void _schedulePump() {
    if (_closed || _pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      while (!_closed && _running.length < concurrency && _waiting.isNotEmpty) {
        final batch = _waiting.keys.first;
        final work = _waiting.remove(batch)!;
        _running.add(batch);
        unawaited(_run(batch, work));
      }
    });
  }

  Future<void> _run(String batch, _ScheduledTransfer work) async {
    try {
      await work.run();
      work.finished.complete();
    } catch (error, stack) {
      work.finished.completeError(error, stack);
    } finally {
      _running.remove(batch);
      _schedulePump();
    }
  }
}

final class _ScheduledTransfer {
  _ScheduledTransfer(this.run);
  final Future<void> Function() run;
  final finished = Completer<void>();
}
