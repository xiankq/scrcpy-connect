import 'dart:async';

/// 跟踪异步核心、原生启动及其单次重试中的用户意图。
/// 停止回执可能早于已分配源 ID 的启动回执。
class MediaIntent {
  MediaIntent(this.deviceId, this.audio);
  final String deviceId;
  final bool audio;
  final ids = <String>{};
  final _stoppedIds = <String>{};
  final _done = Completer<void>();
  bool cancelled = false;
  Future<void> get done => _done.future;
  void bind(String id) {
    ids.add(id);
    if (_stoppedIds.contains(id)) cancelled = true;
  }

  void stop(String id) {
    _stoppedIds.add(id);
    if (ids.contains(id)) cancelled = true;
  }

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}
