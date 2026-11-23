import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';

class DeviceSummary extends StatelessWidget {
  const DeviceSummary({
    super.key,
    required this.device,
    this.battery,
    this.connecting = false,
    this.pane = false,
  });
  final DeviceSnapshot device;
  final DeviceBattery? battery;
  final bool connecting;
  final bool pane;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final displayedDevice = connecting
        ? device.copyWith(status: .connecting)
        : device;
    final version = device.androidVersion;
    final model = device.model;
    final name = deviceName(device);
    final transport = device.transport;
    final level = battery?.level;
    final status = battery?.status ?? DeviceBatteryStatus.unknown;
    final charging = status == .charging;
    final statusLabel = deviceBatteryStatusLabel(status);
    final levelLabel = level == null ? '未获取电量' : '电量 $level%';
    final batteryIcon = charging
        ? LucideIcons.batteryCharging
        : level == null
        ? LucideIcons.battery
        : level <= 20
        ? LucideIcons.batteryLow
        : level < 70
        ? LucideIcons.batteryMedium
        : LucideIcons.batteryFull;
    Widget metric(
      IconData icon,
      String value, {
      String? accessibilityLabel,
      Color? iconColor,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: DesignTokens.componentIconSmallSize, color: iconColor),
        const SizedBox(width: DesignTokens.spacingXxs),
        Flexible(
          child: Text(
            value,
            style: text.bodyMedium,
            semanticsLabel: accessibilityLabel,
          ),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: pane ? 0 : DesignTokens.spacingSm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    name,
                    style: text.displaySmall?.copyWith(
                      fontSize: DesignTokens.typographyConnectionTitleFontSize,
                      height: DesignTokens.typographyConnectionTitleLineHeight,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXs),
                if (version != null || model != null && model != name)
                  Text(
                    version != null ? 'Android $version' : model!,
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: DesignTokens.spacingLg),
                Wrap(
                  spacing: DesignTokens.spacingMd,
                  runSpacing: DesignTokens.spacingXs,
                  children: [
                    metric(
                      batteryIcon,
                      level == null ? '—' : '$level%',
                      accessibilityLabel: statusLabel == null
                          ? levelLabel
                          : '$levelLabel，$statusLabel',
                      iconColor: charging
                          ? Theme.of(context).brightness == Brightness.dark
                                ? DesignTokens.colorSuccessDark
                                : DesignTokens.colorSuccess
                          : null,
                    ),
                    if (transport != null)
                      metric(
                        transport == .usb ? LucideIcons.usb : LucideIcons.wifi,
                        transport == .usb
                            ? 'USB 调试'
                            : deviceTransportLabel(device),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: DesignTokens.spacingSm),
        Semantics(
          label: deviceStatusText(displayedDevice),
          child: DeviceIdentity(
            device: displayedDevice,
            showcase: true,
            pane: pane,
          ),
        ),
      ],
    );
  }
}
