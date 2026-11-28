import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 插图边长与柔形（Ardot「插图 · 设备靠近」37:2967：160 画布内 144 圆形，居中）。
const _artSize = 160.0;
const _blobSize = 144.0;

/// 本机窗口与手机线稿（Ardot 37:1994 / 37:1995）：卡片底、2 点 `primary` 描边、圆角 8。
const _windowSize = Size(76, 56);
const _phoneSize = Size(40, 72);
const _outline = 2.0;

/// 靠近动效时长（Ardot 分镜 12:28「停稳后 · 约 320 ms」）。
const _settle = Duration(milliseconds: 320);

/// 进入时与停稳后的位置和角度（Ardot 37:1992「进入时」→ 37:1942「停稳后」，角度单位为度）。
const _windowFrom = (x: 2.0, y: 92.0, angle: -10.0);
const _windowTo = (x: 12.0, y: 84.0, angle: -4.0);
const _phoneFrom = (x: 120.0, y: 14.0, angle: -16.0);
const _phoneTo = (x: 110.0, y: 22.0, angle: -8.0);

/// 信号点：位置、直径、进入时不透明度（第三点进入时隐藏）。
const _signals = [
  (x: 86.0, y: 76.0, size: 4.0, from: .38),
  (x: 93.0, y: 68.0, size: 6.0, from: .38),
  (x: 100.0, y: 58.0, size: 8.0, from: 0.0),
];

/// 首次添加的设备靠近线稿（design.md「设备与工作台 · 首次添加」）：
/// `primary-container` 圆形柔形上，本机窗口与手机向彼此靠近并停稳。
class FirstDeviceIllustration extends HookWidget {
  const FirstDeviceIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotionOf(context);
    final motion = useAnimationController(
      duration: _settle,
      initialValue: reduced ? 1 : 0,
    );
    useEffect(() {
      if (reduced) {
        motion.value = 1;
      } else {
        motion.forward();
      }
      return null;
    }, [motion, reduced]);
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: _artSize,
        child: AnimatedBuilder(
          animation: motion,
          builder: (context, _) {
            final t = reduced
                ? 1.0
                : Curves.easeOutCubic.transform(motion.value);
            Widget placed(
              ({double x, double y, double angle}) from,
              ({double x, double y, double angle}) to,
              Widget child, {
              Key? key,
            }) => Positioned(
              key: key,
              left: lerpDouble(from.x, to.x, t),
              top: lerpDouble(from.y, to.y, t),
              child: Transform.rotate(
                alignment: Alignment.topLeft,
                angle: lerpDouble(from.angle, to.angle, t)! * math.pi / 180,
                child: child,
              ),
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: (_artSize - _blobSize) / 2,
                  top: (_artSize - _blobSize) / 2,
                  child: Container(
                    width: _blobSize,
                    height: _blobSize,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                placed(
                  _windowFrom,
                  _windowTo,
                  key: const ValueKey('first-device-window'),
                  _Sketch(
                    size: _windowSize,
                    marks: [
                      _Mark(8, 8, 4, 4, colors.primary, circle: true),
                      _Mark(16, 8, 16, 4, colors.primaryContainer),
                      _Mark(
                        8,
                        20,
                        16,
                        26,
                        colors.primaryContainer,
                        radius: DesignTokens.roundedXs,
                      ),
                      _Mark(30, 24, 32, 4, colors.primary),
                      _Mark(30, 34, 22, 4, colors.primaryContainer),
                    ],
                  ),
                ),
                for (final signal in _signals)
                  Positioned(
                    left: signal.x,
                    top: signal.y,
                    child: Opacity(
                      opacity: lerpDouble(signal.from, 1, t)!,
                      child: Container(
                        width: signal.size,
                        height: signal.size,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                placed(
                  _phoneFrom,
                  _phoneTo,
                  _Sketch(
                    size: _phoneSize,
                    marks: [
                      _Mark(14, 6, 12, 3, colors.primary),
                      _Mark(
                        8,
                        18,
                        24,
                        20,
                        colors.primaryContainer,
                        radius: DesignTokens.roundedXs,
                      ),
                      _Mark(8, 44, 18, 3, colors.primary),
                      _Mark(14, 62, 12, 3, colors.primary),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Mark {
  const _Mark(
    this.x,
    this.y,
    this.width,
    this.height,
    this.color, {
    this.radius,
    this.circle = false,
  });
  final double x, y, width, height;
  final Color color;

  /// 圆角矩形的圆角；为空时画胶囊。
  final double? radius;
  final bool circle;
}

class _Sketch extends StatelessWidget {
  const _Sketch({required this.size, required this.marks});
  final Size size;
  final List<_Mark> marks;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: size.width,
      height: size.height,
      decoration: ShapeDecoration(
        color: colors.card,
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(DesignTokens.roundedSm),
          ),
          side: BorderSide(color: colors.primary, width: _outline),
        ),
      ),
      child: Stack(
        children: [
          for (final mark in marks)
            Positioned(
              left: mark.x,
              top: mark.y,
              width: mark.width,
              height: mark.height,
              child: DecoratedBox(
                decoration: mark.circle
                    ? BoxDecoration(color: mark.color, shape: BoxShape.circle)
                    : ShapeDecoration(
                        color: mark.color,
                        shape: mark.radius == null
                            ? const StadiumBorder()
                            : RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.circular(
                                  mark.radius!,
                                ),
                              ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
