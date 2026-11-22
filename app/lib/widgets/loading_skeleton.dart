import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

/// Shows a single accessible loading region once the read has taken 150 ms.
class LoadingSkeleton extends HookWidget {
  const LoadingSkeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = useState(false);
    useEffect(() {
      final timer = Timer(const Duration(milliseconds: 150), () {
        visible.value = true;
      });
      return timer.cancel;
    }, const []);
    if (!visible.value) return const SizedBox.shrink();

    return Semantics(
      container: true,
      liveRegion: true,
      label: '正在读取',
      child: IgnorePointer(child: ExcludeSemantics(child: child)),
    );
  }
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
            ListTile(
              minTileHeight: height,
              minLeadingWidth: leadingSize,
              tileColor: cardRadius == null
                  ? null
                  : Theme.of(context).colorScheme.surface,
              shape: cardRadius == null
                  ? null
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(cardRadius!),
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
                vertical: DesignTokens.spacingXs,
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
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? DesignTokens.componentSkeletonGraphicDarkBackgroundColor
          : DesignTokens.componentSkeletonGraphicBackgroundColor,
      borderRadius: BorderRadius.circular(radius),
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
    final theme = Theme.of(context);
    final fontSize = secondary
        ? theme.textTheme.bodySmall!.fontSize!
        : theme.textTheme.bodyMedium!.fontSize!;
    return FractionallySizedBox(
      widthFactor: fraction,
      alignment: alignment,
      child: Container(
        height: MediaQuery.textScalerOf(context).scale(fontSize) * 0.75,
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? DesignTokens.componentSkeletonLineDarkBackgroundColor
              : DesignTokens.componentSkeletonLineBackgroundColor,
          borderRadius: BorderRadius.circular(DesignTokens.roundedFull),
        ),
      ),
    );
  }
}
