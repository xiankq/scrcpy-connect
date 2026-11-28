import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content/media_thumbnail.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/form_controls.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';

/// 宫格缩略项（Ardot 37:2067）：card 底、圆角 16，内距 4/4/4/8，缩略区与文字间距 4。
const _gridTilePadding = EdgeInsets.fromLTRB(
  DesignTokens.spacingXs,
  DesignTokens.spacingXs,
  DesignTokens.spacingXs,
  DesignTokens.spacingSm,
);
const _gridTileRounded = DesignTokens.roundedMd;

/// 缩略区内的格式线形图形（Ardot 37:2031：32 点）。
const _gridGlyphSize = DesignTokens.spacingXxxl;

/// 视频与不可用标识距缩略区边 6。
const _gridMarkInset = 6.0;

/// 不可用说明图形与 footnote 行高对齐。
const _noteGlyphSize = DesignTokens.componentChevronSize;

class FolderListTile extends StatelessWidget {
  const FolderListTile({
    super.key,
    required this.folder,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final FileCatalogEntry folder;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final date = fileModifiedLabel(folder);
    return AppListRow(
      selected: selected,
      leading: const ListIconBadge(
        icon: folderKindIcon,
        backgroundColor: folderKindColor,
      ),
      title: Text(folder.name),
      titleMaxLines: 2,
      subtitle: date.isEmpty ? null : Text(date),
      trailing: selectionActive
          ? _ListSelectionSlot(
              selected: selected,
              enabled: fileCanManage(folder),
            )
          : null,
      chevron: !selectionActive,
      onTap: fileCanOpen(folder) || selectionActive ? onTap : null,
      onLongPress: onLongPress,
    );
  }
}

class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.file,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final FileCatalogEntry file;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final kind = fileKindOf(file);
    final openable = fileCanOpen(file);
    final date = fileRecentModifiedLabel(file);
    final numericSize = file.size ?? 0;
    final detail = [
      if (date.isNotEmpty) date,
      if (numericSize > 0) fileSizeLabel(numericSize),
    ].join(' · ');
    final unavailableReason = openable ? null : fileUnavailableReason(file);
    return AppListRow(
      selected: selected,
      leading: ListIconBadge(
        icon: fileKindIcon(kind),
        backgroundColor: fileKindColor(kind, name: file.name, mime: file.mime),
      ),
      title: Tooltip(
        triggerMode: TooltipTriggerMode.manual,
        message: (file.path ?? ''),
        child: Text(file.name),
      ),
      titleMaxLines: 2,
      subtitle: unavailableReason != null
          ? FileUnavailableNote(unavailableReason)
          : detail.isEmpty
          ? null
          : Text(detail),
      trailing: selectionActive
          ? _ListSelectionSlot(selected: selected, enabled: fileCanManage(file))
          : null,
      chevron: !selectionActive,
      onTap: openable || selectionActive ? onTap : null,
      onLongPress: onLongPress,
    );
  }
}

/// 不可用条目的原因：错误色图形 + 次要色说明（design.md「文字与状态」）。
class FileUnavailableNote extends StatelessWidget {
  const FileUnavailableNote(this.reason, {super.key, this.center = false});
  final String reason;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: DesignTokens.spacingXs,
              ),
              child: Icon(
                LucideIcons.circleAlert,
                size: _noteGlyphSize,
                color: colors.error,
              ),
            ),
          ),
          TextSpan(text: reason),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: center ? TextAlign.center : TextAlign.start,
    );
  }
}

/// 列表选择标记与箭头共用 22 点尾槽，切换选择态时文字宽度不变。
class _ListSelectionSlot extends StatelessWidget {
  const _ListSelectionSlot({required this.selected, required this.enabled});
  final bool selected, enabled;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: listRowTrailingSlot,
    child: SelectionMark(selected: selected, enabled: enabled),
  );
}

class FolderGridTile extends StatelessWidget {
  const FolderGridTile({
    super.key,
    required this.folder,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final FileCatalogEntry folder;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final openable = fileCanOpen(folder);
    final manageable = fileCanManage(folder);
    final date = fileModifiedLabel(folder);
    return _GridTile(
      semanticsLabel: '${folder.name}\n${(folder.path ?? '')}',
      button: openable || manageable,
      selected: selected,
      onTap: openable || selectionActive ? onTap : null,
      onLongPress: onLongPress,
      thumbnail: const _GridGlyph(icon: folderKindIcon, color: folderKindColor),
      mark: selectionActive && manageable
          ? SelectionMark(selected: selected, overlay: true)
          : null,
      name: folder.name,
      tooltip: folder.path ?? '',
      meta: date.isEmpty ? null : Text(date),
    );
  }
}

class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.device,
    required this.file,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final DeviceSnapshot device;
  final FileCatalogEntry file;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final kind = fileKindOf(file);
    final openable = fileCanOpen(file);
    final manageable = fileCanManage(file);
    final unavailableReason = openable ? null : fileUnavailableReason(file);
    final media =
        (kind == FileKind.images || kind == FileKind.videos) && openable;
    return _GridTile(
      semanticsLabel: '${file.name}\n${(file.path ?? '')}',
      button: openable || manageable,
      selected: selected,
      onTap: openable || selectionActive ? onTap : null,
      onLongPress: onLongPress,
      thumbnail: Stack(
        fit: StackFit.expand,
        children: [
          if (media)
            MediaThumbnail(
              name: file.name,
              path: (file.path ?? ''),
              device: device,
              compact: true,
            )
          else
            _GridGlyph(
              icon: fileKindIcon(kind),
              color: fileKindColor(kind, name: file.name, mime: file.mime),
            ),
          if (kind == FileKind.videos && openable)
            const PositionedDirectional(
              start: _gridMarkInset,
              bottom: _gridMarkInset,
              child: Icon(
                LucideIcons.play,
                color: DesignTokens.colorOnMedia,
                size: DesignTokens.componentSectionGlyphSize,
              ),
            ),
          if (!openable)
            PositionedDirectional(
              start: _gridMarkInset,
              bottom: _gridMarkInset,
              child: Icon(
                LucideIcons.circleAlert,
                color: colors.error,
                size: DesignTokens.componentSectionGlyphSize,
              ),
            ),
        ],
      ),
      mark: selectionActive && manageable
          ? SelectionMark(selected: selected, overlay: true)
          : null,
      name: file.name.isEmpty ? '未命名文件' : file.name,
      tooltip: file.path ?? fileUnavailableReason(file),
      meta: unavailableReason != null
          ? Text(unavailableReason, maxLines: 2)
          : Text(fileSizeLabel(file.size)),
    );
  }
}

class _GridGlyph extends StatelessWidget {
  const _GridGlyph({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(icon, size: _gridGlyphSize, color: color),
  );
}

/// 宫格缩略项：缩略区为 `block` 底、圆角 8；叠放选择标记居中于缩略区（Ardot 选择标记 · 叠放 44:5）；
/// 名称 `footnote`、元数据 `caption` + `text-secondary`，居中。
class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.semanticsLabel,
    required this.button,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.thumbnail,
    required this.mark,
    required this.name,
    required this.tooltip,
    required this.meta,
  });

  final String semanticsLabel;
  final bool button, selected;
  final VoidCallback? onTap, onLongPress;
  final Widget thumbnail;
  final Widget? mark;
  final String name, tooltip;
  final Widget? meta;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const tileShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(_gridTileRounded)),
    );
    return Semantics(
      label: semanticsLabel,
      button: button,
      selected: selected,
      child: Material(
        color: colors.card,
        shape: tileShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: tileShape,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.focused) ||
                    states.contains(WidgetState.hovered)
                ? colors.pressed
                : colors.page.withAlpha(0),
          ),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: _gridTilePadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRSuperellipse(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(DesignTokens.componentThumbnailRounded),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.block, child: thumbnail),
                        if (mark case final mark?) Center(child: mark),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXs),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingXs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Tooltip(
                        triggerMode: TooltipTriggerMode.manual,
                        message: tooltip,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: type.footnote,
                        ),
                      ),
                      if (meta case final meta?)
                        DefaultTextStyle.merge(
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          child: meta,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
