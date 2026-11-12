import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/activities/activities_provider.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_list_state.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/activities/activities_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('刷新失败留在错误视图且不产生未处理异常，后续可重试', (tester) async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        activityManagementProvider.overrideWithValue(_Activities()),
        deviceListProvider.overrideWith(_Devices.new),
        recoveryStateProvider.overrideWith(_Recovery.new),
        activitiesProvider(deviceId: 'device').overrideWith((ref) async {
          reads++;
          if (reads <= 2) throw StateError('snapshot unavailable');
          return const ActivityCollection(
            activities: [],
            pendingApplications: [],
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: const ActivitiesPage(deviceId: 'device'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法核验活动'), findsOneWidget);
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('暂时无法核验活动'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(find.text('暂无正在进行的活动'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Activities implements ActivityManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices extends DeviceListNotifier {
  @override
  DeviceListState build() => DeviceListState(loading: false);
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}
