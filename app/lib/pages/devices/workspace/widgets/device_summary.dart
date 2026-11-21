import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';

class DeviceSummary extends HookWidget {
  const DeviceSummary({
    super.key,
    required this.device,
    this.connecting = false,
    this.pane = false,
  });
  final DeviceSnapshot device;
  final bool connecting;
  final bool pane;

  @override
  Widget build(BuildContext context) {
    useStream(
      useMemoized(
        () => Stream<int>.periodic(const Duration(seconds: 30), (tick) => tick),
      ),
      initialData: 0,
    );
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final updatedAt = device.batteryUpdatedAt;
    final liveBattery =
        device.status == .connected &&
        updatedAt != null &&
        now >= updatedAt &&
        now - updatedAt <= 90;
    final text = Theme.of(context).textTheme;
    final displayedDevice = connecting
        ? device.copyWith(status: .connecting)
        : device;
    final version = device.androidVersion;
    final model = device.model;
    final name = deviceName(device);
    final transport = device.transport;
    final battery = device.battery;
    final batteryIcon = device.charging == true
        ? LucideIcons.batteryCharging
        : battery != null && battery <= 20
        ? LucideIcons.batteryLow
        : battery != null && battery < 70
        ? LucideIcons.batteryMedium
        : LucideIcons.batteryFull;
    Widget metric(IconData icon, String value, {String? accessibilityLabel}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: DesignTokens.componentIconSmallSize),
            const SizedBox(width: DesignTokens.spacingXxs),
            Text(
              value,
              style: text.bodySmall,
              semanticsLabel: accessibilityLabel,
            ),
          ],
        );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: text.displaySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (version != null || model != null && model != name)
                Text(
                  version != null ? 'Android $version' : model!,
                  style: text.bodyMedium,
                ),
              const SizedBox(height: DesignTokens.spacingXs),
              Wrap(
                spacing: DesignTokens.spacingMd,
                runSpacing: DesignTokens.spacingXs,
                children: [
                  if (liveBattery && battery != null)
                    metric(
                      batteryIcon,
                      '$battery%',
                      accessibilityLabel: device.charging == true
                          ? '正在充电，电量 $battery%'
                          : '电量 $battery%',
                    ),
                  if (!liveBattery || battery == null)
                    metric(
                      LucideIcons.battery,
                      '—',
                      accessibilityLabel: '未获取电量',
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
