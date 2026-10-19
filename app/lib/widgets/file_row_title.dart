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
    child: Row(
      children: [
        Expanded(child: Text(name)),
        if (size != null) ...[
          const SizedBox(width: DesignTokens.spacingXs),
          Flexible(
            child: Text(
              size!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    ),
  );
}
