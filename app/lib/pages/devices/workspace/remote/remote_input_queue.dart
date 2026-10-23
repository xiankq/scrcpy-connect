import 'dart:async';
import 'dart:collection';

import 'package:scrcpy_connect/services/app_controller.dart';

import 'remote_presentation.dart';

typedef RemoteInputDispatch = Future<void> Function(
  String command,
  Json params,
  RemoteBinding binding,
);
typedef RemoteInputAdmission = bool Function(
  String command,
  Json params,
  RemoteBinding binding,
);

/// Serializes remote input while retaining only the newest pending move for
/// each pointer. Edge events remain ordered and are never coalesced.
final class RemoteInputQueue {
  RemoteInputQueue({
    required this.dispatch,
    required this.admits,
    this.capacity = 256,
  });

  final RemoteInputDispatch dispatch;
  final RemoteInputAdmission admits;
  final int capacity;
  final _pending = LinkedList<_PendingInput>();
  final _moves = <String, _PendingInput>{};
  Completer<void>? _idle;
  bool _pumping = false;
  bool _closed = false;

  /// Completes after every input accepted before the getter call has either
  /// been dispatched or rejected by the current presentation binding.
  Future<void> get idle {
    if (!_pumping && _pending.isEmpty) return Future<void>.value();
    return (_idle ??= Completer<void>()).future;
  }

  Future<void> enqueue(String command, Json params, RemoteBinding binding) {
    if (_closed) return Future<void>.value();
    final pointerKey = _pointerKey(command, params, binding);
    final moveKey = const ['move', 'hover'].contains(params['action'])
        ? pointerKey
        : null;
    if (moveKey != null) {
      final pending = _moves[moveKey];
      if (pending != null && pending.pending) {
        pending.unlink();
        pending.params = params;
        _pending.add(pending);
        // Every superseded move shares this one completion. Slow writes must
        // not allocate one retained waiter for each physical pointer event.
        return pending.waiter.future;
      }
    } else if (pointerKey != null) {
      // A later down/up/cancel belongs after every move for this pointer.
      // Prevent a following move from being merged across that edge.
      _moves.remove(pointerKey);
    }

    final cleanup =
        (command == InteropCommand.sessionKey.wire &&
            params['action'] == 'up') ||
        (command == InteropCommand.sessionTouch.wire &&
            const ['up', 'cancel'].contains(params['action']));
    // Reserve half of the bounded queue for releases. A saturated stream of
    // text/down events must not prevent releasing already-held physical keys
    // and pointers when the page revokes further admission.
    final limit = cleanup || capacity < 16 ? capacity : capacity ~/ 2;
    if (_pending.length >= limit) {
      return Future<void>.error(StateError('控制输入队列繁忙，请等待网络恢复。'));
    }
    final waiter = Completer<void>();
    final entry = _PendingInput(command, params, binding, moveKey, waiter);
    _pending.add(entry);
    if (moveKey != null) _moves[moveKey] = entry;
    _pump();
    return waiter.future;
  }

  /// Stops accepting new commands. Pending inputs are settled locally without
  /// replay; an in-flight dispatch is allowed to finish.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final entry in List<_PendingInput>.of(_pending)) {
      entry.pending = false;
      entry.complete();
    }
    _pending.clear();
    _moves.clear();
    _completeIdleIfNeeded();
  }

  void _pump() {
    if (_pumping || _pending.isEmpty || _closed) return;
    _pumping = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty && !_closed) {
        final entry = _pending.first;
        entry.unlink();
        entry.pending = false;
        final moveKey = entry.moveKey;
        if (moveKey != null && identical(_moves[moveKey], entry)) {
          _moves.remove(moveKey);
        }

        var accepted = false;
        try {
          accepted = admits(entry.command, entry.params, entry.binding);
        } catch (error, stack) {
          entry.complete(error, stack);
          continue;
        }
        if (accepted) {
          try {
            await dispatch(entry.command, entry.params, entry.binding);
          } catch (error, stack) {
            entry.complete(error, stack);
            continue;
          }
        }
        entry.complete();
      }
    } finally {
      _pumping = false;
      if (_pending.isNotEmpty && !_closed) {
        _pump();
      } else {
        _completeIdleIfNeeded();
      }
    }
  }

  void _completeIdleIfNeeded() {
    if (_pumping || _pending.isNotEmpty) return;
    final idle = _idle;
    _idle = null;
    if (idle != null && !idle.isCompleted) idle.complete();
  }

  String? _pointerKey(String command, Json params, RemoteBinding binding) {
    if (command != InteropCommand.sessionTouch.wire) return null;
    final pointer = params['pointerId'];
    if (pointer is! int) return null;
    return '${binding.$1}\u0000${binding.$2}\u0000$pointer';
  }
}

final class _PendingInput extends LinkedListEntry<_PendingInput> {
  _PendingInput(
    this.command,
    this.params,
    this.binding,
    this.moveKey,
    this.waiter,
  );

  final String command;
  Json params;
  final RemoteBinding binding;
  final String? moveKey;
  final Completer<void> waiter;
  bool pending = true;

  void complete([Object? error, StackTrace? stack]) {
    if (waiter.isCompleted) return;
    if (error == null) {
      waiter.complete();
    } else {
      waiter.completeError(error, stack);
    }
  }
}
