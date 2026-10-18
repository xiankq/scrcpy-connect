import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/source_preferences/source_preferences_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device focus cannot enable sound without prior user intent', () async {
    final requests = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      requests.add(command);
      return {};
    });
    await controller.focusDevice('phone');
    expect(requests, isEmpty);
    controller.dispose();
  });

  test(
    'follow serially stops the previous source and reuses the current one',
    () async {
      final requests = <(String, Json)>[];
      var current = 'first';
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add((command, params));
        if (command == 'audio.sources') {
          return {
            'sources': [
              {
                'sourceId': 'source-$current',
                'deviceId': current,
                'status': 'playing',
              },
            ],
          };
        }
        if (command == 'audio.start') {
          current = value(params, 'deviceId');
          return {'sourceId': 'source-$current', 'status': 'playing'};
        }
        return {};
      });
      controller.settings = {
        'audioMode': 'follow',
        'audioDevices': ['first'],
      };
      await controller.focusDevice('second');
      expect(requests.map((r) => r.$1), [
        'audio.sources',
        'audio.stop',
        'audio.start',
        'settings.update',
      ]);
      expect(requests[1].$2, {'deviceId': 'first', 'sourceId': 'source-first'});
      expect(controller.settings['audioDevices'], ['second']);
      await controller.focusDevice('second');
      expect(requests.where((r) => r.$1 == 'audio.start'), hasLength(1));
      controller.settings = {...controller.settings, 'audioMode': 'mix'};
      final count = requests.length;
      await controller.focusDevice('third');
      expect(requests, hasLength(count));
      controller.dispose();
    },
  );

  testWidgets(
    'an unconfirmed audio start never claims playing or saves intent',
    (tester) async {
      final requests = <(String, Json)>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        requests.add((command, params));
        return switch (command) {
          'audio.sources' => {'sources': <Json>[]},
          'audio.start' => {'status': 'starting', 'reason': '尚未收到设备声音'},
          _ => {},
        };
      });
      controller.devices = [
        {'id': 'phone', 'name': '手机', 'status': 'connected'},
      ];
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: SourcePreferencesPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('播放此设备声音'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.$1 == 'audio.start').single.$2, {
        'deviceId': 'phone',
      });
      expect(requests.where((r) => r.$1 == 'settings.update'), isEmpty);
      expect(find.text('正在播放'), findsNothing);
      expect(find.text('尚未收到设备声音'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
