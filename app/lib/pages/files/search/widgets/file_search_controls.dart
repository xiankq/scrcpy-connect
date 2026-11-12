import 'package:material_ui/material_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

const fileSearchFilters = {
  FileCatalogFilter.all: '全部',
  FileCatalogFilter.images: '图片',
  FileCatalogFilter.videos: '视频',
  FileCatalogFilter.audio: '音频',
  FileCatalogFilter.documents: '文档',
  FileCatalogFilter.archives: '压缩包',
  FileCatalogFilter.folders: '文件夹',
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              340;
          final choices = [
            for (final entire in [false, true])
              Semantics(
                button: true,
                selected: entireStorage == entire,
                child: Material(
                  color: entireStorage == entire
                      ? theme.colorScheme.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                    onTap: () => onChanged(entire),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.all(DesignTokens.spacingSm),
                        child: Center(
                          child: Text(
                            entire ? '手机内部存储' : '当前目录及子目录',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ];
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: choices,
                )
              : Row(
                  children: [
                    for (final choice in choices) Expanded(child: choice),
                  ],
                );
        },
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

  final FileCatalogFilter value;
  final ValueChanged<FileCatalogFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = GlassMaterial.reduceMotion(context);
    return GlassAccessibilityScope(
      reduceMotion: reduceMotion,
      child: GlassMenu(
        autoAdjustToScreen: true,
        menuWidth: (180 * MediaQuery.textScalerOf(context).scale(1)).clamp(
          180,
          MediaQuery.sizeOf(context).width - 32,
        ),
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
        triggerBuilder: (context, toggle) => ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.componentRowHeight,
          ),
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
                    vertical: DesignTokens.spacingSm,
                    horizontal:
                        DesignTokens.spacingMd + DesignTokens.spacingXxs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fileSearchFilters[value] ??
                              fileSearchFilters[FileCatalogFilter.all]!,
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
              height:
                  MediaQuery.textScalerOf(context)
                          .scale(theme.textTheme.bodyMedium!.fontSize!) *
                      (theme.textTheme.bodyMedium!.height ?? 1.5) +
                  DesignTokens.spacingSm * 2,
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
