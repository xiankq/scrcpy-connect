import 'package:media_codec/media_codec.dart';

import 'package:scrcpy_connect/media/output/audio_player_port.dart';

/// 远程声音采用 PCM16，本输出无需创建压缩音频解码器。
class CodecAudioPlayer implements AudioPlayerPort {
  final _controller = MediaCodecController.audio();

  @override
  Stream<AudioJson> get events => _controller.events;
  @override
  int get positionMs => _controller.positionMs;
  @override
  AudioJson get outputStatus => _controller.currentStatus;

  @override
  Future<AudioFormat> open(AudioJson source) async {
    await _controller.open(MediaCodecSource.fromMap(source));
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
