import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences_state.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';

void main() {
  testWidgets(
    'keeps the single bottom glass bar mounted when transparency changes',
    (tester) async {
      final oldSize = tester.view.physicalSize;
      final oldRatio = tester.view.devicePixelRatio;
      addTearDown(() {
        tester.view
          ..physicalSize = oldSize
          ..devicePixelRatio = oldRatio;
      });
      tester.view
        ..physicalSize = const Size(402, 844)
        ..devicePixelRatio = 1;

      final reduceTransparency = ValueNotifier(false);
      addTearDown(reduceTransparency.dispose);
      final router = createAppRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceListProvider.overrideWith(_Devices.new),
            recoveryStateProvider.overrideWith(_Recovery.new),
            preferencesProvider.overrideWith(_Preferences.new),
          ],
          child: MaterialApp.router(
            theme: ConnectTokens.theme(Brightness.light),
            routerConfig: router,
            builder: (context, child) => ValueListenableBuilder<bool>(
              valueListenable: reduceTransparency,
              builder: (context, reduced, _) =>
                  GlassPreferences(reduceTransparency: reduced, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      const key = ValueKey('app-bottom-navigation');
      final first = tester.element(find.byKey(key));
      expect(find.byKey(key), findsOneWidget);

      reduceTransparency.value = true;
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byKey(key), findsOneWidget);
      expect(tester.element(find.byKey(key)), same(first));
      expect(tester.takeException(), isNull);
    },
  );
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}

class _Devices extends DeviceListNotifier {
  @override
  DeviceListState build() => DeviceListState(loading: false);
}

class _Preferences extends PreferencesNotifier {
  @override
  PreferencesState build() => PreferencesState();
}
