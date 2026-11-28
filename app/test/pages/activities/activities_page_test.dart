import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/activities/activities_provider.dart';
import 'package:scrcpy_connect/core/activities/activity_management_provider.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/activities/activities_page.dart';
import 'package:scrcpy_connect/styles/theme.dart';

import '../../support/fixed_state.dart';

void main() {
  testWidgets('刷新失败留在错误视图且不产生未处理异常，后续可重试', (tester) async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        activityManagementProvider.overrideWithValue(_Activities()),
        deviceListProvider.overrideWith(FixedDeviceList.new),
        recoveryStateProvider.overrideWith(FixedRecovery.new),
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
    expect(find.text('暂时无法读取活动'), findsOneWidget);
    expect(find.textContaining('snapshot unavailable'), findsNothing);
    expect(find.text('请稍后重试。'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('暂时无法读取活动'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('重试'));
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
