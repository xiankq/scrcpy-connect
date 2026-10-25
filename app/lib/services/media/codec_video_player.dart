import 'package:media_codec/media_codec.dart';

import 'package:scrcpy_connect/services/media/video_player_port.dart';

/// 控制器只通过 Dart 传递源能力和控制信息；Rust 直接向原生 FFmpeg 解码器提交压缩包。
class CodecVideoPlayer implements VideoPlayerPort {
  final _controller = MediaCodecController.video();

  @override
  Stream<VideoJson> get events => _controller.events;

  @override
  Future<VideoTexture> open(VideoJson source) async {
    await _controller.open(MediaCodecSource.fromMap(source));
    await _controller.waitForFrame();
    final texture = _controller.textureId;
    if (texture == null || texture < 0) {
      throw StateError('No native video texture');
    }
    return VideoTexture(texture, _controller.width, _controller.height);
  }

  @override
  Future<void> setPaused(bool paused) async {
    await _controller.setPaused(paused);
    if (!paused) await _controller.waitForFrame();
  }

  @override
  Future<VideoPixels?> snapshot({
    required int width,
    required int height,
  }) async {
    final image = await _controller.snapshot(width: width, height: height);
    return image == null
        ? null
        : VideoPixels(image.width, image.height, image.rgba);
  }

  @override
  Future<VideoJson> release() => _controller.dispose();
}
