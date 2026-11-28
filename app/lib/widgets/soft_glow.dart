import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 模拟 Ardot「图层模糊」椭圆光斑的静态径向渐变。
///
/// 光斑铺满自身尺寸：中心区为 [color]，向外在 [blur] 范围内渐隐到透明。
/// 只画一次渐变，不做逐帧模糊；放在 [RepaintBoundary] 内时与相邻动画互不重绘。
class SoftGlow extends StatelessWidget {
  const SoftGlow({super.key, required this.color, required this.blur});

  final Color color;

  /// 设计稿 LAYER_BLUR 半径，决定渐隐带的宽度。
  final double blur;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _SoftGlowPainter(color: color, blur: blur),
      child: const SizedBox.expand(),
    ),
  );
}

class _SoftGlowPainter extends CustomPainter {
  const _SoftGlowPainter({required this.color, required this.blur});

  final Color color;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = math.min(size.width, size.height) / 2;
    // 实心段：模糊前椭圆的内缘；其余为近似高斯的三段衰减。
    final solid = ((radius - blur) / radius).clamp(0.0, .6);
    final transparent = color.withValues(alpha: 0);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(size.width / 2, size.height / 2)
      ..drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color,
              color,
              color.withValues(alpha: color.a * .45),
              transparent,
            ],
            stops: [0, solid, solid + (1 - solid) * .45, 1],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SoftGlowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.blur != blur;
}
