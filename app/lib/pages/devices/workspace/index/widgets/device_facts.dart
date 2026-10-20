import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_status.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

/// Device information shares the workspace's first card and remains readable
/// offline. The device name is owned by the page header.
class DeviceFacts extends StatelessWidget {
  const DeviceFacts({super.key, required this.device, this.connecting = false});
  final Json device;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final displayedDevice = connecting
        ? {...device, 'status': 'connecting'}
        : device;
    final android = value(device, 'androidVersion').trim();
    final model = value(device, 'model').trim();
    final address = value(device, 'address').trim();
    final port = int.tryParse(value(device, 'port'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeviceIdentity(device: displayedDevice, showcase: true),
            const SizedBox(width: DesignTokens.spacingLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.isEmpty ? '型号未获取' : model, style: text.bodyMedium),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(
                    android.isEmpty ? 'Android 版本未获取' : 'Android $android',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: DesignTokens.spacingXs),
                  Text(deviceTransportLabel(device), style: text.bodyMedium),
                  const SizedBox(height: DesignTokens.spacingSm),
                  DeviceStatus(device: displayedDevice),
                  if (device['status'] == 'offline') ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text(
                      deviceConnectionLabel(device).replaceFirst('离线 · ', ''),
                      style: text.bodySmall,
                    ),
                  ],
                  const SizedBox(height: DesignTokens.spacingSm),
                  Text('地址', style: text.bodySmall),
                  Text(
                    address.isEmpty ? '未记录' : address,
                    style: text.bodyMedium,
                  ),
                  if (device['transport'] != 'usb' &&
                      port != null &&
                      port >= 1 &&
                      port <= 65535) ...[
                    const SizedBox(height: DesignTokens.spacingXs),
                    Text('连接端口', style: text.bodySmall),
                    Text('$port', style: text.bodyMedium),
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

String deviceTransportLabel(Json device) =>
    switch (value(device, 'transport')) {
      'usb' => 'USB',
      'tls' => '无线调试',
      'tcp' || 'wireless' => 'IP 连接',
      _ => '连接方式未获取',
    };
