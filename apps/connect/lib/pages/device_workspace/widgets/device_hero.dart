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
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final online = device['status'] == 'connected';
    return Glass(
      solid: appSettings['reduceTransparency'] == true,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FeatureIcon(
                LucideIcons.smartphone,
                color: ConnectTokens.mint,
                size: 64,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续使用这台手机',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      online ? '真实画面、原有应用与登录状态' : '连接后即可打开手机屏幕',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => online
                  ? openRemoteRoute(context, deviceId: value(device, 'id'))
                  : AddDeviceRoute(deviceId: value(device, 'id'))
                        .push<void>(context),
              icon: Icon(
                online ? LucideIcons.arrowUpRight : LucideIcons.link,
                size: 19,
              ),
              label: Text(online ? '打开手机屏幕' : '恢复连接'),
            ),
          ),
        ],
      ),
    );
  }
}
