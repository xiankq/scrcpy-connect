import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';

import 'transfer_progress.dart';

/// 缩略与格式图形尺寸（design.md「传输」：左侧 48 点缩略或格式图标；Ardot 37:1247）。
const transferThumbnailSize = 48.0;

/// 缩略内的格式图形（Ardot 37:1248）。
const _thumbnailGlyphSize = 24.0;

/// 缩略图解码宽度：48 点按 3 倍屏取像素。
const _thumbnailCacheWidth = 144;

/// 宽窗列表中当前详情对应卡片的描边（Ardot W1 2:2317）。
const _selectedStrokeWidth = 2.0;

/// 进度区上方留白（Ardot 37:1255 上内距 8）。
const _progressTop = DesignTokens.spacingSm;

/// 传输任务的缩略：单张图片有本机文件时用原图缩略，其余用格式色块与白色图形。
class TransferThumbnail extends StatelessWidget {
  const TransferThumbnail({super.key, required this.task, this.group = false});
  final FileTransferSnapshot task;

  /// 文件夹或多项批次显示文件夹图形。
  final bool group;

  @override
  Widget build(BuildContext context) {
    final kind = FileKind.classify(name: task.name);
    final folder = group || task.kind == .directory;
    final glyph = SizedBox.square(
      dimension: transferThumbnailSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: folder
              ? folderKindColor
              : fileKindColor(kind, name: task.name),
          shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(DesignTokens.componentThumbnailRounded),
            ),
          ),
        ),
        child: Icon(
          folder ? folderKindIcon : fileKindIcon(kind),
          size: _thumbnailGlyphSize,
          color: DesignTokens.componentIconTileTextColor,
        ),
      ),
    );
    final path = task.localPath;
    if (folder || kind != FileKind.images || path == null) return glyph;
    return ClipRSuperellipse(
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.componentThumbnailRounded),
      ),
      child: Image.file(
        File(path),
        width: transferThumbnailSize,
        height: transferThumbnailSize,
        fit: BoxFit.cover,
        cacheWidth: _thumbnailCacheWidth,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => glyph,
      ),
    );
  }
}

/// 传输任务卡（Ardot 传输任务卡 37:1268）：`card` 底、圆角 24、内距 16、缩略与内容间距 12。
///
/// 标题行为文件名（`headline`）与右上百分比或状态标签；其下为方向与来源 → 目标（`footnote`），
/// 有进度时显示进度条，最后一行为已传／总量或阶段说明及结束时间。
class TransferTaskCard extends StatelessWidget {
  const TransferTaskCard({
    super.key,
    required this.thumbnail,
    required this.title,
    required this.direction,
    this.status,
    this.showProgress = false,
    this.progress,
    this.detail = '',
    this.detailIssue = false,
    this.time,
    this.selected = false,
    this.onTap,
    this.trailing,
  });
  final Widget thumbnail;
  final String title;
  final String direction;

  /// 右上角百分比文字或 [StatusTag]。
  final Widget? status;
  final bool showProgress;
  final double? progress;
  final String detail;

  /// 说明为失败或待处理原因时用 `error` 着色。
  final bool detailIssue;
  final String? time;
  final bool selected;
  final VoidCallback? onTap;

  /// 卡片尾部的附加操作（如任务菜单）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final secondary = type.footnote.copyWith(color: colors.textSecondary);
    final shape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.componentListGroupRounded),
      ),
      side: selected
          ? BorderSide(color: colors.primary, width: _selectedStrokeWidth)
          : BorderSide.none,
    );
    final footer = detail.isNotEmpty || time != null;
    return Semantics(
      selected: selected,
      child: Material(
        color: colors.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: colors.page.withAlpha(0),
          highlightColor: colors.pressed,
          hoverColor: colors.pressed,
          focusColor: colors.pressed,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              DesignTokens.componentCardPadding,
              DesignTokens.componentCardPadding,
              trailing == null
                  ? DesignTokens.componentCardPadding
                  : DesignTokens.spacingXs,
              DesignTokens.componentCardPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                thumbnail,
                const SizedBox(width: DesignTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: type.headline,
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(width: DesignTokens.spacingSm),
                            Flexible(child: status!),
                          ],
                        ],
                      ),
                      const SizedBox(height: DesignTokens.spacingXs),
                      Text(direction, style: secondary),
                      if (showProgress) ...[
                        const SizedBox(height: _progressTop),
                        TransferProgress(value: progress),
                      ],
                      if (footer) ...[
                        SizedBox(
                          height: showProgress
                              ? DesignTokens.spacingSm
                              : DesignTokens.spacingXs,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                detail,
                                style: detailIssue
                                    ? secondary.copyWith(color: colors.error)
                                    : secondary,
                              ),
                            ),
                            if (time case final time?) ...[
                              const SizedBox(width: DesignTokens.spacingSm),
                              Text(time, style: secondary),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing case final trailing?) ...[
                  const SizedBox(width: DesignTokens.spacingXxs),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 右上角的百分比（Ardot 37:1252：15/20 半粗）。
class TransferPercent extends StatelessWidget {
  const TransferPercent(this.value, {super.key});
  final double value;

  @override
  Widget build(BuildContext context) {
    final type = AppTypography.of(context);
    return Text(
      '${(value * 100).floor()}%',
      textAlign: TextAlign.end,
      style: type.subheadline.copyWith(fontWeight: type.headline.fontWeight),
    );
  }
}
