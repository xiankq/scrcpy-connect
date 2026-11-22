import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
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
      _ when mime.startsWith('video/') => (
        extension.isEmpty ? '视频' : '$extension 视频',
        LucideIcons.video,
      ),
      _ when mime.startsWith('audio/') => ('音频', LucideIcons.audioLines),
      _ when mime.startsWith('image/') => ('图片', LucideIcons.image),
      _ => (extension.isEmpty ? '文件' : '$extension 文件', LucideIcons.fileText),
    };
    final theme = Theme.of(context);
    final accent = ConnectTokens.accent(
      context,
      fileKindColor(fileKindOf(file), name: file.name, mime: file.mime),
    );
    final seconds = file.modified;
    final modified = seconds == null || seconds <= 0
        ? ''
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            ),
            alwaysUse24HourFormat: true,
          );
    return PageFrame(
      titleStyle: Theme.of(context).textTheme.headlineMedium,
      title: '文件详情',
      backgroundColor: theme.brightness == Brightness.light
          ? DesignTokens.colorFileTile
          : null,
      bottom: GlassActionBar(
        actions: [
          GlassActionBarButton(
            label: '取回原文件',
            icon: const Icon(AppIcons.download),
            onPressed: fileCanOpen(file)
                ? () => retrieveFile(
                    context,
                    ref,
                    device,
                    file,
                    openAfterTransfer: true,
                  )
                : null,
          ),
          if (supportsSystemFileShare)
            GlassActionBarButton(
              label: '分享',
              icon: const Icon(AppIcons.share),
              onPressed: fileCanOpen(file)
                  ? () => retrieveFile(context, ref, device, file, share: true)
                  : null,
            ),
        ],
      ),
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingLg),
        children: [
          ContentPanel(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final symbol = Container(
                  width: DesignTokens.componentEmptyContentIconSize,
                  height: DesignTokens.componentEmptyContentIconSize,
                  decoration: BoxDecoration(
                    color: accent.withValues(
                      alpha: DesignTokens.componentFeatureIconOpacity,
                    ),
                    borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
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
                    Text(type, style: theme.textTheme.bodySmall),
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    symbol,
                    const SizedBox(width: DesignTokens.spacingMd),
                    Expanded(child: metadata),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (label, value) in [
                  if (file.size case final size?) ('大小', fileSizeLabel(size)),
                  if (modified.isNotEmpty)
                    ('修改时间', '${fileModifiedLabel(file)} $modified'),
                  ('来源设备', deviceName(device)),
                ])
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spacingSm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(label, style: theme.textTheme.bodySmall),
                        ),
                        const SizedBox(width: DesignTokens.spacingSm),
                        Expanded(
                          flex: 2,
                          child: Text(value, textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
                if (file.path case final path?) ...[
                  Text('文件位置', style: theme.textTheme.bodySmall),
                  const SizedBox(height: DesignTokens.spacingXs),
                  SelectableText(path, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          if (!fileCanOpen(file))
            StateNote(
              fileUnavailableReason(file),
              icon: LucideIcons.circleAlert,
            ),
        ],
      ),
    );
  }
}
