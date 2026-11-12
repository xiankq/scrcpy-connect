import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/media/models/audio_format.dart';

/// 远程声音采用 PCM16，本输出无需创建压缩音频解码器。
final class _NativeAudioPlayer implements AudioPlayer {
  final _controller = MediaCodecController.audio();

  @override
  Stream<AudioJson> get events => _controller.events;
  @override
  int get positionMs => _controller.positionMs;
  @override
  AudioJson get outputStatus => _controller.currentStatus;

  @override
  Future<AudioFormat> open(MediaCodecSource source) async {
    await _controller.open(source);
    return const AudioFormat('pcm_s16le', 48000, 2);
  }

  @override
  Future<void> setPaused(bool paused) => _controller.setPaused(paused);
  @override
  Future<void> volume(double value, bool muted) =>
      _controller.setVolume(value, muted: muted);
  @override
  Future<AudioJson> release() => _controller.dispose();
}

typedef AudioJson = Map<String, dynamic>;
typedef AudioPlatformRequest = Future<AudioJson> Function(
  String command,
  AudioJson params,
);
typedef AudioPlayerFactory = AudioPlayer Function();

/// 播放器接口，不负责 PCM 复制或系统焦点策略。
abstract interface class AudioPlayer {
  factory AudioPlayer() = _NativeAudioPlayer;
  Stream<AudioJson> get events;
  Future<AudioFormat> open(MediaCodecSource source);
  Future<void> setPaused(bool paused);
  Future<void> volume(double value, bool muted);
  int get positionMs;

  /// 来自系统输出的证据，与收到的源数据包独立。
  AudioJson get outputStatus;
  Future<AudioJson> release();
}
