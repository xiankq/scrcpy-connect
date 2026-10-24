import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

import 'design_tokens.g.dart';
import 'glass_preferences.dart';
import 'glass_geometry.dart';
import 'glass_material.dart';
import 'connect_theme.dart';
import 'glass_press_feedback.dart';

/// 带玻璃提示的普通图标动作；表面、命中几何、焦点和手势识别器仍由 Material 图标按钮负责。
class GlassActionIcon extends StatelessWidget {
  const GlassActionIcon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
    this.color,
    this.padding,
    this.constraints,
    this.visualDensity,
    this.style,
    this.alignment = Alignment.center,
    this.disabledColor,
    this.focusNode,
    this.autofocus = false,
    this.enableFeedback,
    this.isSelected,
    this.selectedIcon,
    this.onLongPress,
    this.mouseCursor,
  });
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final VisualDensity? visualDensity;
  final ButtonStyle? style;
  final AlignmentGeometry alignment;
  final Color? disabledColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool? enableFeedback;
  final bool? isSelected;
  final Widget? selectedIcon;
  final VoidCallback? onLongPress;
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: icon,
      onPressed: onPressed,
      iconSize: iconSize,
      color: color,
      padding: padding,
      constraints: constraints,
      visualDensity: visualDensity,
      style: style,
      alignment: alignment,
      disabledColor: disabledColor,
      focusNode: focusNode,
      autofocus: autofocus,
      enableFeedback: enableFeedback,
      isSelected: isSelected,
      selectedIcon: selectedIcon,
      onLongPress: onLongPress,
      mouseCursor: mouseCursor,
    );
    return tooltip == null
        ? button
        : GlassTooltip(message: tooltip!, child: button);
  }
}

/// 内容与其他控件采用同一浮动材质的提示。
class GlassTooltip extends StatelessWidget {
  const GlassTooltip({
    super.key,
    required this.message,
    required this.child,
    this.triggerMode,
  });

  final String message;
  final Widget child;
  final TooltipTriggerMode? triggerMode;

  @override
  Widget build(BuildContext context) => Tooltip(
    richMessage: _GlassTooltipSpan(
      message: message,
      child: _GlassTooltipMaterial(
        message: message,
        reduceTransparency: GlassPreferences.reduced(context),
        textStyle: Theme.of(context).textTheme.bodySmall!
            .copyWith(color: Theme.of(context).colorScheme.onSurface),
        textScaler: MediaQuery.textScalerOf(context),
      ),
    ),
    // 即使可见内容是嵌入的材质 widget，Tooltip 语义仍须公开提示字符串。
    excludeFromSemantics: false,
    ignorePointer: true,
    triggerMode: triggerMode,
    decoration: const BoxDecoration(color: DesignTokens.colorTransparent),
    padding: EdgeInsets.zero,
    child: child,
  );
}

class _GlassTooltipMaterial extends StatelessWidget {
  const _GlassTooltipMaterial({
    required this.message,
    required this.reduceTransparency,
    required this.textStyle,
    required this.textScaler,
  });
  final String message;
  final bool reduceTransparency;
  final TextStyle textStyle;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Tooltip 持有调度和焦点语义，外层淡入淡出就是真实显示动画。
      // shader 可见性跟随同一动画，不另建计时器或可见性标志。
      final animation =
          context.findAncestorWidgetOfExactType<FadeTransition>()?.opacity ??
          const AlwaysStoppedAnimation<double>(1);
      final span = TextSpan(text: message, style: textStyle);
      final painter =
          TextPainter(
            text: span,
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          )..layout(
            maxWidth: math.max(
              0,
              constraints.maxWidth - 2 * DesignTokens.spacingSm,
            ),
          );
      final size = Size(
        painter.width + 2 * DesignTokens.spacingSm,
        painter.height + 2 * DesignTokens.spacingXs,
      );
      painter.dispose();
      final expansion = glassMotionExpansion(
        size,
        DesignTokens.componentGlassMaterializeScale,
        centered: true,
      );
      return liquid.GlassMaterializeTransition(
        animation: animation,
        scaleFrom: DesignTokens.componentGlassMaterializeScale,
        child: GlassPreferences(
          reduceTransparency: reduceTransparency,
          child: _GlassOverlayCard(
            radius: DesignTokens.roundedMd,
            clipExpansion: expansion,
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingSm,
              vertical: DesignTokens.spacingXs,
            ),
            child: RichText(textScaler: textScaler, text: span),
          ),
        ),
      );
    },
  );
}

/// 库卡片持有玻璃表面；Flutter 保留覆盖层布局、焦点和滚动。
/// GlassCard 不公开 clipExpansion，因此局部图层提供动画纹理余量。
class _GlassOverlayCard extends StatelessWidget {
  const _GlassOverlayCard({
    required this.child,
    required this.radius,
    required this.padding,
    required this.clipExpansion,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsets clipExpansion;

  @override
  Widget build(BuildContext context) => GlassSurfaceGroup.isolated(
    clipExpansion: clipExpansion,
    child: Builder(
      builder: (context) {
        if (opaqueGlass(context) || !ImageFilter.isShaderFilterSupported) {
          return Glass(
            solid: !ImageFilter.isShaderFilterSupported,
            radius: radius,
            padding: padding,
            clipExpansion: clipExpansion,
            child: child,
          );
        }
        if (!GlassMaterial.isInitialized) {
          throw StateError(
            'Await GlassMaterial.initialize() before mounting glass overlays.',
          );
        }
        final dark = Theme.of(context).brightness == Brightness.dark;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: dark ? ConnectTokens.shadowDark : ConnectTokens.shadow,
                blurRadius: ConnectTokens.shadowBlur,
                offset: const Offset(0, ConnectTokens.shadowOffset),
              ),
            ],
          ),
          child: liquid.GlassCard(
            shape: liquid.LiquidRoundedSuperellipse(borderRadius: radius),
            padding: padding,
            quality: liquid.GlassQuality.premium,
            clipBehavior: Clip.antiAlias,
            child: Material(type: MaterialType.transparency, child: child),
          ),
        );
      },
    ),
  );
}

// 以材质 widget 替换常规绘制装饰时，保留 Tooltip 文本语义和 Flutter 的 byTooltip 查找。
class _GlassTooltipSpan extends WidgetSpan {
  const _GlassTooltipSpan({required this.message, required super.child});
  final String message;

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) => buffer.write(message);
}

/// 采用透明生产玻璃材质的可滚动提示布局。
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({
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
    backgroundColor: DesignTokens.colorTransparent,
    surfaceTintColor: DesignTokens.colorTransparent,
    elevation: 0,
    clipBehavior: Clip.none,
    child: LayoutBuilder(
      builder: (context, constraints) => _GlassOverlayCard(
        clipExpansion: glassMotionExpansion(
          Size(constraints.maxWidth, constraints.maxHeight),
          DesignTokens.componentGlassMaterializeScale,
          centered: true,
        ),
        radius: DesignTokens.componentSheetRounded,
        padding: const EdgeInsets.all(DesignTokens.componentSheetPadding),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                DefaultTextStyle(
                  style: Theme.of(context).textTheme.titleLarge!,
                  child: title!,
                ),
                const SizedBox(height: DesignTokens.spacingMd),
              ],
              DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!,
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
    ),
  );
}

/// 具有原生材质化和普通对话框焦点约束的模态提示。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  WidgetBuilder? builder,
  Widget? title,
  Widget? content,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
  RouteSettings? routeSettings,
}) {
  assert(builder != null || content != null);
  final reduceTransparency = GlassPreferences.reduced(context);
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return Navigator.of(context, rootNavigator: true).push<T>(
    _GlassDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      settings: routeSettings,
      pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
        GlassPreferences(
          reduceTransparency: reduceTransparency,
          child: SafeArea(
            child: Builder(
              builder:
                  builder ??
                  (context) => GlassAlertDialog(
                    title: title,
                    content: content!,
                    actions: actions,
                  ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          liquid.GlassMaterializeTransition(
            animation: animation,
            scaleFrom: DesignTokens.componentGlassMaterializeScale,
            child: child,
          ),
    ),
  );
}

class _GlassDialogRoute<T> extends RawDialogRoute<T> {
  _GlassDialogRoute({
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.transitionBuilder,
    super.settings,
  }) : super(
         barrierColor: liquid.GlassDefaults.barrierColor,
         transitionDuration: liquid.GlassDefaults.materializeDuration,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  @override
  Duration get reverseTransitionDuration =>
      liquid.GlassDefaults.dematerializeDuration;
}

/// 保留 Flutter 的模态路由、结果和拖动所有权。
/// 原生 sheet 提供动态材质，不另建关闭识别器，也不接管内容滚动控制器。
Future<T?> showGlassModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  BoxConstraints? constraints,
  bool isDismissible = true,
  bool enableDrag = true,
  RouteSettings? routeSettings,
}) {
  final reduceTransparency = GlassPreferences.reduced(context);
  final reducedMotion = liquid.GlassAccessibilityData.of(context).reduceMotion;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    constraints: constraints,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    routeSettings: routeSettings,
    showDragHandle: false,
    backgroundColor: DesignTokens.colorTransparent,
    elevation: 0,
    clipBehavior: Clip.none,
    sheetAnimationStyle: reducedMotion ? AnimationStyle.noAnimation : null,
    builder: (context) => GlassPreferences(
      reduceTransparency: reduceTransparency,
      child: Builder(
        builder: (context) {
          final opaque =
              opaqueGlass(context) || !ImageFilter.isShaderFilterSupported;
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (enableDrag)
                Padding(
                  padding: const EdgeInsets.all(
                    DesignTokens.componentSheetHandlePadding,
                  ),
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: MaterialLocalizations.of(context)
                          .modalBarrierDismissLabel,
                      onTap: () => Navigator.maybePop(context),
                      child: SizedBox(
                        width: DesignTokens.componentSheetHandleWidth,
                        height: DesignTokens.componentSheetHandleHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.roundedFull,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Flexible(child: builder(context)),
            ],
          );
          if (opaque) {
            const corners = BorderRadius.vertical(
              top: Radius.circular(DesignTokens.componentSheetRounded),
            );
            return GlassPressFeedback(
              radius: DesignTokens.componentSheetRounded,
              child: ClipRSuperellipse(
                borderRadius: corners,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: corners,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: content,
                  ),
                ),
              ),
            );
          }
          if (!GlassMaterial.isInitialized) {
            throw StateError(
              'Await GlassMaterial.initialize() before mounting glass overlays.',
            );
          }
          return GlassPressFeedback(
            radius: DesignTokens.componentSheetRounded,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // 原生镜片获得有限范围和纹理余量；应用内容保留自身视口与控制器。
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final expansion = glassMotionExpansion(
                            Size(constraints.maxWidth, constraints.maxHeight),
                            1 +
                                (DesignTokens.componentGlassInteractionScale -
                                        1) *
                                    (1 +
                                        DesignTokens
                                            .componentGlassInteractionStretch),
                          );
                          return boundGlassSampling(
                            liquid.AdaptiveGlass(
                              shape:
                                  const liquid.LiquidVerticalRoundedSuperellipse(
                                    topRadius:
                                        DesignTokens.componentSheetRounded,
                                    bottomRadius: 0,
                                  ),
                              settings: Glass.optics(
                                brightness: Theme.of(context).brightness,
                              ),
                              quality: liquid.GlassQuality.premium,
                              allowElevation: false,
                              clipExpansion: expansion,
                              child: const SizedBox.expand(),
                            ),
                            expansion: expansion,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                ClipRSuperellipse(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(DesignTokens.componentSheetRounded),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: content,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
