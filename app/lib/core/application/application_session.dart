import 'dart:async';

import 'app_dependencies.dart';
import 'request_failure.dart';

import 'package:scrcpy_connect/core/diagnostics/diagnostic_record.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

/// Scope 的传输与事件所有者。先同步交付状态，再向页面和查询发布事件。
final class ApplicationSession {
  ApplicationSession(this.dependencies) : generation = ++_nextGeneration {
    _reconciling = dependencies.initialState.reconciliationPending;
    _snapshotSequence =
        dependencies.initialState.reconciledSnapshot?['sequence'];
    _subscription = dependencies.events.listen(
      _accept,
      onError: _connectionErrors.add,
    );
  }

  static int _nextGeneration = 0;
  final int generation;
  final AppDependencies dependencies;
  final _connectionErrors = StreamController<Object>.broadcast(sync: true);
  final _stateCommits = StreamController<void>.broadcast(sync: true);
  final _states = StreamController<Json>.broadcast(sync: true);
  final _events = StreamController<Json>.broadcast(sync: true);
  late final StreamSubscription<Json> _subscription;
  final _appOpenClaims = <(String, String), Object>{};
  ({String device, String session})? _clipboardFocus;
  bool disposed = false;
  bool applyingState = false;
  bool _reconciling = false;
  Object? _snapshotSequence;

  Stream<Object> get connectionErrors => _connectionErrors.stream;
  Stream<void> get stateCommits => _stateCommits.stream;
  Stream<Json> get stateEvents => _states.stream;
  Stream<Json> get events => _events.stream;

  void _accept(Json event) {
    if (disposed) return;
    final frozen = immutableJson(event);
    final type = event['type'];
    final data = jsonObject(event['data']);
    if (type == 'state.resynced') {
      if (!_reconciling &&
          data['sequence'] != null &&
          data['sequence'] == _snapshotSequence) {
        return;
      }
      _snapshotSequence = data['sequence'];
      _reconciling = false;
    } else if (type == 'state.resync' || type == 'state.resync.failed') {
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

  String? clipboardSessionFor(String device) =>
      _clipboardFocus?.device == device ? _clipboardFocus?.session : null;

  void focusClipboardSession(String device, String session, bool focused) {
    final current = _clipboardFocus;
    final next = focused
        ? (device: device, session: session)
        : current?.device == device && current?.session == session
        ? null
        : current;
    if (disposed || next == current) return;
    _clipboardFocus = next;
    scheduleMicrotask(() {
      if (!disposed) _events.add({'type': 'clipboard.focus'});
    });
  }

  void Function()? claimAppOpen(String device, String package) {
    if (disposed) return null;
    final key = (device, package);
    if (_appOpenClaims.containsKey(key)) return null;
    final token = Object();
    _appOpenClaims[key] = token;
    return () {
      if (identical(_appOpenClaims[key], token)) _appOpenClaims.remove(key);
    };
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    _clipboardFocus = null;
    _appOpenClaims.clear();
    unawaited(_subscription.cancel());
    unawaited(_states.close());
    unawaited(_stateCommits.close());
    unawaited(_connectionErrors.close());
    unawaited(_events.close());
    final close = dependencies.close;
    if (close != null) {
      unawaited(
        Future<void>.sync(close).catchError((Object error, StackTrace _) {
          dependencies.diagnostics?.record(
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
