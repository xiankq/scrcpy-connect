import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
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
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(DesignTokens.componentListGroupRounded),
      ),
    );
    // 通知卡（Ardot 37:1111）：内距 16、间距 12；36 应用图标，标题一行、正文最多两行，
    // 时间在右上，可清除时 32 紧凑清除键在右下。
    return Material(
      key: ValueKey('notification-${notification.id}'),
      color: colors.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: opening.value || notification.canOpen == false ? null : open,
        customBorder: shape,
        splashColor: colors.page.withAlpha(0),
        highlightColor: colors.pressed,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.componentCardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignTokens.spacingMd,
            children: [
              Semantics(
                label: appName.isEmpty ? '手机通知' : appName,
                child: packageName.isNotEmpty
                    ? PhoneAppIcon(
                        size: notificationAppIconSize,
                        deviceId: device.id,
                        packageName: packageName,
                        userId: notification.userId,
                      )
                    : SizedBox.square(
                        dimension: notificationAppIconSize,
                        child: Icon(
                          AppIcons.notifications,
                          color: colors.textSecondary,
                        ),
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignTokens.spacingXs,
                  children: [
                    Text(
                      notification.title.isEmpty ? '手机通知' : notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.headline,
                    ),
                    if (notification.body.isNotEmpty)
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.subheadline.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      _trailingMaxWidth *
                      MediaQuery.textScalerOf(context)
                          .scale(1)
                          .clamp(1, _trailingMaxScale),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignTokens.spacingSm,
                  children: [
                    if (timeLabel != null)
                      Text(
                        timeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel:
                            '收到于 ${localizations.formatFullDate(posted!)} $time',
                        style: type.footnote.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    if (notification.canDismiss == true)
                      SolidIconButton(
                        compact: true,
                        tooltip: '清除通知',
                        onPressed: clearing ? null : onClear,
                        icon: AppIcons.close,
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

/// 通知卡的应用图标尺寸（Ardot 通知卡 37:1111「应用图标」36）。
const notificationAppIconSize = 36.0;

/// 时间列最宽 104，随字号最多放大到 1.2 倍，保证正文仍有空间。
const _trailingMaxWidth = 104.0;
const _trailingMaxScale = 1.2;
