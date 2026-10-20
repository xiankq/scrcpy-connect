import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_status.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.controller,
    required this.device,
    this.compact = false,
  });
  final AppController controller;
  final Json device;
  final bool compact;

  @override
  Widget build(BuildContext context) => ContentPanel(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
      onTap: () =>
          WorkspaceRoute(deviceId: value(device, 'id')).push<void>(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: compact
              ? DesignTokens.componentDeviceListItemCompactHeight
              : DesignTokens.componentDeviceListItemHeight,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
            vertical: compact ? DesignTokens.spacingXs : DesignTokens.spacingMd,
          ),
          child: Row(
            children: [
              DeviceIdentity(compact: compact),
              const SizedBox(width: DesignTokens.spacingMd),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName(device),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(
                      height: compact
                          ? DesignTokens.spacingXxs
                          : DesignTokens.spacingXs,
                    ),
                    DeviceStatus(device: device, compact: compact),
                    if (device['status'] == 'offline') ...[
                      const SizedBox(height: DesignTokens.spacingXxs),
                      Text(
                        deviceConnectionLabel(device).replaceFirst('离线 · ', ''),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else if (!compact &&
                        value(device, 'model').isNotEmpty) ...[
                      const SizedBox(height: DesignTokens.spacingXxs),
                      Text(
                        value(device, 'model'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              const Icon(
                LucideIcons.chevronRight,
                size: DesignTokens.componentIconSmallSize,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
