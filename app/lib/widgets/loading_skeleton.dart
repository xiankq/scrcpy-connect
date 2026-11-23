import 'dart:async';

import 'dart:ui' as ui;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';

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
    final phase = useAnimationController(duration: skeletonCycle);
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
  _SkeletonPaint(this.phase, this.base, this.highlight, this.radius)
    : super(repaint: phase);

  final Animation<double>? phase;
  final Color base, highlight;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = base;
    if (phase case final animation?) {
      final progress = panelCurve.transform(animation.value);
      final x = size.width * (progress * 2 - .5);
      paint.shader = ui.Gradient.linear(
        Offset(x - size.width * .45, 0),
        Offset(x + size.width * .45, size.height),
        [base, highlight, base],
        const [0, .55, 1],
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SkeletonPaint oldDelegate) =>
      phase != oldDelegate.phase ||
      base != oldDelegate.base ||
      highlight != oldDelegate.highlight ||
      radius != oldDelegate.radius;
}

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({
    super.key,
    this.height = DesignTokens.componentRowHeight,
    this.leadingSize = DesignTokens.componentListIconSize,
    this.leadingHeight,
    this.lines = 2,
    this.trailing = false,
    this.progress = false,
    this.cardRadius,
    this.gap = DesignTokens.spacingZero,
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
                  ? DesignTokens.colorTransparent
                  : Theme.of(context).colorScheme.surface,
              borderRadius: cardRadius == null
                  ? null
                  : BorderRadius.circular(cardRadius!),
              child: ListTile(
                minTileHeight: height,
                minLeadingWidth: leadingSize,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingMd,
                ),
                leading: SkeletonBlock(
                  width: leadingSize,
                  height: leadingHeight ?? leadingSize,
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonLine(fraction: index.isEven ? 0.68 : 0.53),
                    if (lines >= 2) ...[
                      const SizedBox(height: DesignTokens.spacingXxs),
                      const SkeletonLine(fraction: 0.42, secondary: true),
                    ],
                    if (lines == 3) ...[
                      const SizedBox(height: DesignTokens.spacingXxs),
                      const SkeletonLine(fraction: 0.56, secondary: true),
                    ],
                    if (progress) ...[
                      const SizedBox(height: DesignTokens.spacingXxs),
                      const SkeletonBlock(
                        height: DesignTokens.componentTransferProgressHeight,
                        radius: DesignTokens.componentTransferProgressRounded,
                      ),
                    ],
                  ],
                ),
                trailing: trailing
                    ? const SkeletonBlock(
                        width: DesignTokens.componentIconSize,
                        height: DesignTokens.spacingXs,
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
    this.radius = DesignTokens.roundedMd,
  });

  final double? width, height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SkeletonPaint(
          context.dependOnInheritedWidgetOfExactType<_SkeletonPalette>()?.phase,
          dark
              ? DesignTokens.componentSkeletonGraphicDarkBackgroundColor
              : DesignTokens.componentSkeletonGraphicBackgroundColor,
          dark
              ? DesignTokens.componentSkeletonHighlightDarkBackgroundColor
              : DesignTokens.componentSkeletonHighlightBackgroundColor,
          radius,
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
    final fontSize = secondary
        ? theme.textTheme.bodySmall!.fontSize!
        : theme.textTheme.bodyMedium!.fontSize!;
    return FractionallySizedBox(
      widthFactor: fraction,
      alignment: alignment,
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(fontSize) * 0.75,
        child: CustomPaint(
          painter: _SkeletonPaint(
            context
                .dependOnInheritedWidgetOfExactType<_SkeletonPalette>()
                ?.phase,
            theme.brightness == Brightness.dark
                ? DesignTokens.componentSkeletonLineDarkBackgroundColor
                : DesignTokens.componentSkeletonLineBackgroundColor,
            theme.brightness == Brightness.dark
                ? DesignTokens.componentSkeletonHighlightDarkBackgroundColor
                : DesignTokens.componentSkeletonHighlightBackgroundColor,
            DesignTokens.roundedFull,
          ),
        ),
      ),
    );
  }
}
