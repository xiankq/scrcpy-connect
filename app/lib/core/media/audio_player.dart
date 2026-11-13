import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/media/models/audio_format.dart';

import 'models/audio_player_status.dart';
import 'models/media_output_release.dart';
import 'models/media_player_event.dart';

export 'models/audio_player_status.dart';
export 'models/media_output_release.dart';
export 'models/media_player_event.dart';

/// 远程声音采用 PCM16，本输出无需创建压缩音频解码器。
final class _NativeAudioPlayer implements AudioPlayer {
  final _controller = MediaCodecController.audio();

  @override
  Stream<MediaPlayerEvent> get events => _controller.events
      .map(MediaPlayerEvent.decode)
      .where((event) => event != null)
      .cast<MediaPlayerEvent>();
  @override
  int get positionMs => _controller.positionMs;
  @override
  AudioPlayerStatus get outputStatus =>
      AudioPlayerStatus.fromProtocol(_controller.currentStatus);

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
  Future<MediaOutputRelease> release() async =>
      MediaOutputRelease.fromProtocol(await _controller.dispose());
}

typedef AudioPlayerFactory = AudioPlayer Function();

/// 播放器接口，不负责 PCM 复制或系统焦点策略。
abstract interface class AudioPlayer {
  factory AudioPlayer() = _NativeAudioPlayer;
  Stream<MediaPlayerEvent> get events;
  Future<AudioFormat> open(MediaCodecSource source);
  Future<void> setPaused(bool paused);
  Future<void> volume(double value, bool muted);
  int get positionMs;

  /// 来自系统输出的证据，与收到的源数据包独立。
  AudioPlayerStatus get outputStatus;
  Future<MediaOutputRelease> release();
}
