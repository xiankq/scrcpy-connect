import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/devices/device_identity.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';

/// 分组卡片中自带分隔线起点的行。分隔线从标题文字起点开始。
abstract interface class GroupedRow {
  double get separatorIndent;
}

/// 列表行的尾槽宽度：箭头与选择标记共用（design.md「列表」：22 点尾槽）。
const listRowTrailingSlot = DesignTokens.componentSelectionMarkSize;

/// 行尾值与尾槽的间距（Ardot 列表行 37:609「尾部」间距 4）。
const _trailingGap = DesignTokens.spacingXs;

/// 标题与副标题间距（Ardot 列表行 37:609「文本」间距 2）。
const _subtitleGap = DesignTokens.spacingXxs;

/// 设备块行的上下内距（Ardot 列表行 37:818「内容」：上 12、下 11，取 12）。
const _deviceRowVerticalPadding = DesignTokens.spacingMd;

/// 行尾值最多占行宽的比例，保证标题仍有空间。
const _valueMaxWidthFactor = .44;

/// 分隔线起点：行内距 + 前导宽 + 前导与标题间距。
double listRowSeparatorIndent(double? leadingWidth) => leadingWidth == null
    ? DesignTokens.componentListRowPadding
    : DesignTokens.componentListRowPadding +
          leadingWidth +
          DesignTokens.componentListRowGap;

/// 前导为功能色块时的分隔线起点（16 + 30 + 16）。
const tileRowSeparatorIndent =
    DesignTokens.componentListRowPadding +
    DesignTokens.componentIconTileSize +
    DesignTokens.componentListRowGap;

/// 前导为设备块时的分隔线起点（16 + 52 + 16）。
const deviceRowSeparatorIndent =
    DesignTokens.componentListRowPadding +
    DesignTokens.componentDeviceTileSize +
    DesignTokens.componentListRowGap;

/// 由 `SettingsGroup` 为每一行提供，行按下时上报，以隐藏自己及上一行的分隔线。
class ListGroupSlot extends InheritedWidget {
  const ListGroupSlot({
    super.key,
    required this.index,
    required this.onPressedChanged,
    required super.child,
  });

  final int index;
  final void Function(int index, bool pressed) onPressedChanged;

  static ListGroupSlot? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ListGroupSlot>();

  @override
  bool updateShouldNotify(ListGroupSlot oldWidget) =>
      index != oldWidget.index ||
      onPressedChanged != oldWidget.onPressedChanged;
}

/// 把指针按下/抬起上报给所在分组，用于按压行隐藏相邻分隔线。
class ListRowPressReporter extends StatelessWidget {
  const ListRowPressReporter({
    super.key,
    required this.enabled,
    required this.child,
  });
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final slot = ListGroupSlot.maybeOf(context);
    if (slot == null || !enabled) return child;
    return Listener(
      onPointerDown: (_) => slot.onPressedChanged(slot.index, true),
      onPointerUp: (_) => slot.onPressedChanged(slot.index, false),
      onPointerCancel: (_) => slot.onPressedChanged(slot.index, false),
      child: child,
    );
  }
}

/// 列表行（Ardot 列表行 37:609）。
///
/// 前导：功能色块 [ListIconBadge]、设备块 [DeviceIdentity] 或无；标题 `body`，
/// 副标题 `subheadline` + `text-secondary`；尾部依次为行尾值、[trailing] 控件，
/// 导航行在 22 点尾槽内放 18 点箭头。按下时 `pressed` 覆盖整行。
class AppListRow extends StatelessWidget implements GroupedRow {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.value,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.titleMaxLines,
    this.subtitleMaxLines = 2,
    this.contentPadding,
    this.leadingWidth,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;

  /// 行尾值，`subheadline` + `text-secondary`，最多两行。
  final String? value;

  /// 行尾控件：开关、选择标记、区块按钮等。
  final Widget? trailing;

  /// 导航行尾的箭头。
  final bool chevron;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// 读屏与 [ListTile.selected] 的选中状态；选择外观由 [trailing] 的选择标记或对勾表达。
  final bool selected;

  /// 危险动作行：标题用 `error`。
  final bool destructive;
  final int? titleMaxLines;
  final int subtitleMaxLines;
  final EdgeInsetsGeometry? contentPadding;

  /// 前导不是色块或设备块时，用于计算分隔线起点。
  final double? leadingWidth;

  @override
  double get separatorIndent => listRowSeparatorIndent(
    leading == null
        ? null
        : leadingWidth ??
              switch (leading) {
                DeviceIdentity() ||
                DeviceBlock() => DesignTokens.componentDeviceTileSize,
                _ => DesignTokens.componentIconTileSize,
              },
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final interactive = enabled && (onTap != null || onLongPress != null);
    final titleColor = !enabled
        ? colors.disabled
        : destructive
        ? colors.error
        : colors.text;
    final arrow = chevron
        ? SizedBox.square(
            dimension: listRowTrailingSlot,
            child: Icon(
              AppIcons.forward,
              size: DesignTokens.componentChevronSize,
              color: enabled ? colors.outline : colors.disabled,
            ),
          )
        : null;
    Widget? end(double rowWidth) {
      if (value case final label?) {
        return _TrailingValue(
          label: label,
          maxWidth: rowWidth * _valueMaxWidthFactor,
          style: type.subheadline.copyWith(
            color: enabled ? colors.textSecondary : colors.disabled,
          ),
          after: trailing ?? arrow,
        );
      }
      if (trailing != null && arrow != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            trailing!,
            const SizedBox(width: _trailingGap),
            arrow,
          ],
        );
      }
      return trailing ?? arrow;
    }

    Widget tile(double rowWidth) => ListTile(
      enabled: enabled,
      selected: selected,
      selectedColor: titleColor,
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: DesignTokens.componentListRowPadding,
          ),
      minTileHeight: leading is DeviceIdentity || leading is DeviceBlock
          ? DesignTokens.componentDeviceTileSize + 2 * _deviceRowVerticalPadding
          : DesignTokens.componentListRowHeight,
      minVerticalPadding: DesignTokens.componentListRowVerticalPadding,
      minLeadingWidth: DesignTokens.componentIconTileSize,
      horizontalTitleGap: DesignTokens.componentListRowGap,
      splashColor: colors.page.withAlpha(0),
      focusColor: colors.pressed,
      hoverColor: colors.pressed,
      leading: leading,
      title: DefaultTextStyle.merge(
        style: type.body.copyWith(color: titleColor),
        maxLines: titleMaxLines,
        overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
        child: title,
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: _subtitleGap),
              child: DefaultTextStyle.merge(
                style: type.subheadline.copyWith(
                  color: enabled ? colors.textSecondary : colors.disabled,
                ),
                maxLines: subtitleMaxLines,
                overflow: TextOverflow.ellipsis,
                child: subtitle!,
              ),
            ),
      trailing: end(rowWidth),
    );

    return ListRowPressReporter(
      enabled: interactive,
      child: value == null
          ? tile(0)
          : LayoutBuilder(
              builder: (context, constraints) => tile(constraints.maxWidth),
            ),
    );
  }
}

class _TrailingValue extends StatelessWidget {
  const _TrailingValue({
    required this.label,
    required this.maxWidth,
    required this.style,
    required this.after,
  });
  final String label;
  final double maxWidth;
  final TextStyle style;
  final Widget? after;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Tooltip(
              message: label,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: style,
              ),
            ),
          ),
          if (after != null) ...[const SizedBox(width: _trailingGap), after!],
        ],
      ),
    );
  }
}
