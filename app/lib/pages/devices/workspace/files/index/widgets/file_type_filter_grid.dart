import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/file_browser.dart';

class FileTypeFilterGrid extends StatelessWidget {
  const FileTypeFilterGrid({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final FileTypeFilter selected;
  final ValueChanged<FileTypeFilter>? onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final itemWidth = (constraints.maxWidth - DesignTokens.spacingXs) / 2;
      return Wrap(
        spacing: DesignTokens.spacingXs,
        runSpacing: DesignTokens.spacingXs,
        children: [
          for (final entry in const [
            (
              FileTypeFilter.documents,
              '文档',
              LucideIcons.fileText,
              DesignTokens.colorListIconAmber,
            ),
            (
              FileTypeFilter.images,
              '图片',
              LucideIcons.image,
              DesignTokens.colorListIconPurple,
            ),
            (
              FileTypeFilter.videos,
              '视频',
              LucideIcons.video,
              DesignTokens.colorListIconPurple,
            ),
            (
              FileTypeFilter.audio,
              '音频',
              LucideIcons.audioLines,
              DesignTokens.colorListIconSlate,
            ),
          ])
            _FileTypeTile(
              width: itemWidth,
              filter: entry.$1,
              label: entry.$2,
              icon: entry.$3,
              color: entry.$4,
              selected: selected == entry.$1,
              onTap: onSelected == null
                  ? null
                  : () => onSelected!(
                      selected == entry.$1 ? FileTypeFilter.all : entry.$1,
                    ),
            ),
        ],
      );
    },
  );
}

class _FileTypeTile extends StatelessWidget {
  const _FileTypeTile({
    required this.width,
    required this.filter,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final FileTypeFilter filter;
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        width: width,
        child: Material(
          color: selected
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.onSurface
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('file-type-${filter.name}'),
            excludeFromSemantics: true,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DesignTokens.componentTypeCellHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacingSm,
                  vertical: DesignTokens.spacingXs,
                ),
                child: Row(
                  children: [
                    ListIconBadge(icon: icon, backgroundColor: color),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyMedium),
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
