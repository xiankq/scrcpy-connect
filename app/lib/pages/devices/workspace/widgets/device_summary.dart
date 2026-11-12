import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';

/// 设备信息与工作台首卡共用内容，离线仍可阅读；设备名称由页头拥有。
class DeviceSummary extends HookWidget {
  const DeviceSummary({
    super.key,
    required this.device,
    this.connecting = false,
  });
  final DeviceSnapshot device;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    // 元数据过期后立即消失，即使下一次有界查询失败也不能保留为实时值。
    useStream(
      useMemoized(
        () => Stream<int>.periodic(const Duration(seconds: 30), (tick) => tick),
      ),
      initialData: 0,
    );
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final updatedAt = int.tryParse((device.batteryUpdatedAt?.toString() ?? ''));
    final liveBattery =
        device.status == DeviceConnectionStatus.connected &&
        updatedAt != null &&
        nowSeconds >= updatedAt &&
        nowSeconds - updatedAt <= 90;
    final text = Theme.of(context).textTheme;
    final displayedDevice = connecting
        ? device.copyWith(status: DeviceConnectionStatus.connecting)
        : device;
    final address = (device.address ?? '').trim();
    final port = int.tryParse((device.port?.toString() ?? ''));
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
                  Wrap(
                    spacing: DesignTokens.spacingXs,
                    runSpacing: DesignTokens.spacingXxs,
                    children: [
                      DeviceStatus(device: displayedDevice),
                      Text(deviceTransportLabel(device), style: text.bodySmall),
                    ],
                  ),
                  if (device.status == DeviceConnectionStatus.offline) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      deviceConnectionLabel(device).replaceFirst('离线 · ', ''),
                      style: text.bodySmall,
                    ),
                  ],
                  const SizedBox(height: DesignTokens.spacingXs),
                  if (device.transport != DeviceTransport.usb)
                    Text(
                      address.isEmpty
                          ? '地址未获取'
                          : (port != null && port > 0
                                ? '${address.contains(':') && !address.startsWith('[') ? '[$address]' : address}:$port'
                                : address),
                      style: text.bodySmall,
                    ),
                  if (liveBattery && device.battery != null) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Row(
                      children: [
                        Icon(
                          device.charging == true
                              ? LucideIcons.batteryCharging
                              : LucideIcons.battery,
                          size: DesignTokens.componentIconSmallSize,
                          color: DesignTokens.colorListIconMint,
                        ),
                        const SizedBox(width: DesignTokens.spacingXxs),
                        Flexible(
                          child: Text(
                            '${device.battery}%${device.charging == true ? ' · 正在充电' : ''}',
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
        if (device.status != DeviceConnectionStatus.connected)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacingSm),
            child: Text('信息来自本机记录', style: text.bodySmall),
          ),
      ],
    );
  }
}
