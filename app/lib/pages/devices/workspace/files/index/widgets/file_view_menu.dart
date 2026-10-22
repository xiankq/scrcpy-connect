import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/services/file_browser_model.dart';

class FileViewMenuButton extends StatelessWidget {
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
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final menuWidth = math.min(
      288.0,
      math.max(208.0, MediaQuery.sizeOf(context).width - 32),
    );
    final sectionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return GlassAccessibilityScope(
      reduceMotion: reduceMotion,
      child: GlassMenu(
        autoAdjustToScreen: true,
        menuPadding: const EdgeInsets.all(DesignTokens.spacingMd),
        menuWidth: menuWidth,
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
        triggerBuilder: (context, toggle) => GlassActionIcon(
          tooltip: '视图与排序',
          icon: const Icon(LucideIcons.slidersHorizontal),
          onPressed: toggle,
        ),
        items: [
          GlassMenuLabel(title: '视图', style: sectionStyle),
          _choice(
            context,
            label: '网格',
            selected: viewMode == FileViewMode.grid,
            reduceMotion: reduceMotion,
            onPressed: () => onViewModeChanged(FileViewMode.grid),
          ),
          _choice(
            context,
            label: '列表',
            selected: viewMode == FileViewMode.list,
            reduceMotion: reduceMotion,
            onPressed: () => onViewModeChanged(FileViewMode.list),
          ),
          const GlassMenuDivider(),
          GlassMenuLabel(title: '排序', style: sectionStyle),
          for (final entry in const [
            (FileSortKey.name, '名称'),
            (FileSortKey.size, '文件大小'),
            (FileSortKey.modified, '修改时间'),
            (FileSortKey.type, '文件类型'),
          ])
            _choice(
              context,
              label: entry.$2,
              selected: sortKey == entry.$1,
              reduceMotion: reduceMotion,
              onPressed: () => onSortKeyChanged(entry.$1),
            ),
          const GlassMenuDivider(),
          GlassMenuLabel(title: '顺序', style: sectionStyle),
          _choice(
            context,
            label: '升序',
            selected: ascending,
            reduceMotion: reduceMotion,
            onPressed: () => onAscendingChanged(true),
          ),
          _choice(
            context,
            label: '降序',
            selected: !ascending,
            reduceMotion: reduceMotion,
            onPressed: () => onAscendingChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required String label,
    required bool selected,
    required bool reduceMotion,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return GlassMenuItem(
      title: label,
      isSelected: selected,
      height: DesignTokens.componentIconButtonSize,
      titleStyle: theme.textTheme.bodyLarge,
      trailing: selected
          ? Icon(
              LucideIcons.check,
              size: DesignTokens.componentIconActionSize,
              color: theme.colorScheme.onSurface,
            )
          : null,
      enablePressScale: !reduceMotion,
      onTap: onPressed,
    );
  }
}
