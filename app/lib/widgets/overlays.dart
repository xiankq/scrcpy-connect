import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// 确认框进入：1.2 倍缩到 1 并淡入约 400 毫秒；关闭只淡出
/// （interaction-motion「导航与覆盖层」）。
const alertEnterDuration = Duration(milliseconds: 400);
const alertExitDuration = shortTransitionDuration;
const _alertEnterScale = 1.2;

/// Ardot 确认框 37:752：标题区上内距 21、正文区下内距 20、标题与正文间距 6。
const _alertTitleTop = 21.0;
const _alertMessageBottom = 20.0;
const _alertTitleGap = 6.0;

/// 抽屉把手距顶 6（design.md「菜单、确认框与抽屉」，Ardot 37:1380）。
const _sheetHandleTop = 6.0;

/// 抽屉最高停靠点 0.9 屏高（interaction-motion「导航与覆盖层」）。
const _sheetMaxHeightFactor = .9;

/// 承载正文和反馈的实体内容面；玻璃仅用于独立操作控件。
class ContentSurface extends StatelessWidget {
  const ContentSurface({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedXl,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.of(context).card,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// 确认框 `alert`：宽 348、圆角 34；标题 `headline`，正文 `subheadline` 次要色；
/// 两个动作横排放得下时并排（主动作在右），放不下时纵排、取消在最下。
///
/// [glass] 为真时使用 `glass-alert` 材质，否则为实体浮层面（表单类弹窗）。
/// 动作区内的 [TextButton] / [OutlinedButton] 呈现为次要胶囊，[FilledButton] 为主要胶囊，
/// 高 48，标签 17 点 600。
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
    this.glass = false,
  });

  final Widget? title;
  final Widget content;
  final List<Widget> actions;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final translucent = glass && !opaqueGlass(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 浮层的实体回退：浅色 card，深色 block（design.md「表面层级」）。
    final solid = dark ? colors.block : colors.card;
    final secondary = translucent ? colors.glassFill : colors.block;
    final body = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(
          top: _alertTitleTop,
          bottom: DesignTokens.componentAlertActionsPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.componentAlertPadding,
                0,
                DesignTokens.componentAlertPadding,
                _alertMessageBottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    DefaultTextStyle(style: type.headline, child: title!),
                    const SizedBox(height: _alertTitleGap),
                  ],
                  DefaultTextStyle(
                    style: type.subheadline.copyWith(
                      color: colors.textSecondary,
                    ),
                    child: content,
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.componentAlertActionsPadding,
                ),
                child: _AlertActions(secondary: secondary, actions: actions),
              ),
          ],
        ),
      ),
    );
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(DesignTokens.componentAlertRounded),
      ),
    );
    return Dialog(
      backgroundColor: colors.card.withAlpha(0),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingLg,
        vertical: DesignTokens.spacingXxl,
      ),
      constraints: const BoxConstraints.tightFor(
        width: DesignTokens.componentAlertWidth,
      ),
      shape: shape,
      clipBehavior: Clip.none,
      child: translucent
          ? Glass(
              variant: GlassVariant.alert,
              radius: DesignTokens.componentAlertRounded,
              child: body,
            )
          : DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                color: solid,
                shadows: [
                  BoxShadow(
                    color: colors.shadowDock,
                    blurRadius: DesignTokens.componentDockShadowShadowBlur,
                    offset: const Offset(
                      0,
                      DesignTokens.componentDockShadowShadowOffset,
                    ),
                  ),
                ],
              ),
              child: body,
            ),
    );
  }
}

class _AlertActions extends StatelessWidget {
  const _AlertActions({required this.secondary, required this.actions});

  final Color secondary;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const size = Size(
      DesignTokens.componentAlertActionsHeight,
      DesignTokens.componentAlertActionsHeight,
    );
    const padding = EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg);
    final theme = Theme.of(context);
    // 确认框按钮标签 17 点 600（Ardot 37:757），中禁用动作保留原填充（design.md「按钮」）。
    final label = type.headline;
    final secondaryStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(size),
      padding: const WidgetStatePropertyAll(padding),
      backgroundColor: WidgetStatePropertyAll(secondary),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.disabled
            : colors.text,
      ),
      side: const WidgetStatePropertyAll(BorderSide.none),
      textStyle: WidgetStatePropertyAll(label),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    );
    final scoped = theme.copyWith(
      textButtonTheme: TextButtonThemeData(
        style: secondaryStyle.merge(theme.textButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: secondaryStyle.merge(theme.outlinedButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(size),
          padding: const WidgetStatePropertyAll(padding),
          textStyle: WidgetStatePropertyAll(label),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
        ).merge(theme.filledButtonTheme.style),
      ),
    );
    return Theme(
      data: scoped,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = DesignTokens.componentAlertActionsGap;
          // 两个按钮各需容纳约 4 个 17 点字与内距；大字时改为纵排。
          final scale = MediaQuery.textScalerOf(context);
          final minimum =
              2 * (scale.scale(4 * label.fontSize!) + padding.horizontal) + gap;
          final row = actions.length == 2 && constraints.maxWidth >= minimum;
          if (row) {
            return Row(
              spacing: gap,
              children: [for (final button in actions) Expanded(child: button)],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: actions.reversed.toList(),
          );
        },
      ),
    );
  }
}

/// 确认框与弹出层的路由：遮罩同时淡入，内容从 1.2 倍缩到 1 并淡入，关闭只淡出。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  WidgetBuilder? builder,
  Widget? title,
  Widget? content,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  assert(builder != null || content != null);
  final reduced = reduceMotionOf(context);
  return showDialog<T>(
    context: context,
    barrierColor: AppColors.of(context).scrim,
    barrierDismissible: barrierDismissible,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    animationStyle: reduced
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: alertEnterDuration,
            reverseDuration: alertExitDuration,
            curve: enterCurve,
          ),
    builder: (context) {
      final dialog =
          builder?.call(context) ??
          AppAlertDialog(title: title, content: content!, actions: actions);
      final animation = ModalRoute.of(context)?.animation;
      if (reduced || animation == null) return dialog;
      return AnimatedBuilder(
        animation: animation,
        child: dialog,
        builder: (context, child) {
          final exiting = animation.status == AnimationStatus.reverse;
          final scale = exiting
              ? 1.0
              : _alertEnterScale +
                    (1 - _alertEnterScale) *
                        enterCurve.transform(animation.value);
          return Transform.scale(scale: scale, child: child);
        },
      );
    },
  );
}

/// 抽屉 `sheet`：底为 `page`、顶角 28，把手 28×4 距顶 6；最高 0.9 屏高。
///
/// Flutter 持有模态路由、结果与拖动；内容抽屉始终使用实体面。内容顶部用 [SheetHeader]。
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  BoxConstraints? constraints,
  bool isDismissible = true,
  bool enableDrag = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  final colors = AppColors.of(context);
  final height = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<T>(
    context: context,
    barrierColor: colors.scrim,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    constraints:
        constraints ??
        BoxConstraints(maxHeight: height * _sheetMaxHeightFactor),
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    showDragHandle: false,
    backgroundColor: colors.page,
    elevation: 0,
    shape: const RoundedSuperellipseBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DesignTokens.componentSheetRounded),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: reduceMotionOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: panelOpenDuration,
            reverseDuration: panelCloseDuration,
            curve: enterCurve,
          ),
    builder: (context) => enableDrag
        ? Stack(
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top:
                      _sheetHandleTop + DesignTokens.componentSheetHandleHeight,
                ),
                child: builder(context),
              ),
              const Padding(
                padding: EdgeInsets.only(top: _sheetHandleTop),
                child: SheetHandle(),
              ),
            ],
          )
        : Padding(
            padding: const EdgeInsets.only(
              top: _sheetHandleTop + DesignTokens.componentSheetHandleHeight,
            ),
            child: builder(context),
          ),
  );
}

/// 抽屉把手 28×4，`outline` 胶囊；读屏可用它关闭抽屉。
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    button: true,
    onTap: () => Navigator.pop(context),
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: AppColors.of(context).outline,
          shape: const StadiumBorder(),
        ),
        child: const SizedBox(
          width: DesignTokens.componentSheetHandleWidth,
          height: DesignTokens.componentSheetHandleHeight,
        ),
      ),
    ),
  );
}

/// 抽屉与居中弹层的标题栏：高 48、`title3` 标题，尾部可放文字按钮（Ardot 37:1380 / 37:1364）。
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  /// 标题栏高度，Ardot「抽屉 / 头部」37:1382。
  static const height = 48.0;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: height),
    child: Padding(
      padding: EdgeInsetsDirectional.only(
        start: DesignTokens.componentSheetPadding,
        end: trailing == null
            ? DesignTokens.componentSheetPadding
            : DesignTokens.spacingSm,
      ),
      child: Row(
        spacing: DesignTokens.spacingSm,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppTypography.of(context).title3),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}
