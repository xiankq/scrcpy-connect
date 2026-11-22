import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/files/file_search.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/choice_picker.dart';

const fileSearchFilters = {
  FileCatalogFilter.all: '全部类型',
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
              170;
          final choices = [
            for (final entire in [false, true])
              Semantics(
                button: true,
                selected: entireStorage == entire,
                child: Material(
                  color: entireStorage == entire
                      ? theme.colorScheme.primary
                      : DesignTokens.colorTransparent,
                  borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
                    onTap: () => onChanged(entire),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: DesignTokens.componentIconButtonSize,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingXxs,
                          vertical: DesignTokens.spacingXs,
                        ),
                        child: Center(
                          child: Text(
                            entire ? '手机内部存储' : '当前目录及其子目录',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: entireStorage == entire
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            ),
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
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('file-search-type-field'),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingXxs),
      minimumSize: const Size(0, DesignTokens.componentIconButtonSize),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      textStyle: Theme.of(context).textTheme.bodySmall,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
      ),
    ),
    iconAlignment: IconAlignment.end,
    icon: const Icon(
      LucideIcons.chevronDown,
      size: DesignTokens.componentIconSmallSize,
    ),
    label: Text(fileSearchFilters[value]!, textAlign: TextAlign.center),
    onPressed: () async {
      final next = await showChoicePicker<FileCatalogFilter>(
        context: context,
        title: '选择文件类型',
        options: fileSearchFilters.keys,
        label: (option) => fileSearchFilters[option]!,
        isSelected: (option) => option == value,
      );
      if (next != null && context.mounted) onChanged(next);
    },
  );
}
