import 'package:media_codec/media_codec.dart';

import 'package:scrcpy_client/scrcpy_client.dart';

/// Remote audio is PCM16, so this output opens no compressed audio decoder.
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
