import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_battery.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';

/// 工作台概览的上半部（Ardot 37:1510「概览」）：左侧 `title1` 设备名、系统版本、
/// 电量与连接方式，右侧手机轮廓，间距 16。
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
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
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
      bool emphasized = false,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: DesignTokens.componentSectionGlyphSize,
          color: iconColor ?? colors.text,
        ),
        const SizedBox(width: DesignTokens.spacingSm),
        Flexible(
          child: Text(
            value,
            style: emphasized ? type.label : type.subheadline,
            semanticsLabel: accessibilityLabel,
          ),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  name,
                  style: type.title1,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (version != null || model != null && model != name) ...[
                const SizedBox(height: DesignTokens.spacingXs),
                Text(
                  version != null ? 'Android $version' : model!,
                  style: type.subheadline.copyWith(color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: DesignTokens.spacingLg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DesignTokens.spacingSm,
                children: [
                  metric(
                    batteryIcon,
                    level == null ? '—' : '$level%',
                    emphasized: true,
                    accessibilityLabel: statusLabel == null
                        ? levelLabel
                        : '$levelLabel，$statusLabel',
                    iconColor: charging ? colors.success : null,
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
        const SizedBox(width: DesignTokens.spacingLg),
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
