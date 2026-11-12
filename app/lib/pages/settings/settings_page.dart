import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readInfo = ref.watch(appInfoReaderProvider);
    final appSettingsError = ref.watch(
      preferencesProvider.select((state) => state.error),
    );
    final body = GroupedListView(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spacingMd,
        DesignTokens.spacingSm,
        DesignTokens.spacingMd,
        DesignTokens.spacingLg,
      ),
      children: [
        if (appSettingsError != null) StateNote('偏好尚未读取：$appSettingsError'),
        SettingsGroup(
          children: [
            ActionRow(
              icon: LucideIcons.sunMoon,
              title: '外观',
              onTap: () => AppearanceRoute().push<void>(context),
            ),
            ActionRow(
              icon: LucideIcons.radio,
              title: '后台与提醒',
              onTap: () => BackgroundRoute().push<void>(context),
            ),
            ActionRow(
              icon: LucideIcons.hardDrive,
              title: '媒体暂存',
              onTap: () => const MediaCacheRoute().push<void>(context),
            ),
            ActionRow(
              icon: LucideIcons.database,
              title: '本地数据',
              onTap: () => DataPreferencesRoute().push<void>(context),
            ),
            ActionRow(
              icon: LucideIcons.keyRound,
              title: '授权密钥',
              onTap: () => const AdbIdentityRoute().push<void>(context),
            ),
            ActionRow(
              icon: LucideIcons.fileText,
              title: '本机运行日志',
              onTap: () => const RuntimeLogsRoute().push<void>(context),
            ),
            ActionRow(
              icon: LucideIcons.info,
              title: '关于邻接',
              onTap: () async {
                try {
                  final info = await readInfo();
                  if (context.mounted &&
                      identical(ref.read(appInfoReaderProvider), readInfo)) {
                    showGlassDialog<void>(
                      context: context,
                      builder: (dialogContext) => GlassAlertDialog(
                        title: const Text('邻接 Interconnect'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(info.version),
                            const SizedBox(height: DesignTokens.spacingMd),
                            const Text('基于设备授权的跨设备互联'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => showLicensePage(
                              context: dialogContext,
                              applicationName: '邻接 Interconnect',
                              applicationVersion: info.version,
                            ),
                            child: Text(
                              MaterialLocalizations.of(dialogContext)
                                  .viewLicensesButtonLabel,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(
                              MaterialLocalizations.of(dialogContext)
                                  .closeButtonLabel,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted &&
                      identical(ref.read(appInfoReaderProvider), readInfo)) {
                    feedback(context, '$e');
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
    return PageFrame(root: embedded, title: '设置', child: body);
  }
}
