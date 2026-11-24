import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

/// 承载正文和反馈的实体内容面；玻璃仅用于独立操作控件。
class ContentSurface extends StatelessWidget {
  const ContentSurface({
    super.key,
    required this.child,
    this.radius = DesignTokens.roundedLg,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// 对话框的正文与动作共用滚动范围，确认框可选用独立玻璃材质。
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
    final theme = Theme.of(context);
    final translucent = glass && !opaqueGlass(context);
    final body = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.componentAlertPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    DefaultTextStyle(
                      style: theme.textTheme.titleMedium!,
                      child: title!,
                    ),
                    const SizedBox(height: DesignTokens.spacingXs),
                  ],
                  DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: content,
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.componentAlertActionsPadding,
                  DesignTokens.spacingMd,
                  DesignTokens.componentAlertActionsPadding,
                  0,
                ),
                child: actions.length == 2
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = DesignTokens.componentAlertActionsGap;
                          final minimum =
                              MediaQuery.textScalerOf(context).scale(
                                2 * DesignTokens.componentAlertButtonHeight,
                              ) +
                              gap;
                          return constraints.maxWidth < minimum
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  spacing: gap,
                                  children: actions,
                                )
                              : Row(
                                  spacing: gap,
                                  children: [
                                    for (final button in actions)
                                      Expanded(child: button),
                                  ],
                                );
                        },
                      )
                    : OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: DesignTokens.componentAlertActionsGap,
                        overflowSpacing: DesignTokens.componentAlertActionsGap,
                        children: actions,
                      ),
              ),
          ],
        ),
      ),
    );
    return Dialog(
      backgroundColor: translucent
          ? DesignTokens.colorTransparent
          : theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingLg,
      ),
      constraints: const BoxConstraints.tightFor(
        width: DesignTokens.componentAlertWidth,
      ),
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(DesignTokens.componentAlertRounded),
        ),
      ),
      clipBehavior: translucent ? Clip.none : Clip.antiAlias,
      child: translucent
          ? Glass(
              variant: GlassVariant.alert,
              radius: DesignTokens.componentAlertRounded,
              child: body,
            )
          : body,
    );
  }
}

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
    barrierColor: _scrim(context),
    barrierDismissible: barrierDismissible,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    animationStyle: reduced
        ? AnimationStyle.noAnimation
        : const AnimationStyle(duration: panelOpenDuration, curve: panelCurve),
    builder: (context) {
      final dialog =
          builder?.call(context) ??
          AppAlertDialog(title: title, content: content!, actions: actions);
      final animation = ModalRoute.of(context)?.animation;
      if (reduced || animation == null) return dialog;
      final progress = animation.drive(CurveTween(curve: panelCurve));
      return SlideTransition(
        position: progress.drive(
          Tween(begin: const Offset(0, .018), end: Offset.zero),
        ),
        child: ScaleTransition(
          scale: progress.drive(Tween(begin: .965, end: 1.0)),
          child: dialog,
        ),
      );
    },
  );
}

/// Flutter 持有模态路由、结果与拖动，内容抽屉始终使用实体面。
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
}) => showModalBottomSheet<T>(
  context: context,
  barrierColor: _scrim(context),
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  constraints: constraints,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  routeSettings: routeSettings,
  anchorPoint: anchorPoint,
  showDragHandle: false,
  backgroundColor:
      Theme.of(context).bottomSheetTheme.modalBackgroundColor ??
      Theme.of(context).colorScheme.surface,
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
        ),
  builder: (context) => enableDrag
      ? Stack(
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top:
                    DesignTokens.componentSheetHandleHeight +
                    2 * DesignTokens.componentSheetHandlePadding,
              ),
              child: builder(context),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: DesignTokens.componentSheetHandlePadding,
              ),
              child: Semantics(
                label: MaterialLocalizations.of(context)
                    .modalBarrierDismissLabel,
                button: true,
                onTap: () => Navigator.pop(context),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      shape: const StadiumBorder(),
                    ),
                    child: const SizedBox(
                      width: DesignTokens.componentSheetHandleWidth,
                      height: DesignTokens.componentSheetHandleHeight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        )
      : builder(context),
);

Color _scrim(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? DesignTokens.componentModalScrimDarkBackgroundColor
    : DesignTokens.componentModalScrimBackgroundColor;
