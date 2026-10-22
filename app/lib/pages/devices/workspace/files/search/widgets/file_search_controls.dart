import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const fileSearchFilters = {
  'all': '全部',
  'images': '图片',
  'videos': '视频',
  'audio': '音频',
  'documents': '文档',
  'archives': '压缩包',
  'folders': '文件夹',
};

class FileSearchScopeSelector extends StatelessWidget {
  const FileSearchScopeSelector({
    super.key,
    required this.entireStorage,
    required this.onChanged,
  });

  final bool entireStorage;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        ),
        child: Row(
          children: [
            for (final entire in [false, true])
              Expanded(
                child: Semantics(
                  button: true,
                  selected: entireStorage == entire,
                  child: Material(
                    color: entireStorage == entire
                        ? theme.colorScheme.surface
                        : Colors.transparent,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => onChanged(entire),
                      child: Center(
                        child: Text(
                          entire ? '手机内部存储' : '当前目录及子目录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FileSearchTypeField extends StatelessWidget {
  const FileSearchTypeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = GlassMaterial.reduceMotion(context);
    return GlassAccessibilityScope(
      reduceMotion: reduceMotion,
      child: GlassMenu(
        autoAdjustToScreen: true,
        menuWidth: 180,
        menuPadding: const EdgeInsets.all(DesignTokens.spacingXs),
        menuBorderRadius: DesignTokens.roundedLg,
        itemBorderRadius: DesignTokens.roundedMd,
        settings: Glass.optics(
          brightness: theme.brightness,
          variant: GlassVariant.regular,
        ),
        quality: GlassQuality.premium,
        stretch: reduceMotion
            ? 0
            : DesignTokens.componentGlassInteractionStretch,
        morphSpeed: reduceMotion ? MorphSpeed.instant : MorphSpeed.fast,
        triggerBuilder: (context, toggle) => SizedBox.expand(
          child: Semantics(
            button: true,
            label: '文件类型，当前${fileSearchFilters[value]}',
            child: Material(
              key: const ValueKey('file-search-type-field'),
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal:
                        DesignTokens.spacingMd + DesignTokens.spacingXxs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fileSearchFilters[value] ?? fileSearchFilters['all']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacingXs),
                      Icon(
                        LucideIcons.chevronDown,
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
        items: [
          for (final entry in fileSearchFilters.entries)
            GlassMenuItem(
              title: entry.value,
              isSelected: value == entry.key,
              height: DesignTokens.componentIconButtonSize,
              titleStyle: theme.textTheme.bodyMedium,
              trailing: value == entry.key
                  ? Icon(
                      LucideIcons.check,
                      size: DesignTokens.componentIconActionSize,
                    )
                  : null,
              enablePressScale: !reduceMotion,
              onTap: () => onChanged(entry.key),
            ),
        ],
      ),
    );
  }
}
