import 'dart:ui' as ui;

// Match the independent fixture's four bit color oracle. Ratios tolerate video
// range conversion; arbitrary nonempty/black/changed pixels cannot pass.
int? pixelPattern(List<int> rgba, int width, int height, {ui.Rect? region}) {
  final bounds =
      region ?? ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  if (width <= 0 ||
      height <= 0 ||
      rgba.length != width * height * 4 ||
      bounds.left < 0 ||
      bounds.top < 0 ||
      bounds.right > width ||
      bounds.bottom > height ||
      bounds.isEmpty) {
    return null;
  }
  var counter = 0;
  for (var bit = 0; bit < 4; bit++) {
    final x = (bounds.left + bounds.width * (bit + .5) / 4).floor();
    final offset = (bounds.center.dy.floor() * width + x) * 4;
    final r = rgba[offset], g = rgba[offset + 1], b = rgba[offset + 2];
    if (r > 30 && r > g * 1.5 && r > b * 1.5) {
      counter |= 1 << bit;
    } else if (!(b > 60 && b > r * 1.5 && g > r * 1.5)) {
      return null;
    }
  }
  return counter;
}
