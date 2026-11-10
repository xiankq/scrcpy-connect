import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';

import 'support/test_controller.dart';

const original = {
  'id': 'original',
  'address': 'original.local',
  'transport': 'tls',
};

Future<void> tapText(WidgetTester tester, String text) async {
  await Scrollable.ensureVisible(
    tester.element(find.text(text).last),
    alignment: .5,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text(text).last);
  await tester.pump(const Duration(milliseconds: 200));
  final confirmation = find.widgetWithText(FilledButton, '应用并连接');
  if (confirmation.evaluate().isNotEmpty) {
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
  }
}

Future<void> pair(WidgetTester tester, String address) async {
  await tester.enterText(find.byType(TextFormField).at(0), address);
  await tester.enterText(find.byType(TextFormField).at(1), '37123');
  await tester.enterText(find.byType(TextFormField).at(2), '123456');
  await tapText(tester, '配对并连接');
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester, int index) => tester
    .widget<TextFormField>(find.byType(TextFormField).at(index))
    .controller!
    .text;

AppController recordingController(
  List<(String, Json)> calls,
  FutureOr<Json> Function(String, Json) respond, {
  Stream<Json>? events,
}) => createTestController((command, [params = const {}]) async {
  calls.add((command, params));
  return respond(command, params);
}, events: events);

Json request(List<(String, Json)> calls, String command) =>
    calls.singleWhere((call) => call.$1 == command).$2;

Future<GoRouter> mount(
  WidgetTester tester,
  AppController controller, {
  String? location,
}) async {
  controller.loading = false;
  final router = createAppRouter(
    initialLocation: location ?? const AddDeviceRoute().location,
  );
  await tester.pumpWidget(
    TestProviderScope(
      controller: controller,
      child: MaterialApp.router(
        theme: ConnectTokens.theme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    controller.dispose();
  });
  return router;
}

void main() {
  testWidgets(
    'QR reauthorization carries the original device while new QR pairing has no device selector',
    (tester) async {
      for (final deviceId in ['original', null]) {
        final calls = <(String, Json)>[];
        final controller = recordingController(calls, (command, params) async {
          if (command == 'device.info') {
            return original;
          }
          if (command == 'devices.pair.qr') {
            return {
              'attemptId': 'qr-original',
              'payload': 'WIFI:T:ADB;S:test;P:123456;;',
            };
          }
          return {};
        });
        await mount(
          tester,
          controller,
          location: AddDeviceRoute(deviceId: deviceId).location,
        );
        await tapText(tester, '扫码');
        if (deviceId != null) await tapText(tester, '重新生成');
        await tester.pumpAndSettle();
        expect(calls.where((c) => c.$1 == 'devices.pair.qr').map((c) => c.$2), [
          if (deviceId == null) <String, dynamic>{} else {'deviceId': deviceId},
        ]);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'discovery is a secondary page and returns to the original reauthorization form',
    (tester) async {
      final calls = <(String, Json)>[];
      final controller = recordingController(calls, (command, params) async {
        return switch (command) {
          'device.info' => original,
          'devices.discover' => {
            'devices': [
              {
                'name': '发现候选手机',
                'kind': 'pairing',
                'endpoints': [
                  {'address': 'candidate.local', 'port': 37123},
                ],
              },
            ],
          },
          'devices.pair' => {'deviceId': 'original', 'connected': false},
          _ => {},
        };
      });
      final router = await mount(
        tester,
        controller,
        location: const AddDeviceRoute(deviceId: 'original').location,
      );
      expect(calls.where((call) => call.$1 == 'devices.discover'), isEmpty);
      await tester.enterText(find.byType(TextFormField).at(2), '123456');
      await tapText(tester, '发现设备');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/connection/discovery',
      );
      expect(find.text('等待配对'), findsOneWidget);
      await tapText(tester, '发现候选手机');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/connection/add');
      await tapText(tester, '配对并连接');
      await tester.pumpAndSettle();
      final pair = calls.singleWhere((call) => call.$1 == 'devices.pair').$2;
      expect(pair['deviceId'], 'original');
      expect(pair['address'], 'candidate.local');
      expect(pair['port'], 37123);
    },
  );

  testWidgets(
    'unknown paired cleanup blocks return until cancellation succeeds, preserves TLS, and never reuses identity for a new host',
    (tester) async {
      final calls = <(String, Json)>[];
      var cancelConfirmed = false;
      final controller = recordingController(calls, (command, params) async {
        if (command == 'devices.cancel' && !cancelConfirmed) {
          throw const RequestFailure('result_unknown', '取消尚未确认');
        }
        return command == 'devices.pair'
            ? {
                'deviceId': 'paired',
                'paired': true,
                'connected': false,
                'connectionFailure': {
                  'code': 'connection_cleanup_unconfirmed',
                  'message': '候选连接尚未确认释放',
                },
              }
            : {};
      });
      await mount(tester, controller);
      await pair(tester, 'phone.local');
      await tapText(tester, '返回');
      final attempt = request(calls, 'devices.pair')['attemptId'];
      expect(request(calls, 'devices.cancel')['attemptId'], attempt);
      expect(find.text('连接结果待确认'), findsOneWidget);
      expect(find.text('补充连接端口'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(calls.where((c) => c.$1 == 'devices.add'), isEmpty);
      cancelConfirmed = true;
      await tapText(tester, '返回');
      expect(
        calls
            .where((c) => c.$1 == 'devices.cancel')
            .map((c) => c.$2['attemptId']),
        [attempt, attempt],
      );
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('连接设备'), findsOneWidget);
      await tapText(tester, 'IP 连接');
      expect(fieldText(tester, 1), isEmpty);
      expect(find.text('使用手机无线调试主页面的连接端口。'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '5555');
      await tapText(tester, '连接设备');
      await tester.pumpAndSettle();
      final added = calls.singleWhere((call) => call.$1 == 'devices.add').$2;
      expect(added, containsPair('transport', 'tls'));
      expect(added, containsPair('deviceId', 'paired'));
      await tapText(tester, '返回修改');
      await tester.enterText(find.byType(TextFormField).at(0), 'another.local');
      await tapText(tester, '连接设备');
      await tester.pumpAndSettle();
      expect(
        calls
            .where((call) => call.$1 == 'devices.add')
            .last
            .$2
            .containsKey('deviceId'),
        isFalse,
      );
    },
  );

  testWidgets(
    'switching away cancels USB and late QR generation without updating the selected mode',
    (tester) async {
      final usb = Completer<Json>();
      final qr = Completer<Json>();
      final calls = <(String, Json)>[];
      final controller = recordingController(calls, (command, params) async {
        if (command == 'devices.usb') return usb.future;
        if (command == 'devices.pair.qr') return qr.future;
        return {};
      });
      await mount(tester, controller);
      await tapText(tester, 'USB');
      await tapText(tester, '检查连接');
      final attempt = calls
          .singleWhere((call) => call.$1 == 'devices.usb')
          .$2['attemptId'];
      await tapText(tester, '扫码');
      expect(
        calls
            .where((call) => call.$1 == 'devices.cancel')
            .any((call) => call.$2['attemptId'] == attempt),
        isTrue,
      );
      await tapText(tester, 'IP 连接');
      usb.complete({'message': 'stale USB result'});
      qr.complete({
        'attemptId': 'late-qr',
        'payload': 'WIFI:T:ADB;S:test;P:123456;;',
      });
      await tester.pumpAndSettle();
      expect(
        calls
            .where((call) => call.$1 == 'devices.cancel')
            .any((call) => call.$2['attemptId'] == 'late-qr'),
        isTrue,
      );
      expect(find.text('stale USB result'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'QR success immediately preserves encrypted identity when switching to IP',
    (tester) async {
      final events = StreamController<Json>.broadcast();
      final calls = <(String, Json)>[];
      final controller = recordingController(calls, (command, params) async {
        if (command == 'devices.pair.qr') {
          return {
            'attemptId': 'active-qr',
            'payload': 'WIFI:T:ADB;S:test;P:123456;;',
          };
        }
        return {};
      }, events: events.stream);
      await mount(tester, controller);
      addTearDown(events.close);
      await tapText(tester, '扫码');
      await tester.pumpAndSettle();
      events.add({
        'type': 'pairing.changed',
        'data': {
          'attemptId': 'active-qr',
          'status': 'paired',
          'result': {
            'deviceId': 'qr-paired',
            'address': 'qr.local',
            'connected': false,
          },
        },
      });
      await tester.pumpAndSettle();
      await tapText(tester, 'IP 连接');
      expect(find.text('使用手机无线调试主页面的连接端口。'), findsOneWidget);
      expect(fieldText(tester, 1), isEmpty);
      await tester.enterText(find.byType(TextFormField).at(1), '37123');
      await tapText(tester, '连接设备');
      await tester.pumpAndSettle();
      final added = calls.singleWhere((call) => call.$1 == 'devices.add').$2;
      expect(added['transport'], 'tls');
      expect(added['deviceId'], 'qr-paired');
      expect(added['address'], 'qr.local');
    },
  );

  testWidgets(
    'selecting another discovered pairing target clears the earlier completion panel',
    (tester) async {
      final controller = createTestController(
        (command, [params = const {}]) async => switch (command) {
          'devices.pair' => {'deviceId': 'first-paired', 'connected': false},
          'devices.discover' => {
            'devices': [
              {
                'name': '另一台手机',
                'kind': 'pairing',
                'endpoints': [
                  {'address': 'second.local', 'port': 38123},
                ],
              },
            ],
          },
          _ => {},
        },
      );
      await mount(tester, controller);
      await pair(tester, 'first.local');
      expect(find.text('补充连接端口'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tapText(tester, '发现设备');
      await tester.pumpAndSettle();
      await tapText(tester, '另一台手机');
      await tester.pumpAndSettle();
      expect(find.text('补充连接端口'), findsNothing);
      expect(find.text('已配对，尚未连接'), findsNothing);
      expect(find.text('second.local'), findsOneWidget);
    },
  );
}
