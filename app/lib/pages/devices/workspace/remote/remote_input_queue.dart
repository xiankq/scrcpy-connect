import 'dart:async';

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
  RemoteInputQueue({required this.dispatch, required this.admits});

  final RemoteInputDispatch dispatch;
  final RemoteInputAdmission admits;
  final _pending = <_PendingInput>[];
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
    final moveKey = params['action'] == 'move' ? pointerKey : null;
    if (moveKey != null) {
      final pending = _moves[moveKey];
      if (pending != null && pending.pending) {
        final waiter = Completer<void>();
        _pending.remove(pending);
        pending.params = params;
        pending.waiters.add(waiter);
        _pending.add(pending);
        return waiter.future;
      }
    } else if (pointerKey != null) {
      // A later down/up/cancel belongs after every move for this pointer.
      // Prevent a following move from being merged across that edge.
      _moves.remove(pointerKey);
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
        final entry = _pending.removeAt(0);
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

final class _PendingInput {
  _PendingInput(
    this.command,
    this.params,
    this.binding,
    this.moveKey,
    Completer<void> waiter,
  ) : waiters = [waiter];

  final String command;
  Json params;
  final RemoteBinding binding;
  final String? moveKey;
  final List<Completer<void>> waiters;
  bool pending = true;

  void complete([Object? error, StackTrace? stack]) {
    for (final waiter in waiters) {
      if (waiter.isCompleted) continue;
      if (error == null) {
        waiter.complete();
      } else {
        waiter.completeError(error, stack);
      }
    }
  }
}
