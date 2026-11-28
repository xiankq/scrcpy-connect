import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/files/file_actions.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/documents/system_file_share_form.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

/// 文件标识卡（Ardot 37:2262）：圆角 28、内距 20、色块与文字间距 16；
/// 前导为详情尺寸的文件格式色块（[FeatureIcon.detailSize]）。
const _identityRounded = DesignTokens.roundedXxl;
const _identityPadding = DesignTokens.spacingXl;
const _identityGap = DesignTokens.spacingLg;

/// 名称与类型之间的间距（Ardot 37:2264「文本」间距 4）。
const _identityTextGap = DesignTokens.spacingXs;

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
        LucideIcons.fileArchive,
      ),
      _ when mime.startsWith('video/') => (
        extension.isEmpty ? '视频' : '$extension 视频',
        LucideIcons.film,
      ),
      _ when mime.startsWith('audio/') => ('音频', LucideIcons.music),
      _ when mime.startsWith('image/') => ('图片', LucideIcons.image),
      _ => (extension.isEmpty ? '文件' : '$extension 文件', LucideIcons.fileText),
    };
    final colors = AppColors.of(context);
    final text = AppTypography.of(context);
    final accent = fileKindColor(
      fileKindOf(file),
      name: file.name,
      mime: file.mime,
    );
    final typeLine = [
      type,
      if (file.size case final size?) fileSizeLabel(size),
    ].join(' · ');
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
      title: '文件详情',
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
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentPagePadding,
        ),
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: colors.card,
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(_identityRounded),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(_identityPadding),
              child: Row(
                children: [
                  FeatureIcon(
                    icon,
                    color: accent,
                    size: FeatureIcon.detailSize,
                  ),
                  const SizedBox(width: _identityGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(name, style: text.title3),
                        const SizedBox(height: _identityTextGap),
                        Text(
                          typeLine,
                          style: text.subheadline.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          SettingsGroup(
            separatorIndent: DesignTokens.componentListRowPadding,
            children: [
              for (final (label, value) in [
                if (file.size case final size?) ('大小', fileSizeLabel(size)),
                if (modified.isNotEmpty)
                  ('修改时间', '${fileModifiedLabel(file)} $modified'),
                ('来源设备', deviceName(device)),
              ])
                AppListRow(title: Text(label), value: value),
              if (file.path case final path?)
                AppListRow(
                  title: const Text('文件位置'),
                  subtitle: SelectableText(path),
                  subtitleMaxLines: 4,
                ),
            ],
          ),
          if (!fileCanOpen(file))
            StateNote(
              fileUnavailableReason(file),
              icon: LucideIcons.circleAlert,
              color: colors.error,
            ),
        ],
      ),
    );
  }
}
