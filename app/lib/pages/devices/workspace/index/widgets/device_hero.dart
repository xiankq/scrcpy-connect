import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_facts.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceHero extends HookWidget {
  const DeviceHero({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final busy = useState(false);
    final online = device['status'] == 'connected';
    final unauthorized = device['status'] == 'unauthorized';
    final connecting =
        busy.value ||
        ['checking', 'connecting', 'reconnecting'].contains(device['status']);
    final id = value(device, 'id');
    return ContentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeviceFacts(device: device, connecting: busy.value),
          const SizedBox(height: DesignTokens.spacingLg),
          FilledButton.icon(
            onPressed: connecting
                ? null
                : () async {
                    if (online) {
                      await openRemoteRoute(context, deviceId: id);
                    } else if (unauthorized) {
                      await AddDeviceRoute(deviceId: id).push<void>(context);
                    } else {
                      busy.value = true;
                      await perform(context, controller, 'devices.connect', {
                        'deviceId': id,
                      });
                      await controller.refreshDevices();
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
      ),
    );
  }
}
