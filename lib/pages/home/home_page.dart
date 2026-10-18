import 'package:scrcpy_connect/services/app_controller.dart';
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
    final appSettings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
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
    final compactNavigation =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 21;
    final wide = MediaQuery.sizeOf(context).width >= 850;
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
                  width: 244,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 32,
                            horizontal: 12,
                          ),
                          child: Text(
                            '邻接',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        for (var i = 0; i < destinations.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              shape: const StadiumBorder(),
                              selected: tab == i,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .08),
                              leading: Icon(destinations[i].$1),
                              title: Text(destinations[i].$2),
                              onTap: () => selectTab(i),
                            ),
                          ),
                        const Spacer(),
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('你的设备，随手接续。'),
                        ),
                      ],
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
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Glass(
              radius: 999,
              solid: appSettings['reduceTransparency'] == true,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: Semantics(
                        selected: tab == i,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => selectTab(i),
                          child: AnimatedContainer(
                            constraints: const BoxConstraints(minHeight: 56),
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: tab == i
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Flex(
                              mainAxisSize: MainAxisSize.min,
                              direction: compactNavigation
                                  ? Axis.vertical
                                  : Axis.horizontal,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  destinations[i].$1,
                                  size: 20,
                                  color: tab == i
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : null,
                                ),
                                SizedBox(
                                  width: compactNavigation ? 0 : 7,
                                  height: compactNavigation ? 6 : 0,
                                ),
                                Text(
                                  destinations[i].$2,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: tab == i
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                        : null,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }
}
