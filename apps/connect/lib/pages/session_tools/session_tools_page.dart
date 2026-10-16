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

class SessionToolsPage extends StatelessWidget {
  const SessionToolsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '屏幕与输入工具',
    subtitle: deviceName(device),
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ActionRow(
          icon: LucideIcons.camera,
          title: '截取当前画面',
          subtitle: '保存结果以设备实际反馈为准',
          color: ConnectTokens.coral,
          onTap: () async {
            final result = await perform(
              context,
              controller,
              'session.screenshot',
              {'deviceId': device['id']},
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
                              '截图已保存',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 260),
                              child: Image.file(
                                File(path),
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              path,
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
            onTap: () async {
              final result = await perform(
                context,
                controller,
                'session.screen',
                {'deviceId': device['id'], 'mode': option.$1},
              );
              if (result != null && context.mounted) {
                feedback(context, value(result, 'message', '设备已返回屏幕操作结果'));
              }
            },
          ),
        ActionRow(
          icon: LucideIcons.rotateCw,
          title: '旋转远端画面',
          onTap: () => perform(context, controller, 'session.rotate', {
            'deviceId': device['id'],
          }),
        ),
        const SectionTitle('导航与文字'),
        ActionRow(
          icon: LucideIcons.keyboard,
          title: '使用本机键盘',
          subtitle: '打开全屏画面，再点选远端输入框',
          onTap: () => openRemoteRoute(
            context,
            deviceId: value(device, 'id'),
            requestKeyboard: true,
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final option in const [(4, '返回'), (3, '主屏幕'), (187, '最近任务')])
              OutlinedButton(
                onPressed: () async {
                  await perform(context, controller, 'session.key', {
                    'deviceId': device['id'],
                    'keyCode': option.$1,
                    'action': 'down',
                  });
                  if (context.mounted) {
                    await perform(context, controller, 'session.key', {
                      'deviceId': device['id'],
                      'keyCode': option.$1,
                      'action': 'up',
                    });
                  }
                },
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
              await perform(context, controller, 'session.text', {
                'deviceId': device['id'],
                'text': text,
              });
            }
          },
        ),
        ActionRow(
          icon: LucideIcons.clipboard,
          title: '剪贴板',
          onTap: () => ClipboardRoute().push<void>(context),
        ),
      ],
    ),
  );
}
