import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';

final class DeviceAudioChanged extends AppEvent {
  const DeviceAudioChanged(this.snapshot);
  final DeviceAudioSnapshot snapshot;

  @override
  String get deviceId => snapshot.deviceId;
  @override
  String get type => 'audio.updated';
}
