import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceSourceRow extends StatelessWidget {
  const DeviceSourceRow({
    super.key,
    required this.device,
    this.padding = EdgeInsets.zero,
  });

  final DeviceSnapshot device;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DesignTokens.spacingLg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.smartphone,
              size: DesignTokens.componentIconSmallSize - 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: DesignTokens.spacingTight),
            Expanded(
              child: Text(
                deviceName(device),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
