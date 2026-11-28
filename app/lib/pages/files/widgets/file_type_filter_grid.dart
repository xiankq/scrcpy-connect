import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/files/widgets/file_kind_style.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/file_browser.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

/// 两列入口之间的间距（Ardot F1 2:1321 类型入口：行列间距 8）。
const _entryGap = DesignTokens.spacingSm;

/// 文件类型入口（Ardot 37:2267）：内距左右 16、上下 12，色块与名称间距 12，圆角 16。
const _entryPadding = EdgeInsets.symmetric(
  horizontal: DesignTokens.spacingLg,
  vertical: DesignTokens.spacingMd,
);
const _entryGlyphGap = DesignTokens.spacingMd;

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
      final itemWidth = (constraints.maxWidth - _entryGap) / 2;
      return Wrap(
        spacing: _entryGap,
        runSpacing: _entryGap,
        children: [
          for (final (filter, label, kind) in const [
            (FileTypeFilter.documents, '文档', FileKind.documents),
            (FileTypeFilter.images, '图片', FileKind.images),
            (FileTypeFilter.videos, '视频', FileKind.videos),
            (FileTypeFilter.audio, '音频', FileKind.audio),
          ])
            _FileTypeTile(
              width: itemWidth,
              filter: filter,
              label: label,
              icon: fileKindIcon(kind),
              color: fileKindColor(kind),
              selected: selected == filter,
              onTap: onSelected == null
                  ? null
                  : () => onSelected!(
                      selected == filter ? FileTypeFilter.all : filter,
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
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(DesignTokens.roundedMd)),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        width: width,
        child: Material(
          color: selected ? colors.primaryContainer : colors.card,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('file-type-${filter.name}'),
            excludeFromSemantics: true,
            customBorder: shape,
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
            child: Padding(
              padding: _entryPadding,
              child: Row(
                children: [
                  ListIconBadge(
                    icon: icon,
                    backgroundColor: onTap == null ? colors.disabled : color,
                  ),
                  const SizedBox(width: _entryGlyphGap),
                  Expanded(
                    child: Text(
                      label,
                      style: type.body.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : onTap == null
                            ? colors.disabled
                            : colors.text,
                      ),
                    ),
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
