import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 骨架呼吸的最低不透明度（interaction-motion「等待与状态切换」：50%–100%）。
const _skeletonMinOpacity = .5;

/// Shows a single accessible loading region once the read has taken 150 ms.
class LoadingSkeleton extends HookWidget {
  const LoadingSkeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = useState(false);
    useEffect(() {
      final timer = Timer(skeletonDelay, () {
        visible.value = true;
      });
      return timer.cancel;
    }, const []);
    if (!visible.value) return const SizedBox.shrink();

    return Semantics(
      container: true,
      liveRegion: true,
      label: '正在读取',
      child: IgnorePointer(
        child: ExcludeSemantics(child: _SkeletonMotion(child: child)),
      ),
    );
  }
}

class _SkeletonMotion extends HookWidget {
  const _SkeletonMotion({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lifecycle = useAppLifecycleState();
    final running =
        !reduceMotionOf(context) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.isCurrentOf(context) != false &&
        TickerMode.valuesOf(context).enabled;
    // 一个呼吸周期 1.6 秒：去程与回程各占一半。
    final phase = useAnimationController(duration: skeletonCycle ~/ 2);
    useEffect(() {
      if (running) {
        phase.repeat(reverse: true);
      } else {
        phase.stop();
      }
      return null;
    }, [phase, running]);
    return _SkeletonPalette(
      phase: running ? phase : null,
      child: RepaintBoundary(child: child),
    );
  }
}

class _SkeletonPalette extends InheritedWidget {
  const _SkeletonPalette({required this.phase, required super.child});
  final Animation<double>? phase;

  @override
  bool updateShouldNotify(_SkeletonPalette oldWidget) =>
      phase != oldWidget.phase;
}

class _SkeletonPaint extends CustomPainter {
  _SkeletonPaint(this.phase, this.color, this.radius) : super(repaint: phase);

  final Animation<double>? phase;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final breath = phase == null
        ? 1.0
        : 1 -
              (1 - _skeletonMinOpacity) *
                  Curves.easeInOut.transform(phase!.value);
    canvas.drawRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius.clamp(0, size.shortestSide / 2)),
      ),
      Paint()..color = color.withValues(alpha: color.a * breath),
    );
  }

  @override
  bool shouldRepaint(_SkeletonPaint oldDelegate) =>
      phase != oldDelegate.phase ||
      color != oldDelegate.color ||
      radius != oldDelegate.radius;
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    this.height = DesignTokens.componentListRowHeight,
    this.leadingSize = DesignTokens.componentIconTileSize,
    this.leadingHeight,
    this.lines = 2,
    this.trailing = false,
    this.progress = false,
    this.cardRadius,
    this.gap = 0,
  });

  final double height, leadingSize, gap;
  final double? leadingHeight, cardRadius;
  final int lines;
  final bool trailing, progress;

  @override
  Widget build(BuildContext context) {
    final rowCount = (MediaQuery.sizeOf(context).height / (height + gap))
        .ceil()
        .clamp(1, 12);
    return LoadingSkeleton(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < rowCount; index++) ...[
            if (index > 0) SizedBox(height: gap),
            Material(
              color: cardRadius == null
                  ? AppColors.of(context).card.withAlpha(0)
                  : AppColors.of(context).card,
              shape: cardRadius == null
                  ? null
                  : RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(cardRadius!),
                    ),
              child: ListTile(
                minTileHeight: height,
                minLeadingWidth: leadingSize,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.componentListRowPadding,
                ),
                horizontalTitleGap: DesignTokens.componentListRowGap,
                leading: SkeletonBlock(
                  width: leadingSize,
                  height: leadingHeight ?? leadingSize,
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonLine(fraction: index.isEven ? 0.68 : 0.53),
                    if (lines >= 2) ...[
                      const SizedBox(height: DesignTokens.spacingSm),
                      const SkeletonLine(fraction: 0.42, secondary: true),
                    ],
                    if (lines == 3) ...[
                      const SizedBox(height: DesignTokens.spacingSm),
                      const SkeletonLine(fraction: 0.56, secondary: true),
                    ],
                    if (progress) ...[
                      const SizedBox(height: DesignTokens.spacingSm),
                      const SkeletonBlock(
                        height: DesignTokens.componentProgressHeight,
                        radius: DesignTokens.componentProgressRounded,
                      ),
                    ],
                  ],
                ),
                trailing: trailing
                    ? const SkeletonBlock(
                        width: DesignTokens.spacingJumbo,
                        height: DesignTokens.spacingMd,
                        radius: DesignTokens.roundedFull,
                      )
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    this.height,
    this.radius = DesignTokens.roundedSm,
  });

  final double? width, height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(
      painter: _SkeletonPaint(
        context.dependOnInheritedWidgetOfExactType<_SkeletonPalette>()?.phase,
        AppColors.of(context).inset,
        radius,
      ),
    ),
  );
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    required this.fraction,
    this.secondary = false,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final double fraction;
  final bool secondary;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    final fontSize = secondary
        ? type.subheadline.fontSize!
        : type.body.fontSize!;
    return FractionallySizedBox(
      widthFactor: fraction,
      alignment: alignment,
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(fontSize) * .75,
        child: CustomPaint(
          painter: _SkeletonPaint(
            context
                .dependOnInheritedWidgetOfExactType<_SkeletonPalette>()
                ?.phase,
            AppColors.of(context).inset,
            DesignTokens.roundedFull,
          ),
        ),
      ),
    );
  }
}
