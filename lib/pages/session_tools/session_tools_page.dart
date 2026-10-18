import 'package:scrcpy_connect/router/remote_control_intent.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

class SessionToolsPage extends HookWidget {
  const SessionToolsPage({
    super.key,
    required this.controller,
    required this.device,
    this.sessionId,
  });
  final AppController controller;
  final Json device;
  final String? sessionId;
  @override
  Widget build(BuildContext context) {
    final selected = useState(sessionId);
    return PageFrame(
      title: '屏幕与输入工具',
      subtitle: deviceName(device),
      child: CommandView(
        controller: controller,
        command: 'session.list',
        params: {'deviceId': device['id']},
        builder: (context, data, refresh) {
          final sessions = objects(data['sessions'])
              .where(
                (item) =>
                    item['deviceId'] == device['id'] &&
                    item['status'] != 'stopped',
              )
              .toList();
          if (selected.value == null) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const StateNote('选择要操作的窗口。截图和输入只会作用于所选会话。'),
                for (final session in sessions)
                  ActionRow(
                    icon: LucideIcons.appWindow,
                    title: value(session, 'name', '手机屏幕'),
                    subtitle: statusText(value(session, 'status')),
                    onTap: () => selected.value = value(
                      session,
                      'sessionId',
                      value(session, 'id'),
                    ),
                  ),
                if (sessions.isEmpty)
                  ActionRow(
                    icon: LucideIcons.smartphone,
                    title: '打开手机屏幕',
                    onTap: () =>
                        openRemoteRoute(context, deviceId: value(device, 'id')),
                  ),
              ],
            );
          }
          final matches = sessions.where(
            (item) =>
                value(item, 'sessionId', value(item, 'id')) == selected.value,
          );
          if (matches.isEmpty) {
            return EmptyContent(
              icon: LucideIcons.appWindow,
              title: '这个窗口已结束',
              message: '重新选择已有窗口，不会自动创建或操作其他会话。',
              action: TextButton(
                onPressed: () {
                  selected.value = null;
                  refresh();
                },
                child: const Text('选择其他窗口'),
              ),
            );
          }
          return tools(context, matches.first);
        },
      ),
    );
  }

  Widget tools(BuildContext context, Json session) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      StateNote('当前窗口：${value(session, 'name', '手机屏幕')}。操作屏幕或输入时会进入该窗口的全屏画面。'),
      ActionRow(
        icon: LucideIcons.camera,
        title: '截取当前画面',
        subtitle: session['status'] == 'paused'
            ? '窗口已暂停，将截取最后显示的画面'
            : '截取所选窗口的画面',
        color: ConnectTokens.coral,
        onTap: () async {
          final result = await perform(
            context,
            controller,
            'session.screenshot',
            {'sessionId': value(session, 'sessionId', value(session, 'id'))},
          );
          if (result != null && context.mounted) {
            final path = value(result, 'localPath');
            if (path.isNotEmpty) {
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => SafeArea(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '截图已生成',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: Image.file(File(path), fit: BoxFit.contain),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '图片暂存在本App内。通过系统分享交给其他应用，清理或卸载本App可能移除这份副本。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => perform(
                              context,
                              controller,
                              'files.open',
                              {'localPath': path},
                            ),
                            icon: const Icon(
                              LucideIcons.externalLink,
                              size: 18,
                            ),
                            label: const Text('用本机应用打开'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await SharePlus.instance.share(
                                  ShareParams(files: [XFile(path)]),
                                );
                              } catch (error) {
                                if (context.mounted) {
                                  feedback(context, '系统分享失败：$error');
                                }
                              }
                            },
                            icon: const Icon(LucideIcons.share2, size: 18),
                            label: const Text('系统分享'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              return;
            }
            feedback(
              context,
              value(result, 'localPath').isEmpty
                  ? value(result, 'message', '尚未获得保存位置，请检查实际结果')
                  : '已保存至 ${value(result, 'localPath')}',
            );
          }
        },
      ),
      const SectionTitle('被控手机实体屏幕'),
      const StateNote('打开远控画面与点亮实体屏幕是不同操作，不会因通知接续自动点亮。'),
      for (final option in const [
        ('off', '关闭实体屏幕', LucideIcons.moon),
        ('on', '点亮实体屏幕', LucideIcons.sun),
      ])
        ActionRow(
          icon: option.$3,
          title: option.$2,
          onTap: () => openRemoteRoute(
            context,
            deviceId: value(device, 'id'),
            sessionId: value(session, 'sessionId', value(session, 'id')),
            action: RemoteControlIntent.screen(option.$1),
          ),
        ),
      ActionRow(
        icon: LucideIcons.rotateCw,
        title: '旋转远端画面',
        onTap: () => openRemoteRoute(
          context,
          deviceId: value(device, 'id'),
          sessionId: value(session, 'sessionId', value(session, 'id')),
          action: const RemoteControlIntent.rotate(),
        ),
      ),
      const SectionTitle('导航与文字'),
      ActionRow(
        icon: LucideIcons.keyboard,
        title: '使用本机键盘',
        subtitle: '打开全屏画面，再点选远端输入框',
        onTap: () => openRemoteRoute(
          context,
          deviceId: value(device, 'id'),
          sessionId: value(session, 'sessionId', value(session, 'id')),
          requestKeyboard: true,
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final option in const [(4, '返回'), (3, '主屏幕'), (187, '最近任务')])
            OutlinedButton(
              onPressed: () => openRemoteRoute(
                context,
                deviceId: value(device, 'id'),
                sessionId: value(session, 'sessionId', value(session, 'id')),
                action: RemoteControlIntent.key(option.$1),
              ),
              child: Text(option.$2),
            ),
        ],
      ),
      const SizedBox(height: 12),
      ActionRow(
        icon: LucideIcons.keyboard,
        title: '发送文字',
        subtitle: '敏感或受保护的输入框可能不允许粘贴',
        onTap: () async {
          final text = await askText(
            context,
            title: '发送到 ${deviceName(device)}',
            label: '文字内容',
            action: '发送',
            lines: 3,
          );
          if (text != null && context.mounted) {
            await openRemoteRoute(
              context,
              deviceId: value(device, 'id'),
              sessionId: value(session, 'sessionId', value(session, 'id')),
              action: RemoteControlIntent.text(text),
            );
          }
        },
      ),
      ActionRow(
        icon: LucideIcons.clipboard,
        title: '剪贴板',
        onTap: () => ClipboardRoute().push<void>(context),
      ),
    ],
  );
}
