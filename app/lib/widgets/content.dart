import 'dart:math' as math;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 不定进度：24 点 `primary` 环形指示器，淡色轨道上的弧线随转动伸缩
/// （design.md「空态、加载与进度」，弧线节奏沿用 Prism ActivityIndicator）。
class ContentLoadingIndicator extends HookWidget {
  const ContentLoadingIndicator({
    super.key,
    this.size = DesignTokens.componentBarGlyphSize,
    this.color,
  });

  final double size;
  final Color? color;

  /// 一轮三圈、两次伸缩的时长（Prism `_ArcPainter.loop`）。
  static const _loop = Duration(milliseconds: 3200);

  @override
  Widget build(BuildContext context) {
    final animate = !reduceMotionOf(context);
    final rotation = useAnimationController(duration: _loop);
    useEffect(() {
      if (animate) {
        rotation.repeat();
      } else {
        rotation.reset();
      }
      return null;
    }, [rotation, animate]);
    return Semantics(
      label: '正在加载',
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: _ArcPainter(
              progress: rotation,
              color: color ?? AppColors.of(context).primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.progress, required this.color})
    : super(repaint: progress);

  // 图形在 24 栅格内占 20（Lucide 线框区）；轨道为前景的 20%。
  static const _liveArea = 20 / 24;
  static const _trackInk = .2;
  static const _turns = 3;
  static const _stretches = 2;
  static const _minSweep = .1;
  static const _maxSweep = .62;
  static const _headLead = .14;

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final strokeWidth = (side / 9).clamp(1.5, 4.0);
    final radius = (side * _liveArea - strokeWidth) / 2;
    if (radius <= 0) return;
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: color.a * _trackInk);
    canvas.drawCircle(center, radius, stroke);
    final t = progress.value;
    final stretch = .5 - .5 * math.cos(t * _stretches * 2 * math.pi);
    final sweep = _minSweep + (_maxSweep - _minSweep) * stretch;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      (t * _turns + _headLead * stretch) * 2 * math.pi - math.pi / 2,
      sweep * 2 * math.pi,
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// 页面上的内容卡片：`card` 底、圆角 24、内距 16。
class ContentPanel extends StatelessWidget {
  const ContentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignTokens.componentCardPadding),
    this.radius = DesignTokens.componentListGroupRounded,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.of(context).card,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// 功能色块：功能色方块上放白色线形图形（Ardot 功能色块 37:570，与 ListIconBadge 同规格）。
///
/// 默认 30 点、圆角 8、图形 18；其他尺寸圆角取不超过短边三分之一的最大档。
/// 52 点以上的大色块（工作台快捷入口 52、文件格式「详情」[detailSize] 56）图形 28
/// （Ardot 快捷入口 37:1761、文件格式 37:1032），更小的尺寸图形按 30 点的比例缩放。
class FeatureIcon extends StatelessWidget {
  const FeatureIcon(
    this.icon, {
    super.key,
    this.color = DesignTokens.componentIconTileDeviceBackgroundColor,
    this.size = DesignTokens.componentIconTileSize,
  });
  final IconData icon;
  final Color color;
  final double size;

  /// 详情尺寸（Ardot 文件格式 37:1032「尺寸=详情」）：56 方块、圆角 16、图形 28。
  static const detailSize = 56.0;

  static const _largeGlyphSize = 28.0;

  static const _radii = [
    DesignTokens.roundedXxl,
    DesignTokens.roundedXl,
    DesignTokens.roundedLg,
    DesignTokens.roundedMd,
    DesignTokens.roundedSm,
    DesignTokens.roundedXs,
  ];

  @override
  Widget build(BuildContext context) {
    final radius = size == DesignTokens.componentIconTileSize
        ? DesignTokens.componentIconTileRounded
        : _radii.firstWhere(
            (radius) => radius <= size / 3,
            orElse: () => DesignTokens.roundedXs,
          );
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: color,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        child: Icon(
          icon,
          color: DesignTokens.componentIconTileTextColor,
          size: size >= DesignTokens.componentDeviceTileSize
              ? _largeGlyphSize
              : size *
                    DesignTokens.componentIconTileGlyphSize /
                    DesignTokens.componentIconTileSize,
        ),
      ),
    );
  }
}

/// Ardot 空态 37:799：柔形 116、圆角 28，图形 64。
const _emptyShapeSize = 116.0;
const _emptyGlyphSize = 64.0;

/// 空态：居中略偏上（纵向 40%），最宽 320；`primary-container` 柔形上放 64 点
/// `primary` 线形图形，下方 16 为 `headline` 标题、8 为说明、24 为动作。
class EmptyContent extends StatelessWidget {
  const EmptyContent({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return Align(
      // 纵向 40%：Alignment.y = 0.4 * 2 - 1。
      alignment: const Alignment(0, -.2),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXxl,
            vertical: DesignTokens.componentEmptyStatePadding,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.componentEmptyStateWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: _emptyShapeSize,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colors.primaryContainer,
                        shape: const RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(DesignTokens.roundedXxl),
                          ),
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: _emptyGlyphSize,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                Text(title, style: type.headline, textAlign: TextAlign.center),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: DesignTokens.spacingSm),
                  Text(
                    message!,
                    style: type.subheadline.copyWith(
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: DesignTokens.spacingXxl),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
