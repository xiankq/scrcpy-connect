import 'dart:async';

import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_event.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

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
  final _states = StreamController<Json>.broadcast(sync: true);
  final _events = StreamController<Json>.broadcast(sync: true);
  late final StreamSubscription<Json> _subscription;
  bool disposed = false;
  bool applyingState = false;
  bool _reconciling = false;
  int? _snapshotSequence;

  Stream<Object> get connectionErrors => _connectionErrors.stream;
  Stream<void> get stateCommits => _stateCommits.stream;
  Stream<Json> get stateEvents => _states.stream;
  Stream<Json> get events => _events.stream;

  void _accept(Json event) {
    if (disposed) return;
    final frozen = immutableJson(event);
    final type = event['type'];
    if (event['data'] case RecoveryCompleted(:final snapshot)) {
      if (_snapshotSequence case final previous?
          when snapshot.sequence < previous) {
        return;
      }
      if (!_reconciling && snapshot.sequence == _snapshotSequence) {
        return;
      }
      _snapshotSequence = snapshot.sequence;
      _reconciling = false;
    } else if (event['data'] is RecoveryStarted ||
        event['data'] is RecoveryFailed) {
      _reconciling = true;
    }
    if (type != 'session.frame') {
      applyingState = true;
      try {
        _states.add(frozen);
      } finally {
        applyingState = false;
      }
      _stateCommits.add(null);
    }
    _events.add(frozen);
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
