import 'package:scrcpy_connect/services/display_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_identity.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceCard extends HookWidget {
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
  Widget build(BuildContext context) {
    final pending = useState(false);
    final current = controller.currentDevice(device);
    final connecting =
        pending.value ||
        ['connecting', 'checking', 'reconnecting'].contains(current['status']);
    final connected = current['status'] == 'connected';
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
        onTap: () =>
            WorkspaceRoute(deviceId: value(device, 'id')).push<void>(context),
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
                DeviceIdentity(device: device, compact: compact),
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
                              deviceName(device),
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
                                label: connecting
                                    ? '正在连接…'
                                    : connected
                                    ? '断开连接'
                                    : '开始连接',
                                icon: Icon(
                                  connected
                                      ? LucideIcons.unplug
                                      : LucideIcons.plug,
                                ),
                                onPressed: connecting
                                    ? null
                                    : () => run(() async {
                                        final target = controller.currentDevice(
                                          device,
                                        );
                                        if (connected) {
                                          if (target['status'] != 'connected') {
                                            feedback(
                                              context,
                                              '设备已断开，请重新检查当前状态。',
                                            );
                                            return;
                                          }
                                          if (!await confirmConnectionChange(
                                                context,
                                                '断开 ${deviceName(target)}？',
                                                '将结束此设备的连接、控制画面和进行中的活动。设备记录与已保存文件保留，并停止自动重连。',
                                                action: '断开连接',
                                              ) ||
                                              !context.mounted) {
                                            return;
                                          }
                                          await perform(
                                            context,
                                            controller,
                                            'devices.disconnect',
                                            {'deviceId': target['id']},
                                          );
                                          await controller.refreshDevices();
                                        } else {
                                          if (target['status'] == 'connected') {
                                            feedback(context, '设备已连接。');
                                            return;
                                          }
                                          await offerDeviceConnection(
                                            context,
                                            controller,
                                            target,
                                          );
                                        }
                                      }),
                              ),
                              GlassMenuAction(
                                label: '连接配置',
                                icon: const Icon(LucideIcons.settings2),
                                onPressed: pending.value
                                    ? null
                                    : () => DeviceConnectionRoute(
                                        deviceId: value(device, 'id'),
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
                                          controller,
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
                      DeviceStatus(device: device, compact: compact),
                      if (device['status'] == 'offline') ...[
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Text(
                          deviceConnectionLabel(device)
                              .replaceFirst('离线 · ', ''),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ] else if (!compact &&
                          value(device, 'model').isNotEmpty) ...[
                        const SizedBox(height: DesignTokens.spacingXxs),
                        Text(
                          value(device, 'model'),
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
