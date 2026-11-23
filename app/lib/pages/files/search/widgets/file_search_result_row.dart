import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/models/file_catalog_entry.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

class FileSearchResultRow extends StatelessWidget {
  const FileSearchResultRow({
    super.key,
    required this.file,
    required this.folder,
    required this.onTap,
    required this.unavailableReason,
  });

  final FileCatalogEntry file;
  final bool folder;
  final VoidCallback? onTap;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = file.name;
    final path = file.path ?? '';
    final size = folder ? '' : fileSizeLabel(file.size);
    final reason = unavailableReason;
    final location = reason ?? fileParentDirectoryLabel(path);
    final kind = FileKind.classify(name: file.name, mime: file.mime);
    return Semantics(
      button: onTap != null,
      child: Tooltip(
        message: path,
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.roundedLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DesignTokens.componentRowLargeHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingMd,
                  vertical: DesignTokens.spacingSm,
                ),
                child: Row(
                  children: [
                    ListIconBadge(
                      icon: folder ? LucideIcons.folder : fileKindIcon(kind),
                      backgroundColor: folder
                          ? DesignTokens.colorListIconAmber
                          : fileKindColor(
                              kind,
                              name: file.name,
                              mime: file.mime,
                            ),
                    ),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: DesignTokens.spacingXxs),
                            Text(
                              location,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: reason == null
                                    ? null
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (size.isNotEmpty) ...[
                      const SizedBox(width: DesignTokens.spacingXs),
                      Text(size, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(width: DesignTokens.spacingXs),
                    Icon(
                      AppIcons.forward,
                      size: DesignTokens.componentIconSmallSize,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String fileParentDirectoryLabel(String path) {
  final separator = path.lastIndexOf('/');
  final parent = separator <= 0 ? '/' : path.substring(0, separator);
  if (parent == '/') return '设备根目录';
  final crumbs = fileBreadcrumbs(parent);
  if (parent == '/sdcard') return '手机存储';
  if (parent.startsWith('/sdcard/')) {
    return ['手机存储', ...crumbs.skip(1).map((crumb) => crumb.label)].join(' / ');
  }
  return crumbs.map((crumb) => crumb.label).join(' / ');
}
