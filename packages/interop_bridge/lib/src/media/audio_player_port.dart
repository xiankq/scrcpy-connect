typedef AudioJson = Map<String, dynamic>;
typedef AudioRequest = Future<AudioJson> Function(
  String command,
  AudioJson params,
);
typedef AudioPlayerFactory = AudioPlayerPort Function();

/// Public-player seam; no PCM copies or OS focus policy live in this port.
abstract interface class AudioPlayerPort {
  Stream<AudioJson> get events;
  Future<AudioFormat> open(String url);
  Future<void> setPaused(bool paused);
  Future<void> volume(double value, bool muted);
  int get positionMs;
  Future<AudioJson> release();
}

class AudioFormat {
  const AudioFormat(this.codec, this.sampleRate, this.channels);
  final String codec;
  final int sampleRate, channels;
}
