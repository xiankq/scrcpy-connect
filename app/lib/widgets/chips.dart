import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';

/// 带下拉的 chip 尾部箭头大小与收窄后的尾内距（Ardot 37:649：右内距 12、箭头 16）。
const _dropdownGlyphSize = 16.0;
const _dropdownEndPadding = DesignTokens.spacingMd;

/// chip 前导图形大小（与区块按钮的图形同档）。
const _chipGlyphSize = DesignTokens.componentSectionGlyphSize;

/// 实体按钮按下时浅色降到的不透明度、深色叠加的白色比例（interaction-motion「触点反馈」）。
const _pressedOpacityLight = .75;
const _pressedOverlayDark = .2;

/// 筛选与范围 chip（Ardot Chip 37:660）：高 36 胶囊，未选 `card` 底，选中 `primary` 底。
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.dropdown = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  /// 打开下拉选项的 chip 在尾部加 16 点向下箭头。
  final bool dropdown;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onPressed != null;
    final fill = !enabled
        ? colors.disabledContainer
        : selected
        ? colors.primary
        : colors.card;
    final foreground = !enabled
        ? colors.disabled
        : selected
        ? colors.onPrimary
        : colors.text;
    final clear = colors.page.withAlpha(0);
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          splashFactory: NoSplash.splashFactory,
          animationDuration: reduceMotionOf(context)
              ? Duration.zero
              : pressReleaseDuration,
          minimumSize: const WidgetStatePropertyAll(
            Size(
              DesignTokens.componentChipHeight,
              DesignTokens.componentChipHeight,
            ),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsetsDirectional.only(
              start: DesignTokens.componentChipPadding,
              end: dropdown
                  ? _dropdownEndPadding
                  : DesignTokens.componentChipPadding,
            ),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: WidgetStatePropertyAll(type.label),
          overlayColor: WidgetStatePropertyAll(clear),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? dark
                      ? Color.alphaBlend(
                          DesignTokens.colorOnMedia.withValues(
                            alpha: _pressedOverlayDark,
                          ),
                          fill,
                        )
                      : fill.withValues(alpha: fill.a * _pressedOpacityLight)
                : fill,
          ),
          foregroundColor: WidgetStatePropertyAll(foreground),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(
                    color: colors.primary,
                    width: DesignTokens.componentControlFocusSize,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  )
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: _chipGlyphSize, color: foreground),
              const SizedBox(width: DesignTokens.componentChipGap),
            ],
            Flexible(child: Text(label)),
            if (dropdown) ...[
              const SizedBox(width: DesignTokens.componentChipGap),
              Icon(
                LucideIcons.chevronDown,
                size: _dropdownGlyphSize,
                color: foreground,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
