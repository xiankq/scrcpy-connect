import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final AppController controller;
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettingsError = ref.watch(
      appControllerProvider.select((state) => state.settingsError),
    );
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final body = ListView(
      padding: EdgeInsets.fromLTRB(
        24,
        embedded ? 30 : 12,
        24,
        embedded ? 120 : 24,
      ),
      children: [
        if (embedded) ...[
          Text('设置', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 24),
        ],
        if (appSettingsError != null) StateNote('偏好尚未读取：$appSettingsError'),
        ContentPanel(
          child: Column(
            children: [
              ActionRow(
                icon: LucideIcons.sunMoon,
                title: '外观与易用性',
                subtitle: '浅色、深色、透明度与动态效果',
                onTap: () => AppearanceRoute().push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.audioLines,
                title: '设备音源',
                subtitle: '跟随当前设备、固定音源或主动混音',
                onTap: () => AudioRoute().push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.clipboard,
                title: '剪贴板同步',
                subtitle: appSettings['clipboardSync'] == true
                    ? '已开启 · 仅同步选定设备'
                    : '默认关闭 · 可主动发送与获取',
                onTap: () => ClipboardRoute().push<void>(context),
              ),
            ],
          ),
        ),
        const SectionTitle('连接与活动'),
        ContentPanel(
          child: Column(
            children: [
              ActionRow(
                icon: LucideIcons.radio,
                title: '后台与连接',
                subtitle: '按系统许可维持已启用的活动',
                onTap: () => BackgroundRoute().push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.activity,
                title: '当前活动',
                subtitle: '分别查看连接、画面、传输、声音与通话',
                onTap: () => ActivitiesRoute().push<void>(context),
              ),
            ],
          ),
        ),
        const SectionTitle('本机数据'),
        ActionRow(
          icon: LucideIcons.hardDrive,
          title: '媒体暂存',
          subtitle: '查看空间占用，清理不再使用的预览与原件',
          onTap: () => const MediaCacheRoute().push<void>(context),
        ),
        ActionRow(
          icon: LucideIcons.database,
          title: '设备记录与恢复',
          subtitle: '名称与偏好可以恢复，授权身份留在本机',
          onTap: () => DataPreferencesRoute().push<void>(context),
        ),
        const SizedBox(height: 24),
        const StateNote('邻接 · 让手边的屏幕接续另一台手机。\n被控手机免安装，本机无需开启调试。'),
        TextButton(
          onPressed: () async {
            try {
              final info = await controller.request('system.info');
              if (context.mounted) {
                showAboutDialog(
                  context: context,
                  applicationName: '邻接 Interconnect',
                  applicationVersion: value(info, 'version', '开发版本'),
                  children: [Text(value(info, 'description', '基于设备授权的跨设备互联'))],
                );
              }
            } catch (e) {
              if (context.mounted) feedback(context, '$e');
            }
          },
          child: const Text('关于邻接'),
        ),
      ],
    );
    if (embedded) {
      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight / 2,
                ),
                child: const RecoveryStatus(),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }
    return PageFrame(title: '设置', child: body);
  }
}
