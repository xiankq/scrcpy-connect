import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

class HomePage extends HookConsumerWidget {
  const HomePage({super.key, required this.navigationShell});
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final shortLandscape =
            constraints.maxWidth > constraints.maxHeight &&
            constraints.maxHeight < DesignTokens.componentSheetShortHeight;
        final destinations = const [
          (LucideIcons.smartphone, '设备'),
          (LucideIcons.arrowUpDown, '传输'),
          (LucideIcons.settings2, '设置'),
        ];
        if (wide || shortLandscape) {
          return withBack(
            Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SafeArea(
                    child: SizedBox(
                      width: shortLandscape
                          ? DesignTokens.componentSidebarCompactWidth
                          : DesignTokens.componentSidebarWidth,
                      child: Padding(
                        padding: EdgeInsets.all(
                          shortLandscape
                              ? DesignTokens.spacingXs
                              : DesignTokens.spacingMd,
                        ),
                        child: Glass(
                          padding: const EdgeInsets.all(DesignTokens.spacingXs),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!shortLandscape)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: DesignTokens.spacingXl,
                                      horizontal: DesignTokens.spacingSm,
                                    ),
                                    child: Text(
                                      '邻接',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                  ),
                                for (var i = 0; i < destinations.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: DesignTokens.spacingXs,
                                    ),
                                    child: GlassPressFeedback(
                                      child: ListTile(
                                        minTileHeight: shortLandscape
                                            ? DesignTokens
                                                  .componentIconButtonSize
                                            : null,
                                        minVerticalPadding: shortLandscape
                                            ? 0
                                            : null,
                                        contentPadding: shortLandscape
                                            ? const EdgeInsets.symmetric(
                                                horizontal:
                                                    DesignTokens.spacingXs,
                                              )
                                            : null,
                                        horizontalTitleGap: shortLandscape
                                            ? DesignTokens.spacingXs
                                            : null,
                                        shape: const StadiumBorder(),
                                        selected: tab == i,
                                        selectedTileColor:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? DesignTokens
                                                  .colorGlassSelectedDark
                                            : DesignTokens.colorGlassSelected,
                                        leading: Icon(destinations[i].$1),
                                        title: Text(destinations[i].$2),
                                        onTap: () => selectTab(i),
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
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          );
        }
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
                        key: ValueKey(reducedMotion),
                        tabs: [
                          for (final destination in destinations)
                            liquid.GlassTab(
                              icon: Icon(destination.$1),
                              label: destination.$2,
                            ),
                        ],
                        selectedIndex: tab,
                        onTabSelected: selectTab,
                        horizontalPadding: 0,
                        verticalPadding: 0,
                        barHeight: GlassMaterial.navigationHeight(context),
                        barBorderRadius:
                            DesignTokens.componentNavigationRounded,
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
                        unselectedLabelColor:
                            theme.colorScheme.onSurfaceVariant,
                        indicatorColor: opaque
                            ? theme.colorScheme.surfaceContainerHigh
                            : theme.brightness == Brightness.dark
                            ? DesignTokens.colorGlassSelectedDark
                            : DesignTokens.colorGlassSelected,
                        settings: GlassMaterial.settings(context).copyWith(
                          shadow:
                              !opaque && theme.brightness == Brightness.light
                              ? const [
                                  BoxShadow(
                                    color: ConnectTokens.shadow,
                                    blurRadius: ConnectTokens.shadowBlur,
                                    offset: Offset(
                                      0,
                                      ConnectTokens.shadowOffset,
                                    ),
                                  ),
                                ]
                              : const [],
                        ),
                        quality: GlassMaterial.quality(context),
                        indicatorSettings: GlassMaterial.navigationLensSettings(
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
        );
      },
    );
  }
}
