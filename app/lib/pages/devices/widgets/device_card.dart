import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';
import 'package:scrcpy_connect/widgets/glass/glass_menu.dart';

class DeviceCard extends HookConsumerWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.compact = false,
    this.selected = false,
    this.onOpen,
  });
  final DeviceSnapshot device;
  final bool compact;
  final bool selected;
  final VoidCallback? onOpen;

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

    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? colors.surfaceContainerHigh : colors.surface,
        borderRadius: BorderRadius.circular(
          DesignTokens.componentDeviceListItemRounded,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
          onTap:
              onOpen ??
              () => WorkspaceRoute(deviceId: device.id).push<void>(context),
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
                        Text(
                          deviceName(current),
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: DesignTokens.spacingXs),
                        Wrap(
                          spacing: DesignTokens.spacingXs,
                          runSpacing: DesignTokens.spacingXxs,
                          children: [
                            DeviceStatus(device: current, compact: true),
                            if (current.transport != null)
                              Text(
                                '· ${deviceTransportLabel(current)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingXs),
                  GlassMenuButton(
                    tooltip: '设备操作',
                    icon: const Icon(
                      AppIcons.more,
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
                          canStop ? LucideIcons.unplug : LucideIcons.plug,
                        ),
                        onPressed: pending.value
                            ? null
                            : canStop
                            ? () => run(
                                () =>
                                    stopDeviceConnection(context, ref, device),
                              )
                            : () async {
                                if (starting.value) return;
                                starting.value = true;
                                try {
                                  await offerDeviceConnection(
                                    context,
                                    ref,
                                    ref
                                        .read(deviceListProvider.notifier)
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
                        icon: const Icon(AppIcons.deviceManagement),
                        onPressed: pending.value
                            ? null
                            : () =>
                                  DeviceConnectionRoute(deviceId: device.id)
                                      .push<void>(context),
                      ),
                      GlassMenuAction(
                        label: '移除此设备',
                        icon: const Icon(AppIcons.delete),
                        destructive: true,
                        onPressed: pending.value
                            ? null
                            : () => run(() async {
                                await removeSavedDevice(context, ref, device);
                              }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
