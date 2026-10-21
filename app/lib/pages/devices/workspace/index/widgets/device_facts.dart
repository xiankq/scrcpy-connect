import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_status.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// Device information shares the workspace's first card and remains readable
/// offline. The device name is owned by the page header.
class DeviceFacts extends HookWidget {
  const DeviceFacts({super.key, required this.device, this.connecting = false});
  final Json device;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    // Expired metadata must disappear even if the next bounded query fails.
    useStream(
      useMemoized(
        () => Stream<int>.periodic(const Duration(seconds: 30), (tick) => tick),
      ),
      initialData: 0,
    );
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final updatedAt = int.tryParse(value(device, 'batteryUpdatedAt'));
    final liveBattery =
        device['status'] == 'connected' &&
        updatedAt != null &&
        nowSeconds >= updatedAt &&
        nowSeconds - updatedAt <= 90;
    final text = Theme.of(context).textTheme;
    final displayedDevice = connecting
        ? {...device, 'status': 'connecting'}
        : device;
    final model = value(device, 'model').trim();
    final address = value(device, 'address').trim();
    final port = int.tryParse(value(device, 'port'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DeviceIdentity(device: displayedDevice),
            const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.isEmpty ? '型号未获取' : model, style: text.bodyMedium),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Wrap(
                    spacing: DesignTokens.spacingXs,
                    runSpacing: DesignTokens.spacingXxs,
                    children: [
                      DeviceStatus(device: displayedDevice),
                      Text(deviceTransportLabel(device), style: text.bodySmall),
                    ],
                  ),
                  if (device['status'] == 'offline') ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      deviceConnectionLabel(device).replaceFirst('离线 · ', ''),
                      style: text.bodySmall,
                    ),
                  ],
                  const SizedBox(height: DesignTokens.spacingXs),
                  if (device['transport'] != 'usb')
                    Text(
                      address.isEmpty
                          ? '地址未获取'
                          : (port != null && port > 0
                                ? '${address.contains(':') && !address.startsWith('[') ? '[$address]' : address}:$port'
                                : address),
                      style: text.bodySmall,
                    ),
                  if (liveBattery && device['battery'] != null) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Row(
                      children: [
                        Icon(
                          device['charging'] == true
                              ? LucideIcons.batteryCharging
                              : LucideIcons.battery,
                          size: DesignTokens.componentIconSmallSize,
                          color: DesignTokens.colorListIconMint,
                        ),
                        const SizedBox(width: DesignTokens.spacingXxs),
                        Flexible(
                          child: Text(
                            '${device['battery']}%${device['charging'] == true ? ' · 正在充电' : ''}',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (device['status'] != 'connected')
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
            child: Text('信息来自本机记录', style: text.bodySmall),
          ),
      ],
    );
  }
}
