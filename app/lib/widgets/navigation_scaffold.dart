import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:foldable/foldable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/motion.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

/// 底部导航底边距取 21 与底部安全区中的较大值（designs/design.md「底部导航」）。
const _dockBottomMargin = 21.0;

/// 窄窗根页的底部导航（Ardot 底部导航 37:741）：glass-pill 胶囊高 62、三项各 86、
/// 选中项为 `dock-platter` 托盘。iPhone Duo 竖栏时由库改为竖向胶囊（Ardot 41:1326）。
class NavigationScaffold extends HookConsumerWidget {
  const NavigationScaffold({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = navigationShell.currentIndex;
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final opaque = opaqueGlass(context);
    final reducedMotion = GlassMaterial.reduceMotion(context);
    // 降低透明度只换材质；托盘移动与放大镜只在减少动态时关闭。
    final liquidMotion = !reducedMotion;
    final history = useRef(<int>[0]);
    if (history.value.last != tab) history.value.add(tab);
    void selectTab(int index) {
      if (index != tab) navigationShell.goBranch(index);
    }

    Widget withBack(Widget child) => PopScope(
      canPop: tab == 0 && history.value.length <= 1,
      onPopInvokedWithResult: (popped, _) {
        if (popped) return;
        if (history.value.isNotEmpty) history.value.removeLast();
        navigationShell.goBranch(
          history.value.isEmpty ? 0 : history.value.last,
        );
      },
      child: child,
    );
    final sidebar = AppNavigationShell.hasSidebar(context);
    const destinations = appDestinations;
    final verticalBar = liquid.GlassVerticalBar.maybeOf(context);
    final barHeight = GlassMaterial.navigationHeight(context);
    Widget dock = liquid.GlassIsolationScope(
      isolated: true,
      defaultQuality: GlassMaterial.quality(context),
      child: liquid.GlassTabBar.bottom(
        // Keep the package-owned platter alive when accessibility
        // preferences change; replacing the glass layer here can
        // drop its sampled surface during the next frame.
        key: const ValueKey('app-bottom-navigation'),
        tabs: [
          for (final destination in destinations)
            liquid.GlassTab(icon: Icon(destination.$1), label: destination.$2),
        ],
        // 按住时托盘化为放大镜：各边外扩 8，内容放大 1.16 倍。
        indicatorExpansion: liquidMotion
            ? const EdgeInsets.all(DesignTokens.spacingSm)
            : EdgeInsets.zero,
        indicatorPinchStrength: liquidMotion ? 0.4 : 0,
        magnification: liquidMotion
            ? DesignTokens.componentGlassInteractionScale
            : 1,
        selectedIndex: tab,
        onTabSelected: selectTab,
        horizontalPadding: 0,
        verticalPadding: 0,
        barHeight: barHeight,
        barBorderRadius: barHeight / 2,
        tabPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingSm,
        ),
        iconLabelSpacing: DesignTokens.componentDockItemGap,
        iconSize: DesignTokens.componentDockItemSize,
        labelFontSize: type.tabLabel.fontSize!,
        textStyle: type.tabLabel,
        selectedLabelStyle: type.tabLabel.copyWith(
          fontWeight: type.captionEmphasis.fontWeight,
        ),
        selectedIconColor: colors.onPrimaryContainer,
        selectedLabelColor: colors.onPrimaryContainer,
        unselectedIconColor: colors.textSecondary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.dockPlatter,
        settings: GlassMaterial.settings(context, variant: GlassVariant.pill),
        quality: GlassMaterial.quality(context),
        indicatorSettings: GlassMaterial.navigationIndicatorSettings(context),
        pressScale: liquidMotion
            ? GlassPressMetrics.scaleFor(
                Size(DesignTokens.componentNavigationDockWidth, barHeight),
              )
            : 1,
        interactionGlowColor: DesignTokens.colorGlassRim.withValues(
          alpha: DesignTokens.componentGlassInteractionGlowIntensity,
        ),
        interactionBehavior: liquidMotion
            ? liquid.GlassInteractionBehavior.full
            : opaque
            ? liquid.GlassInteractionBehavior.none
            : liquid.GlassInteractionBehavior.glowOnly,
      ),
    );
    if (verticalBar == null) {
      // 库的横向胶囊即控件边界：在同一形状上叠加阴影与上下高光。
      dock = DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          shadows: glassShadows(context, GlassVariant.pill, opaque: opaque),
        ),
        child: GlassRim(
          variant: GlassVariant.pill,
          shape: const StadiumBorder(),
          visible: !opaque,
          child: dock,
        ),
      );
    }
    final navigationBar = _duoEdgeAttachedBar(
      verticalBar,
      child: Visibility(
        visible: MediaQuery.viewInsetsOf(context).bottom <= 0,
        maintainState: true,
        maintainAnimation: true,
        child: SafeArea(
          // GlassTabBar's vertical layout owns the physical strip. Applying
          // the system's lateral inset a second time would push the capsule
          // back toward the content instead of attaching it to the edge.
          top: false,
          left: verticalBar == null,
          right: verticalBar == null,
          minimum: EdgeInsets.only(
            bottom: verticalBar == null ? _dockBottomMargin : 0,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              verticalBar == null ? DesignTokens.spacingLg : 0,
              0,
              verticalBar == null ? DesignTokens.spacingLg : 0,
              verticalBar == null ? 0 : DesignTokens.spacingMd,
            ),
            child: verticalBar == null
                ? Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.componentNavigationDockWidth,
                      ),
                      child: dock,
                    ),
                  )
                : dock,
          ),
        ),
      ),
    );
    return withBack(
      Scaffold(
        extendBody: true,
        body: navigationShell,
        // Keep the package-owned tab bar mounted while the keyboard changes
        // viewInsets. Offstage removes its layout footprint without tearing
        // down the package state that owns the moving glass indicator.
        bottomNavigationBar: sidebar ? null : navigationBar,
      ),
    );
  }

  /// UIKit's inner Duo inset includes the status cluster, so the package's
  /// vertical layout centres the tab capsule too far inside that reserved
  /// region. The app nav belongs to the physical edge; keep the original
  /// inset for page content and give only this bar the measured 84pt strip.
  Widget _duoEdgeAttachedBar(
    liquid.GlassVerticalBarData? bar, {
    required Widget child,
  }) {
    if (bar == null || bar.width <= liquid.GlassVerticalBarMetrics.stripWidth) {
      return child;
    }
    return liquid.GlassVerticalBar(
      data: liquid.GlassVerticalBarData(
        edge: bar.edge,
        width: liquid.GlassVerticalBarMetrics.stripWidth,
        top: bar.top,
        bottom: bar.bottom,
        collapsesTabBar: bar.collapsesTabBar,
        rowTop: bar.rowTop,
        titleInset: bar.titleInset,
        systemInset: bar.systemInset,
      ),
      child: child,
    );
  }
}

const appDestinations = [
  (AppIcons.navigationDevices, '设备', '/devices'),
  (AppIcons.navigationTransfers, '传输', '/transfers'),
  (AppIcons.navigationSettings, '设置', '/settings'),
];

/// 普通路由共用的导航外壳；沉浸页面位于根 Navigator。
///
/// 600 ≤ W < 840 或 H < 480 时为 72 点导航轨道，W ≥ 840 时为 220 点文字侧栏，
/// 见 designs/design.md「自适应窗口与形态」。
class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({super.key, required this.child, required this.uri});
  final Widget child;
  final Uri uri;

  static _NavigationLayout? _layout(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NavigationLayout>();

  static bool hasSidebar(BuildContext context) =>
      _layout(context)?.sidebar ?? false;
  static bool isVisible(BuildContext context) =>
      _layout(context)?.visible ?? true;

  @override
  Widget build(BuildContext context) {
    final visible = ModalRoute.isCurrentOf(context) != false;
    final tab = uri.path.startsWith('/settings') || uri.path == '/preferences'
        ? 2
        : uri.path.startsWith('/transfers') || uri.path.startsWith('/activity')
        ? 1
        : 0;
    return WindowPaneHost(
      child: FoldAwareBuilder(
        builder: (context, constraints, fold) {
          final window = windowEnvironmentOf(context);
          final sizeClass = WindowEnvironment.sizeClassFor(
            constraints.maxWidth - window.insets.left - window.insets.right,
          );
          final short =
              constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight < AdaptiveWindowMetrics.shortHeight;
          // A narrow phone in landscape still needs the bottom bar. Medium
          // and expanded windows get a persistent navigation plane unless
          // UIKit has already reserved an iPhone Duo vertical bar: in that
          // case the single package-owned GlassTabBar moves its tabs into the
          // system strip and an app rail would duplicate navigation.
          final verticalBar = liquid.GlassVerticalBar.maybeOf(context);
          // The inner Duo display keeps the horizontal tab bar in its upright
          // pose. Its regular size class must not accidentally become a
          // tablet rail just because the window is taller than it is wide.
          final duoInnerPortrait =
              fold.isFoldable &&
              fold.isRegularWidth &&
              constraints.maxHeight > constraints.maxWidth;
          final divider = window.verticalPaneDivider;
          final ownsListDetail =
              uri.path == '/devices' || uri.path == '/transfers';
          const duoPane = AdaptiveWindowMetrics.duoPaneWidth;
          final leadingBar =
              verticalBar?.edge == liquid.GlassVerticalBarEdge.leading;
          final reserved = (verticalBar?.width ?? 0) + DesignTokens.spacingSm;
          final managesDivider =
              ownsListDetail &&
              divider != null &&
              fold.isFoldable &&
              verticalBar != null &&
              divider.left - (leadingBar ? reserved : window.insets.left) >=
                  duoPane &&
              constraints.maxWidth -
                      divider.left -
                      divider.width -
                      (leadingBar ? window.insets.right : reserved) >=
                  duoPane;
          final sidebar =
              verticalBar == null &&
              !duoInnerPortrait &&
              (sizeClass != WindowSizeClass.compact || divider != null);
          final rail = sizeClass == WindowSizeClass.medium || short;
          final requestedWidth = rail
              ? DesignTokens.componentNavigationRailWidth
              : DesignTokens.componentSidebarWidth;
          final sidebarWidth = divider == null
              ? requestedWidth
              : requestedWidth.clamp(0.0, divider.left);
          if (DesktopWindowInsets.of(context) != null) {
            return _NavigationLayout(
              sidebar: sidebar,
              visible: visible,
              child: Scaffold(
                body: _DesktopNavigation(
                  tab: tab,
                  sidebar: sidebar,
                  rail: rail,
                  child: child,
                ),
              ),
            );
          }
          return _NavigationLayout(
            sidebar: sidebar,
            visible: visible,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!sidebar && divider != null && !managesDivider)
                    SizedBox(width: divider.left + divider.width),
                  if (sidebar) ...[
                    ColoredBox(
                      color: AppColors.of(context).card,
                      child: SafeArea(
                        top: false,
                        right: false,
                        bottom: false,
                        child: SizedBox(
                          key: const ValueKey('app-sidebar'),
                          width: sidebarWidth,
                          child: _NavigationPanel(
                            tab: tab,
                            expansion: rail ? 0 : 1,
                            top:
                                MediaQuery.paddingOf(context).top +
                                DesignTokens.spacingXxl,
                          ),
                        ),
                      ),
                    ),
                    if (divider != null) ...[
                      if (divider.left > sidebarWidth)
                        SizedBox(width: divider.left - sidebarWidth),
                      SizedBox(
                        key: const ValueKey('display-feature-reserved'),
                        width: divider.width,
                      ),
                    ],
                  ],
                  Expanded(key: const ValueKey('app-content'), child: child),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 桌面侧栏：跨阈值时宽度逐帧衔接，图标固定在导航轨道中心，文字随展开显现。
class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.tab,
    required this.sidebar,
    required this.rail,
    required this.child,
  });

  final int tab;
  final bool sidebar;
  final bool rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const railWidth = DesignTokens.componentNavigationRailWidth;
    const expanded = DesignTokens.componentSidebarWidth;
    final frame = DesktopWindowInsets.of(context)!;
    final top = math.max(frame.top, MediaQuery.paddingOf(context).top);
    final reducedMotion = GlassMaterial.reduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: sidebar ? (rail ? railWidth : expanded) : 0),
      duration: reducedMotion ? Duration.zero : panelOpenDuration,
      curve: panelCurve,
      child: child,
      builder: (context, width, page) {
        final expansion = ((width - railWidth) / (expanded - railWidth)).clamp(
          0.0,
          1.0,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('app-sidebar'),
              width: width,
              child: Offstage(
                offstage: width == 0,
                child: IgnorePointer(
                  ignoring: !sidebar,
                  child: ExcludeSemantics(
                    excluding: !sidebar,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: AlignmentDirectional.topStart,
                        minWidth: railWidth,
                        maxWidth: math.max(width, railWidth),
                        child: _NavigationPanel(
                          tab: tab,
                          expansion: expansion,
                          // macOS 沉浸标题栏：在原生按钮高度下再留 12。
                          top: top + DesignTokens.spacingMd,
                          draggableTop: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(key: const ValueKey('app-content'), child: page!),
          ],
        );
      },
    );
  }
}

/// 实体侧栏与导航轨道（Ardot 侧栏 41:1264、导航轨道 41:1295），`card` 底。
///
/// [expansion] 为 0 时是 72 点轨道：56 点方块，图形在上、`tab-label` 在下，选中为 `block` 底；
/// 为 1 时是 220 点侧栏：项高 40、圆角 8，图形 24 + `subheadline`，选中为 `block` 底加
/// 3×16 的 `primary` 指示条。中间值逐帧插值，图形始终停在轨道中心。
class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.tab,
    required this.expansion,
    required this.top,
    this.draggableTop = false,
  });

  final int tab;
  final double expansion;
  final double top;
  final bool draggableTop;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    final padding = lerpDouble(
      DesignTokens.spacingSm,
      DesignTokens.spacingMd,
      expansion,
    )!;
    final header = SizedBox(height: top, width: double.infinity);
    return Material(
      color: colors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (draggableTop) DesktopWindowDragArea(child: header) else header,
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                padding,
                0,
                padding,
                DesignTokens.spacingXxl,
              ),
              children: [
                // 应用名只在侧栏显示；轨道保留同一高度，图形位置不随展开移动。
                ExcludeSemantics(
                  excluding: expansion < 1,
                  child: Opacity(
                    opacity: expansion,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spacingXs,
                        0,
                        DesignTokens.spacingXs,
                        DesignTokens.spacingMd,
                      ),
                      child: Text(
                        '邻接',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: type.title3,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < appDestinations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesignTokens.spacingXs,
                    ),
                    child: _NavigationDestination(
                      destination: appDestinations[i],
                      selected: tab == i,
                      expansion: expansion,
                      inset: padding,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 轨道项 56×56（Ardot 41:1299），侧栏项高 40（Ardot 41:1410）。
const _railItemSize = 56.0;

/// 侧栏选中指示条 3×16（Ardot 41:1411）。
const _indicatorWidth = 3.0;

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.destination,
    required this.selected,
    required this.expansion,
    required this.inset,
  });

  final (IconData, String, String) destination;
  final bool selected;
  final double expansion;

  /// 面板左右内距；图形左缘固定在 (72 − 24) / 2。
  final double inset;

  @override
  Widget build(BuildContext context) {
    final (icon, label, path) = destination;
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    const glyph = DesignTokens.componentBarGlyphSize;
    final height = lerpDouble(
      _railItemSize,
      DesignTokens.componentSidebarHeight,
      expansion,
    )!;
    final radius = lerpDouble(
      DesignTokens.roundedMd,
      DesignTokens.roundedSm,
      expansion,
    )!;
    final iconStart =
        (DesignTokens.componentNavigationRailWidth - glyph) / 2 - inset;
    // 图形中心在两种形态下都距项顶 20：轨道为 (56 − 24 − 2 − 14) / 2 + 12。
    final iconTop = (DesignTokens.componentSidebarHeight - glyph) / 2;
    final railColor = selected
        ? colors.onPrimaryContainer
        : colors.textSecondary;
    final iconColor = Color.lerp(railColor, colors.text, expansion)!;
    final railLabel = type.tabLabel.copyWith(
      color: railColor,
      fontWeight: selected ? type.captionEmphasis.fontWeight : null,
    );
    final sideLabel = (selected ? type.label : type.subheadline).copyWith(
      color: colors.text,
    );
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
    );
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? colors.block : colors.card.withAlpha(0),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: shape,
            highlightColor: colors.pressed,
            onTap: () => context.go(path),
            child: ExcludeSemantics(
              child: SizedBox(
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (selected)
                      PositionedDirectional(
                        start: DesignTokens.spacingXs,
                        top: (height - DesignTokens.spacingLg) / 2,
                        child: Opacity(
                          opacity: expansion,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: colors.primary,
                              shape: const StadiumBorder(),
                            ),
                            child: const SizedBox(
                              width: _indicatorWidth,
                              height: DesignTokens.spacingLg,
                            ),
                          ),
                        ),
                      ),
                    PositionedDirectional(
                      start: iconStart,
                      top: iconTop,
                      child: Icon(icon, size: glyph, color: iconColor),
                    ),
                    // 轨道标签在图形下方，随展开淡出。
                    if (expansion < 1)
                      PositionedDirectional(
                        start: 0,
                        top:
                            iconTop + glyph + DesignTokens.componentDockItemGap,
                        width: _railItemSize,
                        child: Opacity(
                          opacity: 1 - expansion,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: railLabel,
                          ),
                        ),
                      ),
                    // 侧栏标签在图形右侧 8，随展开显现。
                    if (expansion > 0)
                      PositionedDirectional(
                        start: iconStart + glyph + DesignTokens.spacingSm,
                        end: DesignTokens.spacingMd,
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Opacity(
                            opacity: expansion,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: sideLabel,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationLayout extends InheritedWidget {
  const _NavigationLayout({
    required this.sidebar,
    required this.visible,
    required super.child,
  });
  final bool sidebar;
  final bool visible;
  @override
  bool updateShouldNotify(_NavigationLayout oldWidget) =>
      sidebar != oldWidget.sidebar || visible != oldWidget.visible;
}
