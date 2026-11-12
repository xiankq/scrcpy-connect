import 'dart:async';

import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';

/// Scope 的传输与事件所有者。先同步交付状态，再向页面和查询发布事件。
final class StateSubscription {
  StateSubscription(this.session) : generation = ++_nextGeneration {
    _reconciling = session.initialState.reconciliationPending;
    _snapshotSequence = session.initialState.reconciledSnapshot?.sequence;
    _subscription = session.events.listen(
      _accept,
      onError: _connectionErrors.add,
    );
  }

  static int _nextGeneration = 0;
  final int generation;
  final AppSession session;
  final _connectionErrors = StreamController<Object>.broadcast(sync: true);
  final _stateCommits = StreamController<void>.broadcast(sync: true);
  final _states = StreamController<RuntimeEvent>.broadcast(sync: true);
  final _events = StreamController<RuntimeEvent>.broadcast(sync: true);
  late final StreamSubscription<RuntimeEvent> _subscription;
  bool disposed = false;
  bool applyingState = false;
  bool _reconciling = false;
  int? _snapshotSequence;

  Stream<Object> get connectionErrors => _connectionErrors.stream;
  Stream<void> get stateCommits => _stateCommits.stream;
  Stream<RuntimeEvent> get stateEvents => _states.stream;
  Stream<RuntimeEvent> get events => _events.stream;

  void _accept(RuntimeEvent event) {
    if (disposed) return;
    if (event.data case RecoveryCompleted(:final snapshot)) {
      if (_snapshotSequence case final previous?
          when snapshot.sequence < previous) {
        return;
      }
      if (!_reconciling && snapshot.sequence == _snapshotSequence) {
        return;
      }
      _snapshotSequence = snapshot.sequence;
      _reconciling = false;
    } else if (event.data is RecoveryStarted || event.data is RecoveryFailed) {
      _reconciling = true;
    }
    if (!event.telemetry) {
      applyingState = true;
      try {
        _states.add(event);
      } finally {
        applyingState = false;
      }
      _stateCommits.add(null);
    }
    _events.add(event);
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    unawaited(_subscription.cancel());
    unawaited(_states.close());
    unawaited(_stateCommits.close());
    unawaited(_connectionErrors.close());
    unawaited(_events.close());
    final close = session.close;
    if (close != null) {
      unawaited(
        Future<void>.sync(close).catchError((Object error, StackTrace _) {
          session.diagnostics?.record(
            DiagnosticArea.app,
            'shutdown.failed',
            level: LogLevel.error,
            fields: {'errorType': error.runtimeType.toString()},
          );
        }),
      );
    }
  }
}
