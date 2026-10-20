import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

class DeviceStatus extends StatelessWidget {
  const DeviceStatus({super.key, required this.device, this.compact = false});
  final Json device;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = value(device, 'status', 'offline');
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      'connected' => (LucideIcons.circleCheck, ConnectTokens.mint),
      'connecting' ||
      'reconnecting' ||
      'checking' => (LucideIcons.loaderCircle, ConnectTokens.blue),
      'unauthorized' => (LucideIcons.shieldAlert, ConnectTokens.amber),
      _ => (LucideIcons.wifiOff, colors.onSurfaceVariant),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: DesignTokens.spacingMicro),
          child: Icon(
            icon,
            size: DesignTokens.componentIconSmallSize,
            color: color,
          ),
        ),
        const SizedBox(width: DesignTokens.spacingTight),
        Flexible(
          child: Text(
            statusText(status),
            style: compact
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
