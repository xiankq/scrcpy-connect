import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationReplyPage extends HookWidget {
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
  Widget build(BuildContext context) {
    final draft = useTextEditingController();
    final busy = useState(false);
    final unknown = useState(false);
    final accepted = useState(false);
    final acceptedMessage = useState('');
    final error = useState<String?>(null);
    return PageFrame(
      title: '快捷回复',
      subtitle: '${deviceName(device)} · ${value(notification, 'appName')}',
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
            enabled: !busy.value,
            readOnly: unknown.value || accepted.value,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '回复内容',
              alignLabelWithHint: true,
            ),
          ),
          if (error.value != null)
            StateNote(error.value!, icon: LucideIcons.circleAlert),
          const SizedBox(height: 20),
          if (!unknown.value && !accepted.value)
            FilledButton(
              onPressed: busy.value
                  ? null
                  : () async {
                      if (draft.text.trim().isEmpty) return;
                      busy.value = true;
                      error.value = null;
                      try {
                        final result = await controller.request(
                          'notifications.reply',
                          {
                            'deviceId': device['id'],
                            'notificationId': notification['id'],
                            'text': draft.text,
                          },
                        );
                        if (!context.mounted) return;
                        if (result['status'] == 'acceptedBySystem' ||
                            result['acceptedBySystem'] == true) {
                          accepted.value = true;
                          acceptedMessage.value = value(
                            result,
                            'message',
                            '原应用动作已交给系统；未确认消息送达，不会自动重发。',
                          );
                        } else if (result['status'] == 'unknown') {
                          unknown.value = true;
                        } else if (result['status'] == 'completed' ||
                            result['status'] == 'sent') {
                          feedback(context, '回复已由手机确认提交');
                          closePage<void>(context);
                        } else if (result['status'] == 'failed') {
                          error.value = value(
                            result,
                            'reason',
                            '手机明确返回提交失败，已保留回复草稿。',
                          );
                        } else {
                          error.value = value(
                            result,
                            'reason',
                            '尚未确认回复结果，请在手机上核对',
                          );
                          unknown.value = true;
                        }
                      } catch (e) {
                        if (context.mounted) {
                          error.value = '$e';
                          unknown.value = true;
                        }
                      } finally {
                        if (context.mounted) busy.value = false;
                      }
                    },
              child: Text(busy.value ? '正在提交…' : '发送回复'),
            ),
          if (unknown.value || accepted.value) ...[
            StateNote(
              accepted.value
                  ? acceptedMessage.value
                  : '回复结果尚未确认，已保留提交内容。请先在手机原应用核对，不会自动重发。',
              icon: accepted.value ? LucideIcons.info : LucideIcons.circleAlert,
            ),
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
