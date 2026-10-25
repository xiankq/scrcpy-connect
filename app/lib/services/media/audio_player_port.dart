typedef AudioJson = Map<String, dynamic>;
typedef AudioRequest = Future<AudioJson> Function(
  String command,
  AudioJson params,
);
typedef AudioPlayerFactory = AudioPlayerPort Function();

/// 播放器接口，不负责 PCM 复制或系统焦点策略。
abstract interface class AudioPlayerPort {
  Stream<AudioJson> get events;
  Future<AudioFormat> open(AudioJson source);
  Future<void> setPaused(bool paused);
  Future<void> volume(double value, bool muted);
  int get positionMs;

  /// 来自系统输出的证据，与收到的源数据包独立。
  AudioJson get outputStatus;
  Future<AudioJson> release();
}

class AudioFormat {
  const AudioFormat(this.codec, this.sampleRate, this.channels);
  final String codec;
  final int sampleRate, channels;
}
