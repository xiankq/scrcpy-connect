import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';

export 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';

abstract interface class RemoteAudio {
  Future<List<DeviceAudioSnapshot>> readAudioSources({String? deviceId});
  Future<Set<String>> readAudioEligibleDevices();
  Future<DeviceAudioPlayback> startAudio(String deviceId);
  Future<void> stopAudio(DeviceAudioTarget target);
  Future<DeviceAudioPlayback> pauseAudio(DeviceAudioTarget target);
  Future<DeviceAudioPlayback> resumeAudio(DeviceAudioTarget target);
  Future<DeviceAudioPlayback> changeAudioVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  });
}
