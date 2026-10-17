import 'dart:async';

import 'interop_exception.dart';

typedef StateJson = Map<String, dynamic>;

/// Exact UP/CANCEL is cleanup of an existing input lease, not a replay of its
/// action. Stops and other cleanup remain available while state is unknown.
bool needsVerifiedState(String command, StateJson params) {
  if (command == 'session.key' || command == 'session.touch') {
    final exact =
        params['sessionId'] is String &&
        (params['sessionId'] as String).isNotEmpty;
    return !(exact &&
        (params['action'] == 'up' ||
            (command == 'session.touch' && params['action'] == 'cancel')));
  }
  return const {
    'session.start',
    'session.resume',
    'session.text',
    'session.screen',
    'session.rotate',
    'session.launch',
    'apps.launch',
    'audio.start',
    'audio.resume',
    'observation.start',
    'notifications.open',
    'notifications.reply',
    'notifications.dismiss',
    'calls.action',
    'clipboard.get',
    'clipboard.set',
  }.contains(command);
}

/// Replaces event-derived projections after a transport gap. Snapshots carry
/// the core publication watermark; older queued events can never undo them.
class StateRecovery {
  StateRecovery({
    required this.read,
    required this.emit,
    required this.isDisposed,
    this.timeout = const Duration(seconds: 12),
  });

  final Future<StateJson> Function(bool Function() current) read;
  final void Function(StateJson event) emit;
  final bool Function() isDisposed;
  final Duration timeout;
  Future<StateJson>? _running;
  int _epoch = 0, _watermark = -1, _observed = -1, _gaps = 0;
  bool _pending = false, _disposed = false;

  bool get pending => _pending;
  bool get hasSnapshot => _watermark >= 0;

  /// Returns true only when the ordinary event is safe to forward.
  bool accept(StateJson event) {
    if (_disposed || isDisposed()) return false;
    final type = event['type'];
    if (type == 'runtime.heartbeat') return false;
    if (type == 'state.resync') {
      _gaps++;
      unawaited(
        refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return false;
    }
    final sequence = event['sequence'];
    if (sequence is! int || sequence < 0) {
      // A missing fence is a protocol gap, never permission to apply old data.
      _gaps++;
      unawaited(
        refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return false;
    }
    if (type != 'session.frame' && sequence > _observed) _observed = sequence;
    return !_pending && sequence > _watermark;
  }

  Future<StateJson> refresh() {
    if (_disposed || isDisposed()) {
      return Future.error(const InteropException('cancelled', '状态恢复已结束。'));
    }
    if (_running case final existing?) return existing;
    _pending = true;
    final epoch = ++_epoch;
    final result = Completer<StateJson>();
    _running = result.future;
    // Store the operation before emitting: a synchronous listener may retry.
    emit({'type': 'state.resync', 'data': <String, dynamic>{}});
    unawaited(_recover(epoch, result));
    return result.future;
  }

  Future<void> _recover(int epoch, Completer<StateJson> result) async {
    bool current() => !_disposed && !isDisposed() && _epoch == epoch;
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final gaps = _gaps;
        final snapshot = await read(current).timeout(timeout);
        if (!current()) throw const InteropException('cancelled', '状态恢复已结束。');
        final sequence = validateStateSnapshot(snapshot);
        if (sequence < _watermark) {
          throw const InteropException('invalid_snapshot', '状态快照版本已过期。');
        }
        if (gaps != _gaps || sequence < _observed) continue;
        _watermark = sequence;
        _pending = false;
        _running = null;
        // Listeners may now resume a still-owned visible presentation. They
        // cannot authorize it while reconciliation is pending.
        emit({'type': 'state.resynced', 'data': snapshot});
        result.complete(snapshot);
        return;
      }
      throw const InteropException('state_busy', '状态持续变化，尚未完成核验，请重试。');
    } catch (error, stack) {
      if (current()) {
        // Invalidate a timed-out read before it can release any late owners.
        _epoch++;
        _running = null;
        emit({
          'type': 'state.resync.failed',
          'data': {'reason': '$error'},
        });
      }
      result.completeError(error, stack);
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
  }
}

/// Validates the wire envelope before any ownership cleanup is authorized.
int validateStateSnapshot(StateJson snapshot) {
  final sequence = snapshot['sequence'];
  if (sequence is! int || sequence < 0 || snapshot['settings'] is! Map) {
    throw const InteropException('invalid_snapshot', '状态快照缺少版本或设置。');
  }
  for (final key in const [
    'devices',
    'sessions',
    'sources',
    'transfers',
    'activities',
    'shares',
    'companions',
  ]) {
    if (snapshot[key] is! List) {
      throw InteropException('invalid_snapshot', '状态快照缺少$key。');
    }
  }
  return sequence;
}
