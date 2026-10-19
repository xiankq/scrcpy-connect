import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceHero extends ConsumerWidget {
  const DeviceHero({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = device['status'] == 'connected';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => online
                ? openRemoteRoute(context, deviceId: value(device, 'id'))
                : AddDeviceRoute(deviceId: value(device, 'id'))
                      .push<void>(context),
            icon: Icon(
              online ? LucideIcons.arrowUpRight : LucideIcons.link,
              size: DesignTokens.componentIconActionSize,
            ),
            label: Text(online ? '打开手机屏幕' : '恢复连接'),
          ),
        ),
      ],
    );
  }
}
