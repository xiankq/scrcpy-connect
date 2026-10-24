import 'dart:math' as math;
import 'dart:ui';

/// 仅映射画面内部的指针坐标，排除留黑区域与主控操作栏。
Offset? sourcePoint(
  Offset local,
  Size viewport,
  Size source, {
  bool clamp = false,
}) {
  if (source.isEmpty || viewport.isEmpty) return null;
  final scale = math.min(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  final origin = Offset(
    (viewport.width - source.width * scale) / 2,
    (viewport.height - source.height * scale) / 2,
  );
  final point = (local - origin) / scale;
  if (clamp) {
    return Offset(
      point.dx.clamp(0, source.width - 1),
      point.dy.clamp(0, source.height - 1),
    );
  }
  if (point.dx < 0 ||
      point.dy < 0 ||
      point.dx >= source.width ||
      point.dy >= source.height) {
    return null;
  }
  return point;
}
