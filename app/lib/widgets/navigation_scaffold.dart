import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:scrcpy_connect/widgets/glass/glass_press_feedback.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

class NavigationScaffold extends HookConsumerWidget {
  const NavigationScaffold({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = navigationShell.currentIndex;
    final theme = Theme.of(context);
    final opaque = GlassMaterial.opaque(context);
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
    return withBack(
      Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    DesignTokens.spacingZero,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                  ),
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
                            horizontal: 12,
                            vertical: 8,
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
                    settings: GlassMaterial.navigationBarSettings(context),
                    quality: GlassMaterial.quality(context),
                    indicatorSettings:
                        GlassMaterial.navigationIndicatorSettings(context),
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

  static bool hasSidebar(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_NavigationLayout>()
          ?.sidebar ??
      false;
  static bool isVisible(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_NavigationLayout>()
          ?.visible ??
      true;

  @override
  Widget build(BuildContext context) {
    final visible = ModalRoute.isCurrentOf(context) != false;
    final tab = uri.path.startsWith('/settings') || uri.path == '/preferences'
        ? 2
        : uri.path.startsWith('/transfers') || uri.path.startsWith('/activity')
        ? 1
        : 0;
    return WindowPaneHost(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sizeClass = WindowEnvironment.sizeClassFor(
            constraints.maxWidth,
          );
          final short =
              constraints.maxWidth > constraints.maxHeight &&
              constraints.maxHeight < DesignTokens.componentSheetShortHeight;
          // A narrow phone in landscape still needs the bottom bar. Medium and
          // expanded windows get a persistent navigation plane.
          final sidebar = sizeClass != WindowSizeClass.compact;
          final compactSidebar = sizeClass == WindowSizeClass.medium;
          return _NavigationLayout(
            sidebar: sidebar,
            visible: visible,
            child: !sidebar
                ? child
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
