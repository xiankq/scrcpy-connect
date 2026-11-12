import 'dart:typed_data';

class VideoPixels {
  const VideoPixels(this.width, this.height, this.rgba);
  final int width, height;
  final Uint8List rgba;
  bool get valid =>
      width > 0 && height > 0 && rgba.length == width * height * 4;
}
