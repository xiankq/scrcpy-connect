import 'dart:typed_data';

typedef VideoJson = Map<String, dynamic>;
typedef VideoCoreRequest = Future<VideoJson> Function(
  String command,
  VideoJson params,
);
typedef VideoPlayerFactory = VideoPlayerPort Function();

/// Only operations needed by the session owner. Tests exercise cancellation and
/// late replies through this seam; production always constructs the MDK port.
abstract interface class VideoPlayerPort {
  Stream<VideoJson> get events;
  Future<VideoTexture> open(String url);
  Future<void> setPaused(bool paused);
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
