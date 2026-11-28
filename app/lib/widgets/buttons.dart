import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';

/// 按钮角色（Ardot 按钮 37:516、design.md「按钮」）。填充表示角色，同一角色在任何页面都长一样。
enum AppButtonRole {
  /// `primary` 底、`on-primary` 字。每屏唯一的主动作。
  primary,

  /// 卡片上的次要按钮：`block` 底、`text` 字。
  secondary,

  /// 直接放在页面底上的次要按钮：`card` 底、`text` 字。
  secondaryOnPage,

  /// 卡片上的危险动作：`block` 底、`error` 字。
  destructive,

  /// 页面底上的危险动作：`card` 底、`error` 字。
  destructiveOnPage,

  /// 无底，`primary` 字。帮助、编辑、查看更多等轻量入口。
  text,

  /// 确认框主位置的不可逆动作：`destructive` 实色、白字。
  destructiveFilled,

  /// 玻璃面上的次要按钮：`glass-on-glass` 底、`text` 字（design.md「玻璃配方」）。
  secondaryOnGlass,

  /// 玻璃面上的危险动作：`glass-on-glass` 底、`error` 字（远控工具面板「关闭画面」）。
  destructiveOnGlass,

  /// 照片、视频、通话舞台与熄屏视口上的 `glass-clear` 胶囊，前景 `on-media`；
  /// 玻璃回退为实体浮层面时前景换回 `text`。
  glass,
}

/// 媒体上的禁用前景，与 `disabled` 同为正文色 38%。
const _mediaDisabledOpacity = .38;

/// 按钮尺寸由所在位置决定。
enum AppButtonSize {
  /// 高 48、图形 24：页面底部、确认框、工作台主次按钮。
  dock,

  /// 高 36、图形 20：列表行尾、卡片标题行、组头。
  section,
}

/// 区块按钮内距与图文间距（Ardot 37:462「主要 区块」：左右 16、间距 6）。
const _sectionPadding = DesignTokens.componentChipPadding;
const _sectionGap = DesignTokens.componentChipGap;

/// 实体按钮按下时浅色降到的不透明度、深色叠加的白色比例（interaction-motion「触点反馈」）。
const _pressedOpacityLight = .75;
const _pressedOverlayDark = .2;

/// 带文字的共享按钮。底层为 Material 按钮：主要/实色危险为 [FilledButton]，
/// 次要/危险为 [OutlinedButton]，文字为 [TextButton]，以保留焦点、读屏与测试查找方式。
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.role = AppButtonRole.secondary,
    this.size = AppButtonSize.dock,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonRole role;
  final AppButtonSize size;

  /// 文字前的图形，取标签颜色。
  final IconData? icon;

  /// 进行中时用环形指示器替换图形；是否可点由 [onPressed] 决定。
  final bool busy;

  /// 撑满可用宽度（页面底部通栏、并排的工作台按钮）。
  final bool expand;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? tooltip;

  /// 供仍需直接使用 Material 按钮（如 `FilledButton.icon`）的调用方取同一外观。
  static ButtonStyle styleOf(
    BuildContext context, {
    AppButtonRole role = AppButtonRole.secondary,
    AppButtonSize size = AppButtonSize.dock,
  }) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final clear = colors.page.withAlpha(0);
    final media = opaqueGlass(context)
        ? colors.text
        : DesignTokens.colorOnMedia;
    final (Color fill, Color foreground) = switch (role) {
      AppButtonRole.primary => (colors.primary, colors.onPrimary),
      AppButtonRole.secondary => (colors.block, colors.text),
      AppButtonRole.secondaryOnPage => (colors.card, colors.text),
      AppButtonRole.destructive => (colors.block, colors.error),
      AppButtonRole.destructiveOnPage => (colors.card, colors.error),
      AppButtonRole.text => (clear, colors.primary),
      AppButtonRole.destructiveFilled => (
        colors.destructive,
        DesignTokens.colorOnMedia,
      ),
      AppButtonRole.secondaryOnGlass => (
        glassOnGlassColor(context),
        colors.text,
      ),
      AppButtonRole.destructiveOnGlass => (
        glassOnGlassColor(context),
        colors.error,
      ),
      AppButtonRole.glass => (clear, media),
    };
    final textRole = role == AppButtonRole.text;
    final glassRole = role == AppButtonRole.glass;
    final disabledForeground = glassRole
        ? media.withValues(alpha: media.a * _mediaDisabledOpacity)
        : colors.disabled;
    final height = switch (size) {
      AppButtonSize.dock => DesignTokens.componentButtonFilledHeight,
      AppButtonSize.section => DesignTokens.componentSectionButtonSize,
    };
    final padding = textRole
        ? DesignTokens.componentButtonTextPadding
        : switch (size) {
            AppButtonSize.dock => DesignTokens.componentButtonFilledPadding,
            AppButtonSize.section => _sectionPadding,
          };
    final pressOverlay = DesignTokens.colorOnMedia.withValues(
      alpha: _pressedOverlayDark,
    );
    Color pressedFill(Color color) => dark
        ? Color.alphaBlend(pressOverlay, color)
        : color.withValues(alpha: color.a * _pressedOpacityLight);
    return ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      splashFactory: NoSplash.splashFactory,
      animationDuration: reduceMotionOf(context)
          ? Duration.zero
          : pressReleaseDuration,
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: WidgetStatePropertyAll(Size(height, height)),
      maximumSize: const WidgetStatePropertyAll(Size.infinite),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: padding),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(type.label),
      iconSize: WidgetStatePropertyAll(
        size == AppButtonSize.dock
            ? DesignTokens.componentBarGlyphSize
            : DesignTokens.componentSectionGlyphSize,
      ),
      overlayColor: WidgetStatePropertyAll(clear),
      shadowColor: WidgetStatePropertyAll(clear),
      surfaceTintColor: WidgetStatePropertyAll(clear),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return textRole || glassRole ? clear : colors.disabledContainer;
        }
        // 玻璃胶囊的按压由 GlassPressFeedback 呈现。
        if (glassRole) return fill;
        if (states.contains(WidgetState.pressed)) return pressedFill(fill);
        return fill;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledForeground;
        if (states.contains(WidgetState.pressed) && !dark) {
          return foreground.withValues(
            alpha: foreground.a * _pressedOpacityLight,
          );
        }
        return foreground;
      }),
      iconColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? disabledForeground
            : foreground,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(
                color: colors.primary,
                width: DesignTokens.componentControlFocusSize,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context, role: role, size: size);
    final glyph = size == AppButtonSize.dock
        ? DesignTokens.componentBarGlyphSize
        : DesignTokens.componentSectionGlyphSize;
    final leading = busy
        ? ContentLoadingIndicator(size: glyph, color: _foreground(context))
        : icon == null
        ? null
        : Icon(icon, size: glyph);
    final child = leading == null
        ? Text(label, textAlign: TextAlign.center)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              SizedBox(
                width: size == AppButtonSize.dock
                    ? DesignTokens.componentButtonFilledGap
                    : _sectionGap,
              ),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    Widget button = switch (role) {
      AppButtonRole.primary || AppButtonRole.destructiveFilled => FilledButton(
        style: style,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: child,
      ),
      AppButtonRole.text || AppButtonRole.glass => TextButton(
        style: style,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: child,
      ),
      _ => OutlinedButton(
        style: style,
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        child: child,
      ),
    };
    if (expand) button = SizedBox(width: double.infinity, child: button);
    if (role == AppButtonRole.glass) {
      button = GlassPressFeedback(
        enabled: onPressed != null,
        child: Glass(
          variant: GlassVariant.clear,
          radius: DesignTokens.roundedFull,
          showShadow: false,
          child: button,
        ),
      );
    }
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    return button;
  }

  Color _foreground(BuildContext context) {
    final colors = AppColors.of(context);
    if (role == AppButtonRole.glass) {
      final media = opaqueGlass(context)
          ? colors.text
          : DesignTokens.colorOnMedia;
      return onPressed == null
          ? media.withValues(alpha: media.a * _mediaDisabledOpacity)
          : media;
    }
    if (onPressed == null) return colors.disabled;
    return switch (role) {
      AppButtonRole.primary => colors.onPrimary,
      AppButtonRole.secondary ||
      AppButtonRole.secondaryOnPage ||
      AppButtonRole.secondaryOnGlass => colors.text,
      AppButtonRole.destructive ||
      AppButtonRole.destructiveOnPage ||
      AppButtonRole.destructiveOnGlass => colors.error,
      AppButtonRole.text => colors.primary,
      AppButtonRole.destructiveFilled ||
      AppButtonRole.glass => DesignTokens.colorOnMedia,
    };
  }
}

/// 卡片内的实体图标按钮（design.md「按钮」图标按钮·卡片内）：`block` 底正圆，图形 20。
///
/// 页头的玻璃图标按钮不在此处。
class SolidIconButton extends StatelessWidget {
  const SolidIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
    this.onPage = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 紧凑尺寸 32（密集工具、宫格角落），否则区块尺寸 36。
  final bool compact;

  /// 直接放在页面底上时用 `card` 底。
  final bool onPage;

  @override
  Widget build(BuildContext context) {
    final base = AppButton.styleOf(
      context,
      role: onPage ? AppButtonRole.secondaryOnPage : AppButtonRole.secondary,
      size: AppButtonSize.section,
    );
    final size = compact
        ? DesignTokens.componentCompactButtonSize
        : DesignTokens.componentSectionButtonSize;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: base.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll(Size.square(size)),
        maximumSize: WidgetStatePropertyAll(Size.square(size)),
        fixedSize: WidgetStatePropertyAll(Size.square(size)),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        iconSize: const WidgetStatePropertyAll(
          DesignTokens.componentSectionGlyphSize,
        ),
      ),
    );
  }
}
