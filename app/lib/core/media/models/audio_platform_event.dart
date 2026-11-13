import 'package:scrcpy_connect/core/media/models/audio_focus.dart';

sealed class AudioPlatformEvent {
  const AudioPlatformEvent();
}

final class AudioVisibilityChanged extends AudioPlatformEvent {
  const AudioVisibilityChanged(this.visible);
  final bool visible;
}

final class AudioBackgroundChanged extends AudioPlatformEvent {
  const AudioBackgroundChanged({required this.ownerId, required this.ready});
  final String ownerId;
  final bool ready;
}

final class AudioFocusChanged extends AudioPlatformEvent {
  const AudioFocusChanged({required this.epoch, required this.signal});
  final int epoch;
  final AudioFocusSignal signal;
}
