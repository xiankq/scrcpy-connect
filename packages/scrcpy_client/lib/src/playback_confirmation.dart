import 'dart:async';

import 'package:device_protocol/device_protocol.dart';

/// Confirms requested native states without trusting asynchronously delivered
/// callbacks. Closing drains every waiter before its owner deletes the handle.
class PlaybackConfirmation<T> {
  PlaybackConfirmation({
    required this._changes,
    required this._request,
    required this._query,
    this._timeout = const Duration(seconds: 4),
    this._interval = const Duration(milliseconds: 20),
  });

  final Stream<T> _changes;
  final void Function(T) _request;
  final bool Function(T) _query;
  final Duration _timeout, _interval;
  final _waiters = <Completer<void>>{};
  final _operations = <Future<PlaybackReceipt>>{};
  bool _closed = false;

  Future<PlaybackReceipt> set(
    T target, {
    Future<void> Function()? onRequested,
  }) {
    if (_closed) return Future.error(_cancelled());
    final operation = _set(target, onRequested);
    _operations.add(operation);
    unawaited(
      operation.then<void>(
        (_) => _operations.remove(operation),
        onError: (Object _, StackTrace _) => _operations.remove(operation),
      ),
    );
    return operation;
  }

  Future<PlaybackReceipt> _set(
    T target,
    Future<void> Function()? onRequested,
  ) async {
    final done = Completer<void>();
    _waiters.add(done);
    var queries = 0, maxQueryMs = 0;
    void check() {
      if (_closed || done.isCompleted) return;
      try {
        final watch = Stopwatch()..start();
        final confirmed = _query(target);
        queries++;
        if (watch.elapsedMilliseconds > maxQueryMs) {
          maxQueryMs = watch.elapsedMilliseconds;
        }
        if (confirmed) done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }

    // A delayed callback for an earlier request is only a prompt to query the
    // actual current state; it cannot acknowledge this request on its own.
    final subscription = _changes.listen((_) => check());
    final timer = Timer.periodic(_interval, (_) => check());
    try {
      _request(target);
      check();
      // Only a successfully submitted native request may refresh its source.
      // Drain both waits on failure; a failed refresh must not leave queries
      // touching the handle after its caller retires the player.
      await Future.wait<void>([
        done.future.timeout(_timeout),
        if (onRequested != null) Future<void>.sync(onRequested),
      ]);
      if (_closed) throw _cancelled();
      return PlaybackReceipt(queries, maxQueryMs);
    } finally {
      timer.cancel();
      _waiters.remove(done);
      await subscription.cancel();
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final waiter in _waiters.toList()) {
      if (!waiter.isCompleted) waiter.completeError(_cancelled());
    }
    await Future.wait(
      _operations.toList().map(
        (operation) =>
            operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
  }

  InteropException _cancelled() =>
      const InteropException('cancelled', '此媒体输出已关闭。');
}

class PlaybackReceipt {
  const PlaybackReceipt(this.queries, this.maxQueryMs);
  final int queries, maxQueryMs;
}
