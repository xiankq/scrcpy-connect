import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';

/// File identity and actual size share one row; the full path stays discoverable.
class FileRowTitle extends StatelessWidget {
  const FileRowTitle({
    super.key,
    required this.name,
    required this.path,
    this.size,
    this.tooltipTriggerMode = TooltipTriggerMode.longPress,
  });
  final String name;
  final String path;
  final String? size;
  final TooltipTriggerMode tooltipTriggerMode;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: path,
    triggerMode: tooltipTriggerMode,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actualSize = size;
        if (actualSize == null) return Text(name);
        final theme = Theme.of(context).textTheme;
        final sizeStyle = theme.bodySmall;
        final painter = TextPainter(
          text: TextSpan(text: actualSize, style: sizeStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final sizeWidth = painter.width;
        painter.dispose();
        final minimumNameWidth = MediaQuery.textScalerOf(context)
            .scale(theme.bodyLarge!.fontSize! * 4);
        final sizeLabel = Text(actualSize, style: sizeStyle);
        if (constraints.maxWidth <
            minimumNameWidth + DesignTokens.spacingXs + sizeWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: sizeLabel,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: Text(name)),
            const SizedBox(width: DesignTokens.spacingXs),
            sizeLabel,
          ],
        );
      },
    ),
  );
}
