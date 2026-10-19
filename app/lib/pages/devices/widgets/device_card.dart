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

    return ContentPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: busy.value ? null : enter,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
            vertical: DesignTokens.spacingXs,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.smartphone,
                size: DesignTokens.componentIconSize,
                color: ConnectTokens.accent(context, ConnectTokens.blue),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Text(
                  deviceName(device),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              Text(
                busy.value ? '连接中' : statusText(status),
                softWrap: false,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                onPressed: () =>
                    DeviceDetailsRoute(deviceId: value(device, 'id'))
                        .push<void>(context),
                tooltip: '${deviceName(device)}详情',
                icon: const Icon(
                  LucideIcons.ellipsis,
                  size: DesignTokens.componentIconActionSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
