import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/file_browser_model.dart';

class FileSearchResultRow extends StatelessWidget {
  const FileSearchResultRow({
    super.key,
    required this.file,
    required this.folder,
    required this.onTap,
    required this.unavailableReason,
  });

  final Json file;
  final bool folder;
  final VoidCallback? onTap;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = value(file, 'name', '未命名文件');
    final path = value(file, 'path');
    final size = folder ? '' : fileSizeLabel(file['size']);
    final reason = unavailableReason;
    final location = reason ?? (folder ? '' : fileParentDirectoryLabel(path));
    final kind = fileKindOf(file);
    return Semantics(
      button: onTap != null,
      child: GlassTooltip(
        message: path,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.componentRowLargeHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacingSm,
              ),
              child: Row(
                children: [
                  ListIconBadge(
                    icon: folder ? LucideIcons.folder : fileKindIcon(kind),
                    backgroundColor: folder
                        ? DesignTokens.colorListIconAmber
                        : fileKindColor(kind),
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
                    LucideIcons.chevronRight,
                    size: DesignTokens.componentIconSmallSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
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
