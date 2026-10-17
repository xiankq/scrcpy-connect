typedef SessionJson = Map<String, dynamic>;
typedef SessionRequest = Future<SessionJson> Function(String, [SessionJson]);

/// A view borrows a persistent control session; it never owns its lifetime.
/// Per-session ordering drains old input before another view resumes capture.
class SessionViews {
  SessionViews(this.request);
  final SessionRequest request;
  final _owners = <String, SessionView>{};
  final _tails = <String, Future<void>>{};

  SessionView claim(String id, {required bool visible}) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id');
    final view = SessionView._(this, id, visible);
    _owners[id] = view;
    return view;
  }

  void invalidate() => _owners.clear();

  Future<SessionJson> _visibility(
    SessionView view,
    bool visible, {
    Future<void>? afterInput,
    bool release = false,
  }) {
    final operation = (_tails[view.id] ?? Future<void>.value()).then((_) async {
      // Drain even a superseded view's releases before its successor resumes.
      await afterInput;
      if (!identical(_owners[view.id], view)) return <String, dynamic>{};
      var succeeded = false;
      try {
        if (!visible && !view._visible) {
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
        view._visible = visible;
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
  bool get isCurrent => !_released && identical(_views._owners[id], this);

  Future<SessionJson> resume() =>
      _released ? Future.value({}) : _views._visibility(this, true);
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
