import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/soft_glow.dart';

/// 通话舞台背景（Ardot「通话舞台 · 背景」44:12）：`call-stage` 实体面上三团静态彩光。
///
/// 光斑位置按 402×874 画板的比例摆放，尺寸随窗口面积放大；只绘制一次，没有逐帧工作。
class CallStageBackground extends StatelessWidget {
  const CallStageBackground({super.key});

  /// 画板尺寸（44:12）。
  static const _board = Size(402, 874);

  /// 每团光：模糊前椭圆的左上角与尺寸、图层模糊半径、不透明度。
  /// 取自 44:13 光·主色、44:14 光·青、44:15 光·靛。
  static const _glows = [
    (Rect.fromLTWH(-120, -40, 420, 420), 140.0, .42, DesignTokens.colorPrimary),
    (
      Rect.fromLTWH(200, 220, 340, 340),
      140.0,
      .3,
      DesignTokens.colorAccentTeal,
    ),
    (
      Rect.fromLTWH(-60, 600, 420, 380),
      160.0,
      .38,
      DesignTokens.colorAccentIndigo,
    ),
  ];

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ColoredBox(
      color: DesignTokens.colorCallStage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final scale = math.max(
            1.0,
            math.sqrt(
              size.width * size.height / (_board.width * _board.height),
            ),
          );
          return ClipRect(
            child: Stack(
              children: [
                for (final (rect, blur, opacity, color) in _glows)
                  Positioned.fromRect(
                    rect: Rect.fromCenter(
                      center: Offset(
                        rect.center.dx / _board.width * size.width,
                        rect.center.dy / _board.height * size.height,
                      ),
                      width: (rect.width + 2 * blur) * scale,
                      height: (rect.height + 2 * blur) * scale,
                    ),
                    child: SoftGlow(
                      color: color.withValues(alpha: opacity),
                      blur: blur * scale,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
