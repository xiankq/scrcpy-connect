typedef SessionJson = Map<String, dynamic>;
typedef SessionRequest = Future<SessionJson> Function(String, [SessionJson]);

/// A view borrows a persistent control session; it never owns its lifetime.
/// Per-session ordering drains old input before another view resumes capture.
class SessionViews {
  SessionViews(this.request);
  final SessionRequest request;
  final _owners = <String, SessionView>{};
  final _tails = <String, Future<void>>{};
  bool _uncertain = false;

  SessionView claim(String id, {required bool visible}) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final view = SessionView._(this, id, visible);
    _owners[id] = view;
    return view;
  }

  void invalidate() => _owners.clear();

  /// Until a snapshot arrives, old views may only clean up their exact session.
  void markUncertain() {
    _uncertain = true;
    for (final owner in _owners.values) {
      owner._revision++;
    }
  }

  void reconcile(List<SessionJson> sessions) {
    final current = <String, SessionJson>{
      for (final session in sessions)
        if (!['stopped', 'failed', 'error'].contains(session['status']))
          (session['sessionId'] ?? session['id']).toString(): session,
    };
    _uncertain = false;
    _owners.removeWhere((id, _) => !current.containsKey(id));
    for (final entry in _owners.entries) {
      final session = current[entry.key]!;
      entry.value._revision++;
      entry.value._visible =
          session['capturePaused'] != true && session['status'] != 'paused';
    }
  }

  Future<SessionJson> _visibility(
    SessionView view,
    bool visible, {
    Future<void>? afterInput,
    bool release = false,
  }) {
    final revision = view._revision;
    final operation = (_tails[view.id] ?? Future<void>.value()).then((_) async {
      // Drain even a superseded view's releases before its successor resumes.
      await afterInput;
      if (!identical(_owners[view.id], view)) return <String, dynamic>{};
      if ((_uncertain && visible) || (revision != view._revision && !release)) {
        return <String, dynamic>{};
      }
      var succeeded = false;
      try {
        if (!visible && !view._visible && !_uncertain) {
          succeeded = true;
          return <String, dynamic>{};
        }
        // Resume may unfreeze capture before its renderer receipt fails.
        // Treat that partial outcome as live until a pause is acknowledged.
        if (visible) view._visible = true;
        final receipt = await request(
          visible ? 'session.resume' : 'session.pause',
          {'sessionId': view.id},
        );
        if (revision == view._revision && identical(_owners[view.id], view)) {
          view._visible = visible;
        }
        succeeded = true;
        return receipt;
      } finally {
        if (release && succeeded && identical(_owners[view.id], view)) {
          _owners.remove(view.id);
        }
      }
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[view.id] = tail;
    return operation.whenComplete(() {
      if (identical(_tails[view.id], tail)) _tails.remove(view.id);
    });
  }
}

class SessionView {
  SessionView._(this._views, this.id, this._visible);
  final SessionViews _views;
  final String id;
  bool _visible;
  bool _released = false;
  int _revision = 0;
  bool get isCurrent => !_released && identical(_views._owners[id], this);

  /// Revoke only this local binding after its transport/session has ended.
  /// Unlike release, this cannot pause a removed session or retain its owner
  /// after a failed remote cleanup. Queued old visibility work loses admission.
  void abandonEndedSession() {
    _released = true;
    _revision++;
    if (identical(_views._owners[id], this)) _views._owners.remove(id);
  }

  Future<SessionJson> resume({Future<void>? afterInput}) => _released
      ? Future.value({})
      : _views._visibility(this, true, afterInput: afterInput);
  Future<SessionJson> pause({Future<void>? afterInput}) => _released
      ? Future.value({})
      : _views._visibility(this, false, afterInput: afterInput);
  Future<SessionJson> release({Future<void>? afterInput}) {
    if (_released) return Future.value({});
    _released = true;
    return _views
        ._visibility(this, false, afterInput: afterInput, release: true)
        .catchError((Object error, StackTrace stack) {
          _released = false;
          Error.throwWithStackTrace(error, stack);
        });
  }
}
