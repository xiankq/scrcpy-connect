import 'package:scrcpy_connect/core/events/models/app_event.dart';
import 'package:scrcpy_connect/core/media/models/device_audio_snapshot.dart';
import 'package:scrcpy_connect/core/media/models/audio_focus.dart';

sealed class AudioOutputEvent extends AppEvent {
  const AudioOutputEvent();
  String get sourceId;
  @override
  String get deviceId;

  @override
  String get type => switch (this) {
    AudioPresentationChanged() => 'audio.presentation',
    AudioOutputFailed() => 'audio.output.failed',
    AudioResumeRequired() => 'audio.resume.required',
  };
}

final class AudioPresentationChanged extends AudioOutputEvent {
  const AudioPresentationChanged(this.receipt);
  final AudioOutputReceipt receipt;

  @override
  String get sourceId => receipt.sourceId;
  @override
  String get deviceId => receipt.deviceId;
}

final class AudioOutputFailed extends AudioOutputEvent {
  const AudioOutputFailed({
    required this.sourceId,
    required this.deviceId,
    required this.code,
    required this.reason,
  });
  @override
  final String sourceId;
  @override
  final String deviceId;
  final String code, reason;
}

final class AudioResumeRequired extends AudioOutputEvent {
  const AudioResumeRequired({
    required this.sourceId,
    required this.deviceId,
    required this.focusSignal,
  });
  @override
  final String sourceId;
  @override
  final String deviceId;
  final AudioFocusSignal focusSignal;
}
