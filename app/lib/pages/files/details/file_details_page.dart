import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/utils/formatters.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class FileDetailsPage extends ConsumerWidget {
  const FileDetailsPage({super.key, required this.device, required this.file});
  final DeviceSnapshot device;
  final FileCatalogEntry file;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = file.name;
    final mime = file.mime;
    final extension = name.contains('.')
        ? name.split('.').last.toUpperCase()
        : '';
    final (type, icon) = switch (mime) {
      _ when mime == 'application/pdf' => ('PDF 文件', LucideIcons.fileText),
      _ when const {'ZIP', 'RAR', '7Z', 'GZ'}.contains(extension) => (
        '压缩包',
        LucideIcons.archive,
      ),
      _ when mime.startsWith('video/') => ('视频', LucideIcons.video),
      _ when mime.startsWith('audio/') => ('音频', LucideIcons.audioLines),
      _ => (extension.isEmpty ? '文件' : '$extension 文件', LucideIcons.fileText),
    };
    final theme = Theme.of(context);
    final accent = ConnectTokens.accent(context, switch (icon) {
      LucideIcons.archive => ConnectTokens.amber,
      LucideIcons.audioLines => DesignTokens.colorListIconSlate,
      LucideIcons.video => DesignTokens.colorListIconPurple,
      _ => DesignTokens.colorListIconDocument,
    });
    return PageFrame(
      title: '文件详情',
      bottom: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: DesignTokens.spacingSm,
        children: [
          TextButton.icon(
            onPressed: fileCanOpen(file)
                ? () => retrieveFile(
                    context,
                    ref,
                    device,
                    file,
                    openAfterTransfer: true,
                  )
                : null,
            icon: const Icon(LucideIcons.download),
            label: const Text('取回文件'),
          ),
          if (supportsSystemFileShare)
            TextButton.icon(
              onPressed: fileCanOpen(file)
                  ? () => retrieveFile(context, ref, device, file, share: true)
                  : null,
              icon: const Icon(LucideIcons.share2),
              label: const Text('分享'),
            ),
        ],
      ),
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
                          '$type · ${bytes(file.size)}',
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
                  (file.path ?? ''),
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
          const StateNote('取回后可在本机编辑副本；修改后需要主动重新发送，不会自动回写手机。'),
        ],
      ),
    );
  }
}
