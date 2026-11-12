import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

class DeviceCard extends HookConsumerWidget {
  const DeviceCard({super.key, required this.device, this.compact = false});
  final DeviceSnapshot device;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = useState(false);
    final starting = useState(false);
    final current = ref.read(deviceListProvider.notifier).current(device);
    final connected = current.status == DeviceConnectionStatus.connected;
    final canStop = starting.value || hasDeviceConnectionIntent(current);
    Future<void> run(Future<void> Function() action) async {
      if (pending.value) return;
      pending.value = true;
      try {
        await action();
      } finally {
        if (context.mounted) pending.value = false;
      }
    }

    return ContentPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
        onTap: () => WorkspaceRoute(deviceId: device.id).push<void>(context),
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
                  ? DesignTokens.spacingXs
                  : DesignTokens.spacingMd,
            ),
            child: Row(
              children: [
                DeviceIdentity(device: current, compact: compact),
                const SizedBox(width: DesignTokens.spacingMd),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              deviceName(current),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spacingXs),
                          GlassMenuButton(
                            tooltip: '设备操作',
                            icon: const Icon(
                              LucideIcons.ellipsis,
                              size: DesignTokens.componentIconSmallSize,
                            ),
                            actions: [
                              GlassMenuAction(
                                label: connected
                                    ? '断开连接'
                                    : canStop
                                    ? '停止连接'
                                    : '开始连接',
                                icon: Icon(
                                  canStop
                                      ? LucideIcons.unplug
                                      : LucideIcons.plug,
                                ),
                                onPressed: pending.value
                                    ? null
                                    : canStop
                                    ? () => run(
                                        () => stopDeviceConnection(
                                          context,
                                          ref,
                                          device,
                                        ),
                                      )
                                    : () async {
                                        if (starting.value) return;
                                        starting.value = true;
                                        try {
                                          await offerDeviceConnection(
                                            context,
                                            ref,
                                            ref
                                                .read(
                                                  deviceListProvider.notifier,
                                                )
                                                .current(device),
                                          );
                                        } finally {
                                          if (context.mounted) {
                                            starting.value = false;
                                          }
                                        }
                                      },
                              ),
                              GlassMenuAction(
                                label: '连接配置',
                                icon: const Icon(LucideIcons.settings2),
                                onPressed: pending.value
                                    ? null
                                    : () => DeviceConnectionRoute(
                                        deviceId: device.id,
                                      ).push<void>(context),
                              ),
                              GlassMenuAction(
                                label: '移除此设备',
                                icon: const Icon(LucideIcons.trash2),
                                destructive: true,
                                onPressed: pending.value
                                    ? null
                                    : () => run(() async {
                                        await removeSavedDevice(
                                          context,
                                          ref,
                                          device,
                                        );
                                      }),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(
                        height: compact
                            ? DesignTokens.spacingXxs
                            : DesignTokens.spacingXs,
                      ),
                      DeviceStatus(device: current, compact: compact),
                      if (current.status == DeviceConnectionStatus.offline) ...[
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Text(
                          deviceConnectionLabel(current)
                              .replaceFirst('离线 · ', ''),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if (!compact &&
                          (current.model ?? '').isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Text(
                          (current.model ?? ''),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
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
