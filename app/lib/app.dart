import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/widgets/app_presentation_host.dart';
import 'package:scrcpy_connect/styles/system_visual_preferences.dart';
import 'package:scrcpy_connect/styles/system_typography.dart';

import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;

class ConnectApp extends HookConsumerWidget {
  const ConnectApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appStoreProvider.notifier);
    final dependencies = ref.watch(appDependenciesProvider);
    final views = useMemoized(() => RemoteViews(controller), [
      controller,
      dependencies,
    ]);
    useEffect(() => views.dispose, [views]);
    ref.listen(
      appStoreProvider.select((s) => (s.devices, s.reconciliationPending)),
      (_, _) => views.reconcile(),
    );
    final appSettings = ref.watch(
      appStoreProvider.select((state) => state.settings),
    );
    final navigator = useMemoized(() => GlobalKey<NavigatorState>());
    final router = useMemoized(() => createAppRouter(navigatorKey: navigator), [
      controller,
    ]);
    useEffect(() => router.dispose, [router]);
    final systemVisualPreferences = useMemoized(SystemVisualPreferences.new);
    useListenable(systemVisualPreferences);
    useEffect(() {
      systemVisualPreferences.start();
      return systemVisualPreferences.dispose;
    }, [systemVisualPreferences]);
    final systemTypography = useMemoized(SystemTypography.new);
    useListenable(systemTypography);
    useEffect(() {
      systemTypography.start();
      return systemTypography.dispose;
    }, [systemTypography]);
    final mode = switch (appSettings['appearance']) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    final fontFamily = systemTypography.fontFamily;
    final lightTheme = useMemoized(
      () => _appTheme(Brightness.light, fontFamily),
      [fontFamily],
    );
    final darkTheme = useMemoized(
      () => _appTheme(Brightness.dark, fontFamily),
      [fontFamily],
    );
    return MaterialApp.router(
      title: '邻接',
      restorationScopeId: 'connect-app',
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      builder: (context, child) => RemoteViewsScope(
        views: views,
        child: AppPresentationHost(
          navigator: navigator,
          router: router,
          child: liquid.GlassTheme(
            data: GlassMaterial.theme(context),
            child: liquid.GlassAccessibilityScope(
              reduceTransparency:
                  systemVisualPreferences.reduceTransparency ||
                  MediaQuery.highContrastOf(context) ||
                  liquid.GlassAccessibilityData.of(context).reduceTransparency,
              child: child!,
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData _appTheme(Brightness brightness, String? fontFamily) =>
    ConnectTokens.theme(brightness, fontFamily: fontFamily).copyWith(
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => Transform.flip(
          flipX: Directionality.of(context) == TextDirection.rtl,
          child: const Icon(LucideIcons.chevronLeft),
        ),
        closeButtonIconBuilder: (_) => const Icon(LucideIcons.x),
        drawerButtonIconBuilder: (_) => const Icon(LucideIcons.menu),
        endDrawerButtonIconBuilder: (_) => const Icon(LucideIcons.menu),
      ),
    );
