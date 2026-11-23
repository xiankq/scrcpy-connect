import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/glass/glass_action_bar.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

class FileViewMenuButton extends HookWidget {
  const FileViewMenuButton({
    super.key,
    required this.viewMode,
    required this.sortKey,
    required this.ascending,
    required this.onViewModeChanged,
    required this.onSortKeyChanged,
    required this.onAscendingChanged,
  });

  final FileViewMode viewMode;
  final FileSortKey sortKey;
  final bool ascending;
  final ValueChanged<FileViewMode> onViewModeChanged;
  final ValueChanged<FileSortKey> onSortKeyChanged;
  final ValueChanged<bool> onAscendingChanged;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final menu = useMemoized(MenuController.new);
    final width = math.min(
      DesignTokens.componentFileViewPopoverWidth,
      size.width -
          MediaQuery.paddingOf(context).horizontal -
          2 * DesignTokens.spacingMd,
    );
    final optionsWidth = width - 2 * DesignTokens.spacingMd;
    return MenuAnchor(
      controller: menu,
      animated: !GlassMaterial.reduceMotion(context),
      consumeOutsideTap: true,
      clipBehavior: Clip.none,
      alignmentOffset: Offset(
        -width / 2,
        DesignTokens.componentFileActionBarPadding + DesignTokens.spacingXs,
      ),
      style: const MenuStyle(
        alignment: AlignmentDirectional.bottomCenter,
        backgroundColor: WidgetStatePropertyAll(DesignTokens.colorTransparent),
        surfaceTintColor: WidgetStatePropertyAll(DesignTokens.colorTransparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      builder: (context, controller, child) => GlassActionBarButton(
        label: '视图与排序',
        icon: const Icon(AppIcons.viewOptions),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        SizedBox(
          width: width,
          child: Glass(
            radius: DesignTokens.roundedLg,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height * .65),
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '视图与排序',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: DesignTokens.spacingMd),
                    Text('排序', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: DesignTokens.spacingXs),
                    _choices(
                      context,
                      label: '排序',
                      width: optionsWidth,
                      selected: sortKey,
                      entries: const [
                        (FileSortKey.name, '名称'),
                        (FileSortKey.size, '大小'),
                        (FileSortKey.modified, '时间'),
                        (FileSortKey.type, '类型'),
                      ],
                      onSelected: (value) {
                        onSortKeyChanged(value);
                        menu.close();
                      },
                    ),
                    const SizedBox(height: DesignTokens.spacingSm),
                    _choices(
                      context,
                      label: '顺序',
                      width: optionsWidth,
                      selected: ascending,
                      entries: const [(true, '升序'), (false, '降序')],
                      onSelected: (value) {
                        onAscendingChanged(value);
                        menu.close();
                      },
                    ),
                    const SizedBox(height: DesignTokens.spacingSm),
                    _choices(
                      context,
                      label: '布局',
                      width: optionsWidth,
                      selected: viewMode,
                      entries: const [
                        (FileViewMode.list, '列表'),
                        (FileViewMode.grid, '宫格'),
                      ],
                      onSelected: (value) {
                        onViewModeChanged(value);
                        menu.close();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _choices<T>(
    BuildContext context, {
    required String label,
    required double width,
    required T selected,
    required List<(T, String)> entries,
    required ValueChanged<T> onSelected,
  }) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.merge(
      DesignTokens.componentFileViewPopoverTypography,
    );
    final labelWidth = MediaQuery.textScalerOf(context)
        .scale(DesignTokens.typographyFileOptionLabelFontSize * 2);
    final columns = (width / (labelWidth + 2 * DesignTokens.spacingXs))
        .floor()
        .clamp(1, entries.length);
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(DesignTokens.roundedMd),
        ),
        child: Wrap(
          children: [
            for (final (value, title) in entries)
              SizedBox(
                width: width / columns,
                child: Semantics(
                  selected: value == selected,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: value == selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      textStyle: style,
                      backgroundColor: value == selected
                          ? theme.colorScheme.primary
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.roundedMd,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingXs,
                        vertical: DesignTokens.spacingXxs,
                      ),
                    ),
                    onPressed: () => onSelected(value),
                    child: Text(title, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
