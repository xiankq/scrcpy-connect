import 'package:scrcpy_connect/models/media_intent.dart';

/// 登记在途启动意图，按设备或实际源撤销，并等待原启动完成。
class MediaIntentStore {
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
