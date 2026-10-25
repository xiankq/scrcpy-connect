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

/// 登记在途启动意图，按设备或实际源撤销，并等待原启动完成。
class MediaIntentRegistry {
  final active = <MediaIntent>{};
  MediaIntent begin(String deviceId, {required bool audio}) {
    final intent = MediaIntent(deviceId, audio);
    active.add(intent);
    return intent;
  }

  void finish(MediaIntent intent) {
    active.remove(intent);
    intent.complete();
  }

  void stop(String id, {required bool audio}) {
    for (final intent in active.where((i) => i.audio == audio)) {
      intent.stop(id);
    }
  }

  void stopDevice(String device) {
    for (final intent in active.where((i) => i.deviceId == device)) {
      intent.cancelled = true;
    }
  }

  void stopAudioDevice(String device) {
    for (final intent in active.where((i) => i.deviceId == device && i.audio)) {
      intent.cancelled = true;
    }
  }

  void cancelAll() {
    for (final intent in active) {
      intent.cancelled = true;
    }
  }
}
