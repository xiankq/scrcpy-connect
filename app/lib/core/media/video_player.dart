import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/media/models/video_pixels.dart';
import 'package:scrcpy_connect/core/media/models/video_texture.dart';

/// 控制器只通过 Dart 传递源能力和控制信息；Rust 直接向原生 FFmpeg 解码器提交压缩包。
final class _NativeVideoPlayer implements VideoPlayer {
  final _controller = MediaCodecController.video();

  @override
  Stream<VideoJson> get events => _controller.events;

  @override
  Future<VideoTexture> open(MediaCodecSource source) async {
    await _controller.open(source);
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

typedef VideoJson = Map<String, dynamic>;
typedef VideoPlayerFactory = VideoPlayer Function();

/// 只提供会话所有者需要的操作；测试通过此接口覆盖取消和迟到回执，生产实现使用原生媒体包解码器。
abstract interface class VideoPlayer {
  factory VideoPlayer() = _NativeVideoPlayer;
  Stream<VideoJson> get events;

  /// 解码并分配纹理后完成；Flutter 挂载纹理后另行观察平台的延迟导入。
  Future<VideoTexture> open(MediaCodecSource source);

  /// 暂停本地输出，不重新启动捕获。
  Future<void> setPaused(bool paused);
  Future<VideoPixels?> snapshot({required int width, required int height});
  Future<VideoJson> release();
}
