import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/core/application/app_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_summary.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceHero extends HookWidget {
  const DeviceHero({super.key, required this.controller, required this.device});
  final AppNotifier controller;
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context) {
    final busy = useState(false);
    final online = device.status == DeviceConnectionStatus.connected;
    final unauthorized = device.status == DeviceConnectionStatus.unauthorized;
    final connecting = busy.value || deviceConnectionInProgress(device);
    final id = device.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentPanel(
          child: InkWell(
            onTap: () => DeviceDetailsRoute(deviceId: id).push<void>(context),
            borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
            child: Row(
              children: [
                Expanded(
                  child: DeviceSummary(device: device, connecting: busy.value),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: DesignTokens.componentIconSmallSize,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        FilledButton.icon(
          onPressed: connecting
              ? null
              : () async {
                  if (online) {
                    await openRemoteRoute(context, deviceId: id);
                  } else if (device.transport == DeviceTransport.usb) {
                    await UsbGuideRoute(deviceId: id).push<void>(context);
                  } else if (unauthorized) {
                    await AddDeviceRoute(deviceId: id).push<void>(context);
                  } else {
                    busy.value = true;
                    try {
                      await controller.connections.connectDevice(id);
                    } catch (error) {
                      if (context.mounted) feedback(context, '$error');
                    }
                    await controller.deviceList.refresh();
                    if (context.mounted) busy.value = false;
                  }
                },
          icon: Icon(
            online
                ? LucideIcons.smartphone
                : unauthorized
                ? LucideIcons.shieldCheck
                : LucideIcons.link,
            size: DesignTokens.componentIconActionSize,
          ),
          label: Text(
            connecting
                ? '正在连接'
                : online
                ? '打开手机屏幕'
                : unauthorized
                ? '重新授权'
                : '连接手机',
          ),
        ),
      ],
    );
  }
}
