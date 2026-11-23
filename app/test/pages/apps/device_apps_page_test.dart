import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/apps/device_apps_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';

void main() {
  const device = DeviceSnapshot(id: 'phone');
  final provider = installedDeviceAppsProvider(device.id);

  testWidgets('a fast first read goes straight to the confirmed empty state', (
    tester,
  ) async {
    final result = Completer<List<DeviceApp>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryStateProvider.overrideWith(_Recovery.new),
          provider.overrideWith((_) => result.future),
        ],
        child: const MaterialApp(home: DeviceAppsPage(device: device)),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SkeletonBlock), findsNothing);
    result.complete([]);
    await tester.pumpAndSettle();

    expect(find.text('没有可显示的应用'), findsOneWidget);
    expect(find.byType(LoadingSkeleton), findsNothing);
  });

  testWidgets(
    'a slow first read leaves search usable and announces one region',
    (tester) async {
      final result = Completer<List<DeviceApp>>();
      tester.view
        ..physicalSize = const Size(320, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recoveryStateProvider.overrideWith(_Recovery.new),
            provider.overrideWith((_) => result.future),
          ],
          child: MaterialApp(
            theme: ConnectTokens.theme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                padding: const EdgeInsets.only(top: 36, bottom: 24),
                disableAnimations: true,
                highContrast: true,
              ),
              child: child!,
            ),
            home: const DeviceAppsPage(device: device),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 149));
      expect(find.byType(SkeletonBlock), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.bySemanticsLabel('正在读取'), findsOneWidget);
      expect(find.text('没有可显示的应用'), findsNothing);

      await tester.enterText(find.byType(TextField), '相机');
      result.complete([]);
      await tester.pumpAndSettle();

      expect(find.text('相机'), findsOneWidget);
      expect(find.text('未找到应用'), findsOneWidget);
      expect(find.bySemanticsLabel('正在读取'), findsNothing);
    },
  );

  testWidgets('refresh keeps a previously confirmed list state visible', (
    tester,
  ) async {
    final refresh = Completer<List<DeviceApp>>();
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        recoveryStateProvider.overrideWith(_Recovery.new),
        provider.overrideWith((_) => reads++ == 0 ? [] : refresh.future),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DeviceAppsPage(device: device)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有可显示的应用'), findsOneWidget);

    await tester.tap(find.text('重新检查'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(reads, 2);
    expect(find.text('没有可显示的应用'), findsOneWidget);
    expect(find.byType(LoadingSkeleton), findsNothing);

    refresh.complete([]);
    await tester.pumpAndSettle();
  });
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}
