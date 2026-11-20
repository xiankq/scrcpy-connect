import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:foldable/foldable.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

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
    if (AppNavigationShell.hasSidebar(context)) {
      return withBack(navigationShell);
    }
    const destinations = appDestinations;
    final verticalBar = liquid.GlassVerticalBar.maybeOf(context);
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
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              verticalBar == null
                  ? DesignTokens.spacingMd
                  : DesignTokens.spacingZero,
              DesignTokens.spacingZero,
              verticalBar == null
                  ? DesignTokens.spacingMd
                  : DesignTokens.spacingZero,
              DesignTokens.spacingMd,
            ),
            child: liquid.GlassIsolationScope(
              isolated: true,
              defaultQuality: GlassMaterial.quality(context),
              child: liquid.GlassTabBar.bottom(
                // Keep the package-owned platter alive when accessibility
                // preferences change; replacing the glass layer here can
                // drop its sampled surface during the next frame.
                key: const ValueKey('app-bottom-navigation'),
                tabs: [
                  for (final destination in destinations)
                    liquid.GlassTab(
                      icon: Icon(destination.$1),
                      label: destination.$2,
                    ),
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
                labelFontSize: theme.textTheme.labelLarge!.fontSize!,
                textStyle: theme.textTheme.labelLarge,
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
                indicatorSettings: GlassMaterial.navigationIndicatorSettings(
                  context,
                ),
                pressScale: reducedMotion
                    ? 1
                    : DesignTokens.componentGlassInteractionScale,
                interactionBehavior: reducedMotion
                    ? liquid.GlassInteractionBehavior.glowOnly
                    : liquid.GlassInteractionBehavior.full,
              ),
            ),
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
        bottomNavigationBar: navigationBar,
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
  (LucideIcons.smartphone, '设备', '/devices'),
  (LucideIcons.arrowUpDown, '传输', '/transfers'),
  (LucideIcons.settings2, '设置', '/settings'),
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
          final sizeClass = WindowEnvironment.sizeClassFor(
            constraints.maxWidth,
          );
          final short =
              constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight < DesignTokens.componentSheetShortHeight;
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
          final divider = windowEnvironmentOf(context).verticalPaneDivider;
          final sidebar =
              verticalBar == null &&
              !duoInnerPortrait &&
              (sizeClass != WindowSizeClass.compact || divider != null);
          final compactSidebar = sizeClass == WindowSizeClass.medium;
          final singlePaneChild = !sidebar && divider != null
              ? Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: (constraints.maxWidth - divider.left - divider.width)
                        .clamp(0.0, constraints.maxWidth)
                        .toDouble(),
                    child: child,
                  ),
                )
              : child;
          return _NavigationLayout(
            sidebar: sidebar,
            visible: visible,
            child: !sidebar
                ? singlePaneChild
                : Scaffold(
                    body: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Builder(
                          builder: (context) {
                            final divider = windowEnvironmentOf(context)
                                .verticalPaneDivider;
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
                                  child: SizedBox(
                                    key: const ValueKey('app-sidebar'),
                                    width: sidebarWidth,
                                    height: double.infinity,
                                    child: Padding(
                                      padding: EdgeInsets.all(
                                        short
                                            ? DesignTokens.spacingXs
                                            : DesignTokens.spacingMd,
                                      ),
                                      child: ContentSurface(
                                        padding: const EdgeInsets.all(
                                          DesignTokens.spacingXs,
                                        ),
                                        child: SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (!compactSidebar && !short)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: DesignTokens
                                                            .spacingXl,
                                                        horizontal: DesignTokens
                                                            .spacingSm,
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
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: DesignTokens
                                                            .spacingXs,
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
                                                          compactSidebar ||
                                                              short
                                                          ? const EdgeInsets.symmetric(
                                                              horizontal:
                                                                  DesignTokens
                                                                      .spacingXs,
                                                            )
                                                          : null,
                                                      horizontalTitleGap:
                                                          compactSidebar ||
                                                              short
                                                          ? DesignTokens
                                                                .spacingXs
                                                          : null,
                                                      shape:
                                                          const StadiumBorder(),
                                                      selected: tab == i,
                                                      selectedTileColor:
                                                          Theme.of(context)
                                                                  .brightness ==
                                                              Brightness.dark
                                                          ? DesignTokens
                                                                .colorGlassSelectedDark
                                                          : DesignTokens
                                                                .colorGlassSelected,
                                                      leading: Icon(
                                                        appDestinations[i].$1,
                                                      ),
                                                      title: compactSidebar
                                                          ? null
                                                          : Text(
                                                              appDestinations[i]
                                                                  .$2,
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
                                    SizedBox(
                                      width: divider.left - sidebarWidth,
                                    ),
                                  SizedBox(
                                    key: const ValueKey(
                                      'display-feature-reserved',
                                    ),
                                    width: divider.width,
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        Expanded(child: child),
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
