import 'package:scrcpy_connect/services/files/file_access.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/file_actions.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FileDetailsPage extends StatelessWidget {
  const FileDetailsPage({
    super.key,
    required this.controller,
    required this.device,
    required this.file,
  });
  final AppController controller;
  final Json device;
  final Json file;
  @override
  Widget build(BuildContext context) {
    final name = value(file, 'name');
    final mime = value(file, 'mime');
    final extension = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : '';
    final (type, icon) = switch (mime) {
      _ when mime.startsWith('image/') => ('图片', LucideIcons.image),
      _ when mime.startsWith('video/') => ('视频', LucideIcons.video),
      _ when mime.startsWith('audio/') => ('音频', LucideIcons.audioLines),
      _ => (extension.isEmpty ? '文件' : '$extension 文件', LucideIcons.fileText),
    };
    final theme = Theme.of(context);
    final accent = ConnectTokens.accent(context, ConnectTokens.amber);
    return PageFrame(
      title: '文件详情',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final symbol = Container(
                      width: DesignTokens.componentEmptyContentIconSize,
                      height: DesignTokens.componentEmptyContentIconSize,
                      decoration: BoxDecoration(
                        color: accent.withValues(
                          alpha: DesignTokens.componentFeatureIconOpacity,
                        ),
                        borderRadius: BorderRadius.circular(
                          DesignTokens.roundedLg,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: DesignTokens.componentIconLargeSize,
                        color: accent,
                      ),
                    );
                    final metadata = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(name, style: theme.textTheme.titleLarge),
                        const SizedBox(height: DesignTokens.spacingXs),
                        Text(
                          '$type · ${bytes(file['size'])}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    );
                    final minimumNameWidth = MediaQuery.textScalerOf(context)
                        .scale(theme.textTheme.titleLarge!.fontSize! * 6);
                    if (constraints.maxWidth -
                            DesignTokens.componentEmptyContentIconSize -
                            DesignTokens.spacingMd <
                        minimumNameWidth) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          symbol,
                          const SizedBox(height: DesignTokens.spacingMd),
                          metadata,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        symbol,
                        const SizedBox(width: DesignTokens.spacingMd),
                        Expanded(child: metadata),
                      ],
                    );
                  },
                ),
                const SizedBox(height: DesignTokens.spacingLg),
                Text('手机上的位置', style: theme.textTheme.bodySmall),
                const SizedBox(height: DesignTokens.spacingSm),
                SelectableText(
                  value(file, 'path'),
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          if (!fileCanOpen(file))
            StateNote(
              fileUnavailableReason(file),
              icon: LucideIcons.circleAlert,
            ),
          const SizedBox(height: DesignTokens.spacingXs),
          FilledButton.icon(
            onPressed: fileCanOpen(file)
                ? () => retrieveFile(context, controller, device, file)
                : null,
            icon: const Icon(
              LucideIcons.download,
              size: DesignTokens.componentIconActionSize,
            ),
            label: const Text('取回原文件'),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          OutlinedButton.icon(
            onPressed: fileCanOpen(file)
                ? () => retrieveFile(
                    context,
                    controller,
                    device,
                    file,
                    share: true,
                  )
                : null,
            icon: const Icon(
              LucideIcons.share2,
              size: DesignTokens.componentIconActionSize,
            ),
            label: const Text('交给系统分享'),
          ),
          const StateNote('取回后可在本机编辑副本；修改后需要主动重新发送，不会自动回写手机。'),
        ],
      ),
    );
  }
}
