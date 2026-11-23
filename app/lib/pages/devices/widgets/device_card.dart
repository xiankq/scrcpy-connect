import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';

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
    final connected = current.status == .connected;
    final inProgress = deviceConnectionInProgress(current);
    final waiting =
        current.status == .offline && hasDeviceConnectionIntent(current);
    final canStop = hasDeviceConnectionIntent(current);
    Future<void> run(Future<void> Function() action) async {
      if (pending.value) return;
      pending.value = true;
      try {
        await action();
      } finally {
        if (context.mounted) pending.value = false;
      }
    }

    Future<void> connect() async {
      if (pending.value || starting.value) return;
      starting.value = true;
      try {
        await startDeviceConnection(context, ref, current);
      } finally {
        if (context.mounted) starting.value = false;
      }
    }

    void stop() => run(() => stopDeviceConnection(context, ref, current));
    void configure() =>
        DeviceConnectionRoute(deviceId: device.id).push<void>(context);
    void remove() => run(() async {
      await removeSavedDevice(context, ref, current);
    });
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final actions = [
      (
        connected
            ? '断开连接'
            : canStop
            ? '停止连接'
            : '开始连接',
        canStop ? LucideIcons.unplug : LucideIcons.plug,
        canStop ? stop : connect,
      ),
      ('连接配置', AppIcons.deviceManagement, configure),
      ('移除此设备', AppIcons.delete, remove),
    ];

    Future<void> openMenu([Offset? position]) async {
      if (pending.value) return;
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final box = context.findRenderObject()! as RenderBox;
      final anchor =
          position ?? box.localToGlobal(box.size.bottomRight(Offset.zero));
      final action = await showMenu<VoidCallback>(
        context: context,
        popUpAnimationStyle: reduceMotionOf(context)
            ? AnimationStyle.noAnimation
            : null,
        position: RelativeRect.fromSize(
          Offset(anchor.dx, anchor.dy) & Size.zero,
          overlay.size,
        ),
        items: [
          for (final (label, icon, action) in actions)
            PopupMenuItem(
              value: action,
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: DesignTokens.componentIconSmallSize,
                    color: label == '移除此设备' ? colors.error : null,
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
                  Flexible(child: Text(label)),
                ],
              ),
            ),
        ],
      );
      if (context.mounted) action?.call();
    }

    final status = switch (current.status) {
      .failed => '连接失败',
      _ => deviceStatusText(current),
    };
    String? detail;
    if (current.lastSeen case final last?
        when current.status == .offline && last > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(last * 1000);
      final today = DateUtils.dateOnly(DateTime.now());
      final day = DateUtils.dateOnly(date);
      final time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(date),
        alwaysUse24HourFormat: true,
      );
      detail = day == today
          ? '今天 $time'
          : day == DateTime(today.year, today.month, today.day - 1)
          ? '昨天 $time'
          : '${date.month}/${date.day} $time';
    } else if (current.transport != null) {
      detail = deviceTransportLabel(current);
    }
    final identity = DeviceIdentity(device: current, compact: compact);
    final labels = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          deviceName(current),
          style: theme.textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: DesignTokens.spacingXxs),
        Text(
          detail == null ? status : '$status · $detail',
          style: theme.textTheme.bodySmall?.copyWith(
            color: switch (current.status) {
              .failed => colors.error,
              .unauthorized => DesignTokens.componentConnectionIconUsbTextColor,
              _ => colors.onSurfaceVariant,
            },
          ),
        ),
      ],
    );
    final action = FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(
          DesignTokens.componentDeviceListActionWidth,
          DesignTokens.componentDeviceListActionHeight,
        ),
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXs),
        backgroundColor: connected
            ? dark
                  ? DesignTokens.colorAccentBlueSoftDark
                  : DesignTokens.colorAccentBlueSoft
            : dark
            ? DesignTokens.colorDevicePanelDark
            : DesignTokens.colorDevicePanel,
        foregroundColor: connected
            ? dark
                  ? DesignTokens.colorConnectionTrackArcDark
                  : DesignTokens.componentDeviceListOpenTextColor
            : colors.onSurface,
        shape: const StadiumBorder(),
        textStyle: theme.textTheme.labelLarge,
      ),
      onPressed: pending.value || starting.value && !inProgress
          ? null
          : connected
          ? () => openRemoteRoute(context, deviceId: device.id)
          : inProgress || waiting
          ? stop
          : connect,
      child: Text(switch (current.status) {
        .connected => '打开屏幕',
        _ when starting.value && !inProgress => '正在连接',
        .failed => '重试',
        .unauthorized => '重新授权',
        _ when inProgress || waiting => '停止连接',
        _ => '连接',
      }),
    );

    return Semantics(
      selected: selected,
      customSemanticsActions: {
        const CustomSemanticsAction(label: '设备操作'): openMenu,
      },
      child: Material(
        color: selected ? colors.surfaceContainerHigh : colors.surface,
        borderRadius: BorderRadius.circular(
          DesignTokens.componentDeviceListItemRounded,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              onOpen ??
              () => WorkspaceRoute(deviceId: device.id).push<void>(context),
          onLongPress: openMenu,
          onSecondaryTapUp: (details) => openMenu(details.globalPosition),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: compact
                  ? DesignTokens.componentDeviceListItemCompactHeight
                  : DesignTokens.componentDeviceListItemHeight,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignTokens.componentDeviceListItemPadding,
                vertical: compact
                    ? DesignTokens.spacingXs
                    : DesignTokens.spacingMd,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  return Row(
                    children: [
                      identity,
                      const SizedBox(width: DesignTokens.spacingMd),
                      if (constraints.maxWidth / scale < 250)
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              labels,
                              const SizedBox(height: DesignTokens.spacingXs),
                              action,
                            ],
                          ),
                        )
                      else ...[
                        Expanded(child: labels),
                        const SizedBox(width: DesignTokens.spacingXs),
                        action,
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
