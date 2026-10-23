import 'dart:typed_data';

typedef VideoJson = Map<String, dynamic>;
typedef VideoCoreRequest = Future<VideoJson> Function(
  String command,
  VideoJson params,
);
typedef VideoPlayerFactory = VideoPlayerPort Function();

/// Only operations needed by the session owner. Tests exercise cancellation and
/// late replies through this seam; production uses the native packet decoder.
abstract interface class VideoPlayerPort {
  Stream<VideoJson> get events;

  /// Resolves after decoding and texture allocation. Lazy platform import is
  /// observed separately after Flutter mounts the returned texture.
  Future<VideoTexture> open(VideoJson source);

  /// Synchronously applies output pause. [onRequested] is a compatibility hook
  /// after submission; pausing a decoder does not require restarting capture.
  Future<void> setPaused(bool paused, {Future<void> Function()? onRequested});
  Future<VideoPixels?> snapshot({required int width, required int height});
  Future<VideoJson> release();
}

class VideoTexture {
  const VideoTexture(this.id, this.width, this.height);
  final int id, width, height;
}

class VideoPixels {
  const VideoPixels(this.width, this.height, this.rgba);
  final int width, height;
  final Uint8List rgba;
  bool get valid =>
      width > 0 && height > 0 && rgba.length == width * height * 4;
}
