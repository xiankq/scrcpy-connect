import 'package:scrcpy_connect/widgets/root_page_header.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
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
    final body = GroupedListView(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        embedded ? DesignTokens.spacingZero : DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        embedded ? 120 : DesignTokens.spacingLg,
      ),
      children: [
        if (embedded) ...[
          const RootPageHeader(title: '设置'),
          const SizedBox(height: DesignTokens.spacingSm),
        ],
        if (appSettingsError != null) StateNote('偏好尚未读取：$appSettingsError'),
        ContentPanel(
          child: Column(
            children: [
              ActionRow(
                icon: LucideIcons.sunMoon,
                title: '外观',
                onTap: () => AppearanceRoute().push<void>(context),
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
                onTap: () => BackgroundRoute().push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.activity,
                title: '当前活动',
                onTap: () => ActivitiesRoute().push<void>(context),
              ),
            ],
          ),
        ),
        const SectionTitle('本机数据'),
        ActionRow(
          icon: LucideIcons.hardDrive,
          title: '媒体暂存',

          onTap: () => const MediaCacheRoute().push<void>(context),
        ),
        ActionRow(
          icon: LucideIcons.database,
          title: '设备记录与恢复',

          onTap: () => DataPreferencesRoute().push<void>(context),
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        TextButton(
          onPressed: () async {
            try {
              final info = await controller.execute(InteropCommand.systemInfo);
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
