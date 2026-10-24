import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/activities/devices_workspace_activities_page.dart';

import 'support/test_controller.dart';

void main() {
  testWidgets(
    'confirming device A audio stops its exact activity and preserves B',
    (tester) async {
      final requests = <(String, Json)>[];
      var stopped = false;
      var lists = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add((command, Map.of(params)));
        if (command == 'activities.stop') {
          expect(params, {'activityId': 'audio:source-a'});
          stopped = true;
          return {
            'deviceId': 'device-a',
            'sourceId': 'source-a',
            'status': 'stopped',
          };
        }
        if (command == 'activities.list') {
          lists++;
          return {
            'activities': [
              if (!stopped)
                {
                  'id': 'audio:source-a',
                  'name': '设备声音',
                  'deviceId': 'device-a',
                  'deviceName': '手机 A',
                  'status': 'playing',
                  'canStop': true,
                  'stopImpact': '仅停止手机 A 的设备声音，连接和手机 B 保持原状。',
                },
              {
                'id': 'audio:source-b',
                'name': '设备声音',
                'deviceId': 'device-b',
                'deviceName': '手机 B',
                'status': 'playing',
                'canStop': true,
              },
            ],
          };
        }
        return {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        TestProviderScope(
          controller: controller,
          child: MaterialApp(
            home: ActivitiesPage(controller: controller, deviceId: 'device-a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('手机 A'), findsOneWidget);
      expect(find.text('手机 B'), findsNothing);
      expect(find.text('设备声音'), findsOneWidget);
      expect(find.byTooltip('正在播放'), findsOneWidget);
      final rowA = find.byKey(const ValueKey('audio:source-a'));
      await tester.tap(find.descendant(of: rowA, matching: find.text('停止')));
      await tester.pumpAndSettle();
      expect(find.text('仅停止手机 A 的设备声音，连接和手机 B 保持原状。'), findsOneWidget);
      expect(requests.where((r) => r.$1 == 'activities.stop'), isEmpty);
      await tester.tap(find.text('停止活动'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'activities.stop'), hasLength(1));
      expect(lists, greaterThan(1));
      expect(find.textContaining('手机 A'), findsNothing);
      expect(find.textContaining('手机 B'), findsNothing);
      expect(find.text('设备声音'), findsNothing);
      expect(find.text('暂无正在进行的活动'), findsOneWidget);
      expect(
        requests
            .where((r) => r.$1 == 'activities.list')
            .every((r) => r.$2['deviceId'] == 'device-a'),
        isTrue,
      );
      expect(
        requests.where(
          (r) =>
              r.$1 == 'devices.disconnect' ||
              r.$1 == 'session.stop' ||
              r.$1 == 'observation.stop',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
