import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/media_thumbnail.dart';

class FolderListTile extends StatelessWidget {
  const FolderListTile({
    super.key,
    required this.folder,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final Json folder;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final date = fileModifiedLabel(folder);
    final manageable = fileCanManage(folder);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
      ),
      selected: selected,
      leading: const ListIconBadge(
        icon: LucideIcons.folder,
        backgroundColor: DesignTokens.colorListIconAmber,
      ),
      title: Text(
        value(folder, 'name'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (date.isNotEmpty) ...[
            Text(date, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: DesignTokens.spacingXs),
          ],
          SizedBox.square(
            dimension: DesignTokens.spacingLg,
            child: Center(
              child: selectionActive
                  ? _FileSelectionMark(selected: selected, enabled: manageable)
                  : Icon(
                      LucideIcons.chevronRight,
                      size: DesignTokens.componentIconSmallSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
        ],
      ),
      onTap: fileCanOpen(folder) || selectionActive ? onTap : null,
      onLongPress: onLongPress,
    );
  }
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

  final Json folder;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openable = fileCanOpen(folder);
    final manageable = fileCanManage(folder);
    final date = fileModifiedLabel(folder);
    return Semantics(
      label: '${value(folder, 'name')}\n${value(folder, 'path')}',
      button: openable || manageable,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        onTap: openable || selectionActive ? onTap : null,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: const Center(
                        child: Icon(
                          LucideIcons.folder,
                          size: DesignTokens.componentIconLargeSize,
                          color: DesignTokens.colorListIconAmber,
                        ),
                      ),
                    ),
                    if (selectionActive && manageable)
                      Center(child: _FileSelectionMark(selected: selected)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            GlassTooltip(
              triggerMode: TooltipTriggerMode.manual,
              message: value(folder, 'path'),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  value(folder, 'name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            if (date.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacingXxs),
              Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.controller,
    required this.device,
    required this.file,
    required this.selected,
    required this.selectionActive,
    required this.onTap,
    required this.onLongPress,
  });

  final AppStore controller;
  final Json device;
  final Json file;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final kind = fileKindOf(file);
    final theme = Theme.of(context);
    final openable = fileCanOpen(file);
    final manageable = fileCanManage(file);
    final date = fileRecentModifiedLabel(file);
    final unavailableReason = openable ? null : fileUnavailableReason(file);
    final color = fileKindColor(kind);
    return Semantics(
      label: '${value(file, 'name')}\n${value(file, 'path')}',
      button: openable || manageable,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        onTap: openable || selectionActive ? onTap : null,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  DesignTokens.componentThumbnailRounded,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if ((kind == FileKind.images || kind == FileKind.videos) &&
                        openable)
                      MediaThumbnail(
                        file: file,
                        controller: controller,
                        device: device,
                        compact: true,
                      )
                    else if (kind == FileKind.documents && openable)
                      const _DocumentGridPreview()
                    else
                      ColoredBox(
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Center(
                          child: Icon(
                            fileKindIcon(kind),
                            size: DesignTokens.componentIconLargeSize,
                            color: color,
                          ),
                        ),
                      ),
                    if (kind == FileKind.videos)
                      const Positioned(
                        left: DesignTokens.spacingXs,
                        bottom: DesignTokens.spacingXs,
                        child: Icon(
                          LucideIcons.play,
                          color: Colors.white,
                          size: DesignTokens.componentIconActionSize,
                        ),
                      ),
                    if (!openable)
                      Positioned(
                        left: DesignTokens.spacingXs,
                        bottom: DesignTokens.spacingXs,
                        child: Icon(
                          LucideIcons.circleAlert,
                          color: theme.colorScheme.error,
                          size: DesignTokens.componentIconActionSize,
                        ),
                      ),
                    if (selectionActive && manageable)
                      Center(child: _FileSelectionMark(selected: selected)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            GlassTooltip(
              triggerMode: TooltipTriggerMode.manual,
              message: value(file, 'path', fileUnavailableReason(file)),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  value(file, 'name', '未命名文件'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            if (unavailableReason != null || date.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacingXxs),
              Text(
                unavailableReason ?? date,
                maxLines: unavailableReason == null ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: unavailableReason == null
                      ? null
                      : theme.colorScheme.error,
                ),
              ),
            ],
            if (openable)
              Text(
                fileSizeLabel(file['size']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _DocumentGridPreview extends StatelessWidget {
  const _DocumentGridPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Center(
        child: Container(
          width: DesignTokens.componentFileDocumentPreviewWidth,
          height: DesignTokens.componentFileDocumentPreviewHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXs,
            vertical: DesignTokens.spacingTight,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(
              DesignTokens.componentFileDocumentPreviewRounded,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: DesignTokens.spacingMicro,
                decoration: BoxDecoration(
                  color: DesignTokens.colorListIconAmber,
                  borderRadius: BorderRadius.circular(
                    DesignTokens.spacingMicro,
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.spacingXxs),
              for (var index = 0; index < 4; index++) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: index == 3 ? 0.8 : 1,
                    child: Container(
                      height: DesignTokens.spacingMicro,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.spacingMicro,
                        ),
                      ),
                    ),
                  ),
                ),
                if (index < 3) const SizedBox(height: DesignTokens.spacingXxs),
              ],
            ],
          ),
        ),
      ),
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

  final Json file;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final kind = fileKindOf(file);
    final openable = fileCanOpen(file);
    final manageable = fileCanManage(file);
    final date = fileRecentModifiedLabel(file);
    final numericSize = num.tryParse('${file['size']}') ?? 0;
    final detail = [
      if (date.isNotEmpty) date,
      if (numericSize > 0) fileSizeLabel(numericSize),
    ].join(' · ');
    final unavailableReason = openable ? null : fileUnavailableReason(file);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
      ),
      selected: selected,
      leading: ListIconBadge(
        icon: fileKindIcon(kind),
        backgroundColor: fileKindColor(kind),
      ),
      title: GlassTooltip(
        triggerMode: TooltipTriggerMode.manual,
        message: value(file, 'path'),
        child: Text(
          value(file, 'name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      subtitle: unavailableReason == null
          ? null
          : Text(
              unavailableReason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detail.isNotEmpty) ...[
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: DesignTokens.spacingXs),
          ],
          SizedBox.square(
            dimension: DesignTokens.spacingLg,
            child: Center(
              child: selectionActive
                  ? _FileSelectionMark(selected: selected, enabled: manageable)
                  : Icon(
                      LucideIcons.chevronRight,
                      size: DesignTokens.componentIconSmallSize,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
        ],
      ),
      onTap: openable || selectionActive ? onTap : null,
      onLongPress: onLongPress,
    );
  }
}

class _FileSelectionMark extends StatelessWidget {
  const _FileSelectionMark({required this.selected, this.enabled = true});
  final bool selected, enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Container(
        width: DesignTokens.roundedLg,
        height: DesignTokens.roundedLg,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? colors.primary : colors.surface,
          border: Border.all(
            color: selected ? colors.primary : colors.outline,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(
                LucideIcons.check,
                size: DesignTokens.roundedMd,
                color: colors.onPrimary,
              )
            : null,
      ),
    );
  }
}
