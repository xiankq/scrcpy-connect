import 'dart:typed_data';

class VideoPixels {
  VideoPixels(this.width, this.height, Uint8List rgba)
    : rgba = Uint8List.fromList(rgba).asUnmodifiableView();
  final int width, height;
  final Uint8List rgba;
  bool get valid =>
      width > 0 && height > 0 && rgba.length == width * height * 4;
}
