import 'package:scrcpy_connect/router/navigation.dart';

import 'dart:async';

import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/notification_replies.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationReplyPage extends HookConsumerWidget {
  const NotificationReplyPage({
    super.key,
    required this.controller,
    required this.device,
    required this.notification,
  });
  final AppController controller;
  final Json device;
  final Json notification;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = AppController.notificationReplyKey(
      value(device, 'id'),
      notification,
    );
    final reply =
        ref.watch(
          appControllerProvider.select(
            (state) => state.notificationReplies[key],
          ),
        ) ??
        const NotificationReplyState();
    final pending = ref.watch(
      appControllerProvider.select((state) => state.reconciliationPending),
    );
    final draft = useTextEditingController(text: reply.text, keys: [key]);
    final capacityError = useState<String?>(null);
    final busy = reply.phase == NotificationReplyPhase.submitting;
    final localOnly = notification['localReplyOnly'] == true;
    final guarded = !reply.canEdit || localOnly;
    return PageFrame(
      title: '快捷回复',
      subtitle: value(notification, 'appName').isEmpty
          ? deviceName(device)
          : '${deviceName(device)} · ${value(notification, 'appName')}',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            value(notification, 'title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(value(notification, 'body')),
          const SizedBox(height: 24),
          TextField(
            controller: draft,
            enabled: !busy,
            readOnly: guarded,
            maxLength: 16384,
            onChanged: (text) {
              capacityError.value =
                  controller.updateNotificationReplyDraft(key, text)
                  ? null
                  : '本机保留的回复已达到容量上限，当前内容尚未保留，请复制后到手机上处理。';
            },
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '回复内容',
              alignLabelWithHint: true,
            ),
          ),
          if (capacityError.value != null)
            StateNote(capacityError.value!, icon: LucideIcons.circleAlert),
          if (reply.expired) const StateNote('这条通知已更新或结束，旧回复动作不能再使用。已保留草稿。'),
          if (localOnly && !reply.expired)
            const StateNote('当前无法核验这条通知，以下仅为本机保留的回复。'),
          const SizedBox(height: 20),
          if (!guarded || busy)
            FilledButton(
              onPressed: busy || pending || capacityError.value != null
                  ? null
                  : () => unawaited(controller.submitNotificationReply(key)),
              child: Text(busy ? '正在提交…' : '发送回复'),
            ),
          if (reply.message.isNotEmpty)
            StateNote(
              reply.message,
              icon: reply.phase == NotificationReplyPhase.accepted
                  ? LucideIcons.info
                  : LucideIcons.circleAlert,
            ),
          if (!guarded && !busy && reply.message.isNotEmpty)
            TextButton(
              onPressed: () =>
                  openRemoteRoute(context, deviceId: value(device, 'id')),
              child: const Text('在手机上完成后返回'),
            ),
          if (guarded && !busy) ...[
            FilledButton(
              onPressed: () =>
                  openRemoteRoute(context, deviceId: value(device, 'id')),
              child: const Text('到手机上核对'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: draft.text));
                if (context.mounted) feedback(context, '已复制保留的回复内容');
              },
              icon: const Icon(LucideIcons.copy, size: 18),
              label: const Text('复制保留内容'),
            ),
          ],
          const StateNote('发送前会核验通知是否仍有效。完整对话、新建消息与历史内容请在手机原应用处理。'),
        ],
      ),
    );
  }
}
