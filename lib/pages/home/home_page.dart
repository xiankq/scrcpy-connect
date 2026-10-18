import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = navigationShell.currentIndex;
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
        final destinations = const [
          (LucideIcons.smartphone, '设备'),
          (LucideIcons.arrowUpDown, '传输'),
          (LucideIcons.settings2, '设置'),
        ];
        if (wide) {
          return withBack(
            Scaffold(
              body: Row(
                children: [
                  SafeArea(
                    child: SizedBox(
                      width: DesignTokens.componentSidebarWidth,
                      child: Padding(
                        padding: const EdgeInsets.all(DesignTokens.spacingMd),
                        child: Glass(
                          padding: const EdgeInsets.all(DesignTokens.spacingXs),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                    child: ListTile(
                                      shape: const StadiumBorder(),
                                      selected: tab == i,
                                      selectedTileColor:
                                          Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? DesignTokens.colorGlassSelectedDark
                                          : DesignTokens.colorGlassSelected,
                                      leading: Icon(destinations[i].$1),
                                      title: Text(destinations[i].$2),
                                      onTap: () => selectTab(i),
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
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacingMd,
                  DesignTokens.spacingZero,
                  DesignTokens.spacingMd,
                  DesignTokens.spacingMd,
                ),
                child: GlassTabBar(
                  destinations: [
                    for (final destination in destinations)
                      GlassDestination(
                        icon: destination.$1,
                        label: destination.$2,
                      ),
                  ],
                  selectedIndex: tab,
                  onSelected: selectTab,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
