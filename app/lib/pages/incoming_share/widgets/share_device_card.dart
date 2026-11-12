import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';

class ShareDeviceCard extends StatelessWidget {
  const ShareDeviceCard({
    super.key,
    required this.device,
    required this.selected,
    required this.onTap,
  });
  final DeviceSnapshot device;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      child: ContentPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.componentDeviceListItemHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
                vertical: DesignTokens.spacingMd,
              ),
              child: Row(
                children: [
                  DeviceIdentity(device: device),
                  const SizedBox(width: DesignTokens.spacingMd),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName(device),
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.circleCheck,
                              size: DesignTokens.componentIconSmallSize,
                              color: ConnectTokens.mint,
                            ),
                            const SizedBox(width: DesignTokens.spacingXxs),
                            Expanded(
                              child: Text(
                                '已连接 · ${deviceTransportLabel(device)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingXs),
                  if (selected)
                    Icon(
                      LucideIcons.circleCheck,
                      color: theme.colorScheme.primary,
                      size: DesignTokens.componentIconSize,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
