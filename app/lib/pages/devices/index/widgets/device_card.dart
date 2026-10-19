import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceCard extends HookConsumerWidget {
  const DeviceCard({
    super.key,
    required this.controller,
    required this.device,
    this.compact = false,
  });
  final AppController controller;
  final Json device;
  final bool compact;
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: compact
                ? DesignTokens.componentDeviceListItemCompactHeight
                : DesignTokens.componentDeviceListItemHeight,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
              vertical: compact
                  ? DesignTokens.spacingXxs
                  : DesignTokens.spacingMd,
            ),
            child: Row(
              children: [
                DeviceIdentity(compact: compact),
                const SizedBox(width: DesignTokens.spacingSm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName(device),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      SizedBox(
                        height: compact
                            ? DesignTokens.spacingMicro
                            : DesignTokens.spacingXxs,
                      ),
                      Text(
                        busy.value ? '正在连接' : deviceConnectionLabel(device),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingXs),
                GlassMenuButton(
                  tooltip: '${deviceName(device)}详情',
                  actions: [
                    GlassMenuAction(
                      label: '设备详情',
                      icon: const Icon(LucideIcons.info),
                      onPressed: () =>
                          DeviceDetailsRoute(deviceId: value(device, 'id'))
                              .push<void>(context),
                    ),
                  ],
                  icon: const Icon(
                    LucideIcons.ellipsis,
                    size: DesignTokens.componentIconActionSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
