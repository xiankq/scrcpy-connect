import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';

/// 开关（Ardot 37:550）：52×32 轨道，命中区高 44。
class ConnectSwitch extends StatelessWidget {
  const ConnectSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onChanged != null;
    final toggle = enabled ? () => onChanged!(!value) : null;
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : regularTransitionDuration;
    final (track, thumb) = !enabled
        ? (colors.disabledContainer, colors.disabled)
        : value
        ? (colors.primary, colors.onPrimary)
        : (colors.inset, colors.outline);
    return Semantics(
      toggled: value,
      enabled: enabled,
      onTap: toggle,
      child: GestureDetector(
        onTap: toggle,
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        child: SizedBox(
          width: DesignTokens.componentSwitchWidth,
          height: DesignTokens.componentBarButtonSize,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: standardCurve,
              width: DesignTokens.componentSwitchWidth,
              height: DesignTokens.componentSwitchHeight,
              padding: const EdgeInsets.all(
                (DesignTokens.componentSwitchHeight -
                        DesignTokens.componentSwitchThumbSize) /
                    2,
              ),
              decoration: ShapeDecoration(
                color: track,
                shape: const StadiumBorder(),
              ),
              child: AnimatedAlign(
                duration: duration,
                curve: standardCurve,
                alignment: value
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: AnimatedContainer(
                  duration: duration,
                  width: DesignTokens.componentSwitchThumbSize,
                  height: DesignTokens.componentSwitchThumbSize,
                  decoration: BoxDecoration(
                    color: thumb,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选择标记（Ardot 37:551）对勾大小。
const _selectionCheckSize = 14.0;

/// 未选态空心圆描边宽度（design.md「列表」：outline 1.5 点空心圆）。
const _selectionRingWidth = 1.5;

/// 22 点选择标记：未选为 outline 空心圆，选中为 primary 实心加白色对勾。
///
/// 只负责外观；读屏状态由所在行或宫格项表达。
class SelectionMark extends StatelessWidget {
  const SelectionMark({
    super.key,
    required this.selected,
    this.enabled = true,
    this.overlay = false,
  });

  final bool selected;
  final bool enabled;

  /// 叠在缩略图正中的宫格样式（design.md「列表」：`selection-mark-overlay`）：
  /// 直径 26、白色圆环，未选为 28% 黑底，已选为 primary 加白色对勾，明暗一致。
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final duration = reduceMotionOf(context)
        ? Duration.zero
        : shortTransitionDuration;
    final size = overlay
        ? _overlayMarkSize
        : DesignTokens.componentSelectionMarkSize;
    final fill = selected
        ? (enabled ? colors.primary : colors.disabled)
        : overlay
        ? DesignTokens.colorViewport.withValues(alpha: _overlayUnselectedAlpha)
        : colors.primary.withAlpha(0);
    final ring = overlay
        ? DesignTokens.colorOnMedia
        : enabled
        ? colors.outline
        : colors.disabled;
    final check = overlay
        ? DesignTokens.colorOnMedia
        : enabled
        ? colors.onPrimary
        : colors.card;
    return AnimatedContainer(
      duration: duration,
      curve: standardCurve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: selected && !overlay
            ? null
            : Border.all(color: ring, width: _selectionRingWidth),
      ),
      child: selected
          ? Icon(
              LucideIcons.check,
              size: overlay ? _overlayCheckSize : _selectionCheckSize,
              color: check,
            )
          : null,
    );
  }
}

/// Ardot「选择标记 · 叠放」44:5。
const _overlayMarkSize = 26.0;
const _overlayCheckSize = 16.0;
const _overlayUnselectedAlpha = .28;

/// 分段项的图形与颜色；未选时用 [color]（添加设备方式的彩色线形图标），选中时为 on-primary。
typedef SegmentIcon = ({IconData icon, Color? color});

/// 图标在上、标签在下的分段高度（design.md「输入与选择」：添加设备的分段为高 64 变体）。
const _iconSegmentedHeight = 64.0;

/// 图标与标签的间距（Ardot 2:828 连接方式分段）。
const _iconSegmentGap = DesignTokens.spacingXxs;

/// interaction-motion「导航与覆盖层」：分段选中胶囊 250 毫秒滑到目标项。
const _segmentThumbDuration = Duration(milliseconds: 250);

/// 分段（Ardot 37:641）：胶囊轨道，选中项为 primary 胶囊，250 毫秒滑到目标项。
class ConnectSegmentedControl<T> extends StatelessWidget {
  const ConnectSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.icons,
    this.onPage = false,
    this.onGlass = false,
  }) : assert(icons == null || icons.length == options.length),
       assert(!(onPage && onGlass));

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T>? onSelected;

  /// 提供时使用图标在上、标签在下的 64 高变体，按 [options] 顺序对应。
  final List<SegmentIcon>? icons;

  /// 直接放在页面底上时轨道用 `card`，否则（卡片内）用 `block`。
  final bool onPage;

  /// 放在玻璃面（菜单、就地面板）上时轨道用 `glass-on-glass`（Ardot 41:1259）；
  /// 玻璃回退为实体浮层面时取浮层面的下一层。
  final bool onGlass;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final enabled = onSelected != null;
    final reduce = reduceMotionOf(context);
    final index = options.indexWhere((option) => option.$1 == selected);
    final count = options.length;
    const inner = DesignTokens.componentSegmentedPadding;
    final minItemHeight =
        (icons == null
            ? DesignTokens.componentSegmentedHeight
            : _iconSegmentedHeight) -
        2 * inner;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: onPage
            ? colors.card
            : onGlass
            ? glassOnGlassColor(context)
            : colors.block,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(inner),
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  duration: reduce ? Duration.zero : _segmentThumbDuration,
                  curve: standardCurve,
                  alignment: AlignmentDirectional(
                    count == 1 ? 0 : -1 + 2 * index / (count - 1),
                    0,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: enabled
                            ? colors.primary
                            : colors.disabledContainer,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final (i, (value, label)) in options.indexed)
                  Expanded(
                    child: _Segment(
                      label: label,
                      icon: icons?[i],
                      selected: i == index,
                      enabled: enabled,
                      minHeight: minItemHeight,
                      onTap: enabled && i != index
                          ? () => onSelected!(value)
                          : null,
                      colors: colors,
                      type: type,
                      reduce: reduce,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.minHeight,
    required this.onTap,
    required this.colors,
    required this.type,
    required this.reduce,
  });

  final String label;
  final SegmentIcon? icon;
  final bool selected;
  final bool enabled;
  final double minHeight;
  final VoidCallback? onTap;
  final AppColors colors;
  final AppTypography type;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? colors.disabled
        : selected
        ? colors.onPrimary
        : colors.textSecondary;
    final style = selected
        ? type.label.copyWith(color: foreground)
        : type.subheadline.copyWith(color: foreground);
    final text = AnimatedDefaultTextStyle(
      duration: reduce ? Duration.zero : shortTransitionDuration,
      style: style,
      textAlign: TextAlign.center,
      child: Text(label, textAlign: TextAlign.center),
    );
    final iconColor = !enabled
        ? colors.disabled
        : selected
        ? colors.onPrimary
        : icon?.color ?? colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingXs,
              vertical: DesignTokens.spacingXxs,
            ),
            child: Center(
              child: icon == null
                  ? text
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon!.icon,
                          size: DesignTokens.componentBarGlyphSize,
                          color: iconColor,
                        ),
                        const SizedBox(height: _iconSegmentGap),
                        text,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 页面底部通栏主按钮的外形：停靠尺寸胶囊。颜色与文字由 [AppButton]/主题决定。
///
/// 新代码直接用 `AppButton(role: AppButtonRole.primary, expand: true)`。
const pagePrimaryButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(
    Size(
      DesignTokens.componentButtonFilledHeight,
      DesignTokens.componentButtonFilledHeight,
    ),
  ),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: DesignTokens.componentButtonFilledPadding),
  ),
  shape: WidgetStatePropertyAll(StadiumBorder()),
);
