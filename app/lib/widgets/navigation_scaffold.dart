import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:foldable/foldable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

class NavigationScaffold extends HookConsumerWidget {
  const NavigationScaffold({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = navigationShell.currentIndex;
    final theme = Theme.of(context);
    final opaque = opaqueGlass(context);
    final reducedMotion = GlassMaterial.reduceMotion(context);
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
    final dock = liquid.GlassIsolationScope(
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
        indicatorExpansion: reducedMotion
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingSm,
                vertical: DesignTokens.spacingXs,
              ),
        indicatorPinchStrength: reducedMotion ? 0 : 0.4,
        magnification: reducedMotion ? 1 : 1.15,
        selectedIndex: tab,
        onTabSelected: selectTab,
        horizontalPadding: 0,
        verticalPadding: 0,
        barHeight: GlassMaterial.navigationHeight(context),
        barBorderRadius: DesignTokens.componentNavigationRounded,
        tabPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.componentNavigationPadding,
        ),
        iconLabelSpacing: DesignTokens.spacingMicro,
        iconSize: DesignTokens.componentIconSize,
        labelFontSize: DesignTokens.typographyCaptionFontSize,
        textStyle: theme.textTheme.bodySmall,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        selectedIconColor: theme.colorScheme.primary,
        selectedLabelColor: theme.colorScheme.primary,
        unselectedIconColor: theme.colorScheme.onSurfaceVariant,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicatorColor: opaque
            ? theme.colorScheme.surfaceContainerHigh
            : theme.brightness == Brightness.dark
            ? DesignTokens.colorGlassSelectedDark
            : DesignTokens.colorGlassSelected,
        settings: GlassMaterial.navigationTrackSettings(context),
        quality: GlassMaterial.quality(context),
        indicatorSettings: GlassMaterial.navigationIndicatorSettings(context),
        pressScale: reducedMotion
            ? 1
            : DesignTokens.componentGlassInteractionScale,
        interactionBehavior: reducedMotion
            ? liquid.GlassInteractionBehavior.glowOnly
            : liquid.GlassInteractionBehavior.full,
      ),
    );
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
            bottom: verticalBar == null
                ? DesignTokens.spacingMd
                : DesignTokens.spacingZero,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              verticalBar == null
                  ? DesignTokens.spacingMd
                  : DesignTokens.spacingZero,
              DesignTokens.spacingZero,
              verticalBar == null
                  ? DesignTokens.spacingMd
                  : DesignTokens.spacingZero,
              verticalBar == null
                  ? DesignTokens.spacingZero
                  : DesignTokens.spacingMd,
            ),
            child: verticalBar == null
                ? Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.componentNavigationWidth,
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
        body: ContentArrival(state: tab, child: navigationShell),
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
              constraints.maxHeight <
                  DesignTokens.componentWorkspaceSplitHeight;
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
          final duoPane = DesignTokens.componentWorkspaceDuoPaneWidth;
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
          final compactSidebar = sizeClass == WindowSizeClass.medium || short;
          final desktop = DesktopWindowInsets.of(context);
          final navigationWidth = compactSidebar
              ? DesignTokens.componentSidebarCompactWidth
              : DesignTokens.componentSidebarWidth;
          final page = sidebar && desktop != null
              ? DesktopWindowInsets(
                  left: math.max(0.0, desktop.left - navigationWidth),
                  right: desktop.right,
                  top: desktop.top,
                  child: child,
                )
              : child;
          return _NavigationLayout(
            sidebar: sidebar,
            visible: visible,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!sidebar && divider != null && !managesDivider)
                    SizedBox(width: divider.left + divider.width),
                  if (sidebar)
                    Builder(
                      builder: (context) {
                        final requestedWidth = compactSidebar || short
                            ? DesignTokens.componentSidebarCompactWidth
                            : DesignTokens.componentSidebarWidth;
                        final sidebarWidth = divider == null
                            ? requestedWidth
                            : requestedWidth.clamp(0.0, divider.left);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SafeArea(
                              right: false,
                              minimum: EdgeInsets.only(
                                top: compactSidebar && (desktop?.left ?? 0) > 0
                                    ? desktop!.top
                                    : 0,
                              ),
                              child: SizedBox(
                                key: const ValueKey('app-sidebar'),
                                width: sidebarWidth,
                                height: double.infinity,
                                child: Material(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? DesignTokens
                                            .componentDeviceHeroDarkBackgroundColor
                                      : DesignTokens
                                            .componentWorkspaceSidebarBackgroundColor,
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      compactSidebar
                                          ? DesignTokens.spacingXs
                                          : DesignTokens.spacingSm,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!compactSidebar &&
                                              (desktop?.left ?? 0) > 0)
                                            DesktopWindowDragArea(
                                              child: SizedBox(
                                                height: math.max(
                                                  0,
                                                  desktop!.top -
                                                      DesignTokens.spacingSm,
                                                ),
                                                width: double.infinity,
                                              ),
                                            ),
                                          if (!compactSidebar && !short)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical:
                                                        DesignTokens.spacingXl,
                                                    horizontal:
                                                        DesignTokens.spacingSm,
                                                  ),
                                              child: Text(
                                                '邻接',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineMedium,
                                              ),
                                            ),
                                          for (
                                            var i = 0;
                                            i < appDestinations.length;
                                            i++
                                          )
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: DesignTokens.spacingXs,
                                              ),
                                              child: GlassPressFeedback(
                                                child: ListTile(
                                                  minTileHeight: short
                                                      ? DesignTokens
                                                            .componentIconButtonSize
                                                      : null,
                                                  minVerticalPadding: short
                                                      ? 0
                                                      : null,
                                                  contentPadding:
                                                      compactSidebar || short
                                                      ? const EdgeInsets.symmetric(
                                                          horizontal:
                                                              DesignTokens
                                                                  .spacingXs,
                                                        )
                                                      : null,
                                                  horizontalTitleGap:
                                                      compactSidebar || short
                                                      ? DesignTokens.spacingXs
                                                      : null,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          DesignTokens
                                                              .roundedMd,
                                                        ),
                                                  ),
                                                  selected: tab == i,
                                                  selectedTileColor:
                                                      Theme.of(context)
                                                              .brightness ==
                                                          Brightness.dark
                                                      ? DesignTokens
                                                            .colorGlassSelectedDark
                                                      : DesignTokens
                                                            .colorGlassSelected,
                                                  leading: compactSidebar
                                                      ? null
                                                      : Icon(
                                                          appDestinations[i].$1,
                                                        ),
                                                  title: compactSidebar
                                                      ? Tooltip(
                                                          message:
                                                              appDestinations[i]
                                                                  .$2,
                                                          child: Icon(
                                                            appDestinations[i]
                                                                .$1,
                                                          ),
                                                        )
                                                      : Text(
                                                          appDestinations[i].$2,
                                                        ),
                                                  onTap: () => context.go(
                                                    appDestinations[i].$3,
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
                            if (divider != null) ...[
                              if (divider.left > sidebarWidth)
                                SizedBox(width: divider.left - sidebarWidth),
                              SizedBox(
                                key: const ValueKey('display-feature-reserved'),
                                width: divider.width,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  Expanded(key: const ValueKey('app-content'), child: page),
                ],
              ),
            ),
          );
        },
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
