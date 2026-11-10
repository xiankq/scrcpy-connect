import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class NotificationCard extends HookWidget {
  const NotificationCard({
    super.key,
    required this.controller,
    required this.device,
    required this.notification,
    required this.clearing,
    required this.onClear,
  });

  final AppStore controller;
  final Json device;
  final Json notification;
  final bool clearing;
  final VoidCallback onClear;

  Future<void> _open(BuildContext context) async {
    try {
      final result = await controller.request('notifications.open', {
        'deviceId': device['id'],
        'notificationId': notification['id'],
      });
      if (!context.mounted) return;
      if (result['located'] != true) {
        feedback(context, value(result, 'message', '未能定位原内容，将打开手机界面'));
      }
    } catch (error) {
      if (!context.mounted) return;
      feedback(context, '$error');
      if (error is! RequestFailure || error.code != 'authentication_required') {
        return;
      }
    }
    if (context.mounted) {
      await openRemoteRoute(context, deviceId: value(device, 'id'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final opening = useState(false);
    final appName = value(notification, 'appName').trim();
    final packageName = value(notification, 'packageName');
    final timestamp = notification['postedAt'];
    final posted =
        timestamp is int && timestamp > 0 && timestamp <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final time = posted == null
        ? null
        : localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(posted),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final sameDay =
        posted != null &&
        posted.year == now.year &&
        posted.month == now.month &&
        posted.day == now.day;
    final elapsed = posted == null ? null : now.difference(posted);
    final timeLabel = posted == null
        ? null
        : elapsed != null && !elapsed.isNegative && elapsed.inMinutes < 1
        ? '现在'
        : elapsed != null && !elapsed.isNegative && elapsed.inHours < 1
        ? '${elapsed.inMinutes}分钟前'
        : sameDay
        ? time
        : '${localizations.formatShortMonthDay(posted)} · $time';
    return ContentPanel(
      key: ValueKey('notification-${value(notification, 'id')}'),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: opening.value || notification['canOpen'] == false
              ? null
              : () async {
                  opening.value = true;
                  try {
                    await _open(context);
                  } finally {
                    if (context.mounted) opening.value = false;
                  }
                },
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.componentNotificationCardHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: DesignTokens.componentButtonSecondaryHeight,
                    ),
                    child: Row(
                      children: [
                        if (packageName.isNotEmpty)
                          SizedBox.square(
                            dimension: DesignTokens.componentSmallButtonSize,
                            child: FittedBox(
                              child: PhoneAppIcon(
                                controller: controller,
                                deviceId: value(device, 'id'),
                                packageName: packageName,
                                userId: notification['userId'] == null
                                    ? null
                                    : value(notification, 'userId'),
                              ),
                            ),
                          )
                        else
                          const Icon(
                            LucideIcons.imageOff,
                            semanticLabel: '图标暂不可用',
                          ),
                        const SizedBox(width: DesignTokens.spacingSm),
                        Expanded(
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: DesignTokens.spacingSm,
                            runSpacing: DesignTokens.spacingXxs,
                            children: [
                              Text(
                                appName.isEmpty || appName == packageName
                                    ? '手机通知'
                                    : appName,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (timeLabel != null)
                                Text(
                                  timeLabel,
                                  semanticsLabel:
                                      '收到于 ${localizations.formatFullDate(posted!)} $time',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (value(notification, 'title').isNotEmpty) ...[
                    const SizedBox(height: DesignTokens.spacingSm),
                    Text(
                      value(notification, 'title'),
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (value(notification, 'body').isNotEmpty) ...[
                    const SizedBox(height: DesignTokens.spacingTight),
                    Text(
                      value(notification, 'body'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  if (value(notification, 'title').isEmpty &&
                      value(notification, 'body').isEmpty) ...[
                    const SizedBox(height: DesignTokens.spacingTight),
                    Text(
                      '此通知未提供预览内容',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (notification['canOpen'] == false)
                    const StateNote('此通知的原始动作已不可用，请在手机原应用中处理。'),
                  if (notification['canDismiss'] is bool) ...[
                    const SizedBox(height: DesignTokens.spacingSm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DesignTokens.componentButtonSecondaryHeight,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: DesignTokens.spacingSm,
                          runSpacing: DesignTokens.spacingXxs,
                          children: [
                            if (notification['canDismiss'] == true)
                              GlassTooltip(
                                message: '清除通知',
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      DesignTokens.componentIconButtonSize,
                                      DesignTokens.componentIconButtonSize,
                                    ),
                                  ),
                                  onPressed: clearing ? null : onClear,
                                  icon: const Icon(
                                    LucideIcons.checkCheck,
                                    size: DesignTokens.componentIconSmallSize,
                                  ),
                                  label: const Text('清除通知'),
                                ),
                              )
                            else if (notification['canDismiss'] == false)
                              Text(
                                '手机系统将此项标为不可清除，请在原应用中处理。',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
