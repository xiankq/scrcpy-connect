import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceCard extends HookConsumerWidget {
  const DeviceCard({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    ref.watch(appControllerProvider.select((state) => state.devices));
    final busy = useState(false);
    final status = value(device, 'status', 'offline');
    final online = status == 'connected';
    Future<void> enter() async {
      if (online) {
        WorkspaceRoute(deviceId: value(device, 'id')).push<void>(context);
        return;
      }
      if (status == 'unauthorized') {
        AddDeviceRoute(deviceId: responseDeviceId(device)).push<void>(context);
        return;
      }
      busy.value = true;
      final result = await perform(context, controller, 'devices.connect', {
        'deviceId': device['id'],
      });
      await controller.refreshDevices();
      if (context.mounted && result != null) {
        final updated = controller.currentDevice(device);
        if (updated['status'] == 'connected') {
          WorkspaceRoute(deviceId: value(updated, 'id')).push<void>(context);
        }
      }
      if (context.mounted) busy.value = false;
    }

    return Glass(
      solid: appSettings['reduceTransparency'] == true,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: busy.value ? null : enter,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  LucideIcons.smartphone,
                  size: 44,
                  color: online
                      ? Theme.of(context).colorScheme.primary
                      : ConnectTokens.secondary,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName(device),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          online
                              ? LucideIcons.circleCheck
                              : status == 'unauthorized'
                              ? LucideIcons.shieldAlert
                              : LucideIcons.circleDashed,
                          size: 14,
                          color: online
                              ? ConnectTokens.mint
                              : ConnectTokens.secondary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            busy.value ? '正在连接…' : statusText(status),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      online
                          ? '${value(device, 'transport', '设备连接')}${device['battery'] == null ? '' : ' · ${device['battery']}%'}'
                          : value(device, 'lastSeenLabel', '连接以检查当前状态'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    onPressed: () =>
                        DeviceDetailsRoute(deviceId: value(device, 'id'))
                            .push<void>(context),
                    tooltip: '${deviceName(device)}详情',
                    icon: const Icon(LucideIcons.ellipsis, size: 20),
                  ),
                  if (busy.value)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      online
                          ? LucideIcons.arrowUpRight
                          : LucideIcons.arrowRight,
                      size: 19,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
