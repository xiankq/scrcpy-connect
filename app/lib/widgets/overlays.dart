import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';

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

/// 对话框正文和动作保持可滚动，使用不透明的主题表面。
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
  });

  final Widget? title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Theme.of(context).colorScheme.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DesignTokens.componentSheetRounded),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(DesignTokens.componentSheetPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              DefaultTextStyle(
                style: Theme.of(context).textTheme.headlineMedium!,
                child: title!,
              ),
              const SizedBox(height: DesignTokens.spacingMd),
            ],
            DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyLarge!,
              child: content,
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: DesignTokens.spacingMd),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: DesignTokens.spacingXs,
                overflowSpacing: DesignTokens.spacingXs,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    ),
  );
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
  showDragHandle: enableDrag,
  backgroundColor: Theme.of(context).colorScheme.surface,
  elevation: 0,
  shape: const RoundedRectangleBorder(
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
  builder: builder,
);

Color _scrim(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? DesignTokens.componentModalScrimDarkBackgroundColor
    : DesignTokens.componentModalScrimBackgroundColor;
