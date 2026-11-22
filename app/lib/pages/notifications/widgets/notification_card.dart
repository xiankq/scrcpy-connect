import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

class NotificationCard extends HookConsumerWidget {
  const NotificationCard({
    super.key,
    required this.device,
    required this.notification,
    required this.clearing,
    required this.onClear,
  });

  final DeviceSnapshot device;
  final DeviceNotification notification;
  final bool clearing;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(deviceNotificationsProvider);
    final opening = useValueNotifier(false, [
      notifications,
      device.id,
      notification.id,
    ]);
    useListenable(opening);
    final currentOpening = useRef(opening);
    currentOpening.value = opening;
    bool isCurrent() =>
        context.mounted &&
        identical(currentOpening.value, opening) &&
        identical(notifications, ref.read(deviceNotificationsProvider));
    Future<void> open() async {
      if (opening.value || !isCurrent()) return;
      opening.value = true;
      try {
        try {
          final result = await notifications.openNotification(
            device.id,
            notification.id,
          );
          if (!context.mounted || !isCurrent()) return;
          if (!result.located) {
            feedback(context, '找不到这条通知的原内容。你可以打开手机屏幕查看。');
          }
        } catch (error) {
          if (!context.mounted || !isCurrent()) return;
          feedback(
            context,
            failureMessage(error, fallback: '无法在手机上打开这条通知。请解锁手机后再试。'),
          );
          if (error is! RequestFailure ||
              error.code != 'authentication_required') {
            return;
          }
        }
        if (context.mounted && isCurrent()) {
          await openRemoteRoute(context, deviceId: device.id);
        }
      } finally {
        if (isCurrent()) opening.value = false;
      }
    }

    final appName = notification.appName.trim();
    final packageName = notification.packageName;
    final posted = notification.postedTime;
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final time = posted == null
        ? null
        : localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(posted),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final elapsed = posted == null ? null : now.difference(posted);
    final timeLabel = posted == null
        ? null
        : elapsed != null && !elapsed.isNegative && elapsed.inMinutes < 1
        ? '现在'
        : elapsed != null && !elapsed.isNegative && elapsed.inHours < 1
        ? '${elapsed.inMinutes}分钟前'
        : time;
    final theme = Theme.of(context);
    return ContentPanel(
      key: ValueKey('notification-${notification.id}'),
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: opening.value || notification.canOpen == false ? null : open,
        borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spacingMd,
            DesignTokens.spacingSm,
            DesignTokens.spacingSm,
            DesignTokens.spacingSm,
          ),
          child: Row(
            children: [
              Semantics(
                label: appName.isEmpty ? '手机通知' : appName,
                child: packageName.isNotEmpty
                    ? PhoneAppIcon(
                        size: DesignTokens.componentNotificationAppIconSize,
                        deviceId: device.id,
                        packageName: packageName,
                        userId: notification.userId,
                      )
                    : const Icon(LucideIcons.bell),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notification.title.isEmpty ? '手机通知' : notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (notification.body.isNotEmpty)
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      104 *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (timeLabel != null)
                      Text(
                        timeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel:
                            '收到于 ${localizations.formatFullDate(posted!)} $time',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (notification.canDismiss == true)
                      IconButton(
                        tooltip: '清除通知',
                        onPressed: clearing ? null : onClear,
                        icon: const Icon(
                          LucideIcons.x,
                          size: DesignTokens.componentIconSmallSize,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
