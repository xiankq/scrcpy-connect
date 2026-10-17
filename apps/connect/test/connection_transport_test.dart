import 'support/test_controller.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

class _Backend {
  _Backend({this.service, this.record});

  final Json? service;
  final Json? record;
  final calls = <(String, Json)>[];
  late final controller = createTestController(request)..loading = false;

  Future<Json> request(String command, [Json params = const {}]) async {
    calls.add((command, Map<String, dynamic>.from(params)));
    return switch (command) {
      'devices.discover' => {'devices': [if (service != null) service]},
      'device.info' => record ?? {},
      'devices.add' => {
        'deviceId': record?['id'] ?? 'new-device',
        'device': {'id': record?['id'] ?? 'new-device', 'status': 'offline'},
      },
      'devices.pair' => {'deviceId': 'paired-device', 'connected': false},
      'devices.list' => {'devices': <Json>[]},
      _ => {},
    };
  }
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Backend backend,
  String location,
) async {
  final router = createAppRouter(initialLocation: location);
  await tester.pumpWidget(
    TestProviderScope(
      controller: backend.controller,
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
    backend.controller.dispose();
  });
  return router;
}

Future<Json> _submit(WidgetTester tester, _Backend backend) async {
  await Scrollable.ensureVisible(
    tester.element(find.text('连接设备')),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('连接设备'));
  await tester.pumpAndSettle();
  final added = backend.calls.singleWhere((call) => call.$1 == 'devices.add');
  final connected = backend.calls.singleWhere(
    (call) => call.$1 == 'devices.connect',
  );
  expect(connected.$2['attemptId'], added.$2['attemptId']);
  expect(connected.$2['deviceId'], backend.record?['id'] ?? 'new-device');
  return added.$2;
}

void main() {
  for (final kind in ['tls', 'tcp']) {
    testWidgets(
      'unknown discovered $kind service keeps its type across the typed route and add',
      (tester) async {
        final backend = _Backend(
          service: {
            'instance': 'unknown-service',
            'kind': kind,
            'trusted': false,
            'endpoints': [
              {'address': '192.0.2.10', 'port': 37123},
            ],
          },
        );
        final router = await _mount(
          tester,
          backend,
          const DiscoveryRoute().location,
        );
        await tester.tap(find.text('unknown-service'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.queryParameters['transport'],
          kind,
        );
        final added = await _submit(tester, backend);
        expect(added['transport'], kind);
        expect(added['address'], '192.0.2.10');
        expect(added['port'], 37123);
        expect(added.containsKey('deviceId'), isFalse);
      },
    );
  }

  testWidgets('manual wireless requires TLS even on port 5555', (tester) async {
    final backend = _Backend();
    await _mount(
      tester,
      backend,
      const ConnectionFormRoute(address: 'phone.local', port: '5555').location,
    );
    final added = await _submit(tester, backend);
    expect(added['transport'], 'tls');
    expect(added['port'], 5555);
  });

  testWidgets('manual legacy TCP is an explicit choice independent of port', (
    tester,
  ) async {
    final backend = _Backend();
    await _mount(
      tester,
      backend,
      const ConnectionFormRoute(address: 'phone.local', port: '37123').location,
    );
    await tester.tap(find.text('现代无线调试（加密）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧版 TCP（USB 授权后开启）').last);
    await tester.pumpAndSettle();
    expect(find.text('填写已开启的 TCP 连接信息'), findsOneWidget);
    final added = await _submit(tester, backend);
    expect(added['transport'], 'tcp');
    expect(added['port'], 37123);
  });

  for (final record in <Json>[
    {'id': 'known-device', 'transport': 'tls'},
    {'id': 'known-device', 'transport': 'tcp', 'guid': 'paired-guid'},
    {'id': 'known-device', 'transport': 'tcp'},
  ]) {
    final expected = record['guid'] != null || record['transport'] == 'tls'
        ? 'tls'
        : 'tcp';
    testWidgets(
      'record ${record['transport']} guid=${record['guid']} keeps $expected on manual update',
      (tester) async {
        final backend = _Backend(record: {...record, 'status': 'offline'});
        await _mount(
          tester,
          backend,
          const ConnectionFormRoute(
            deviceId: 'known-device',
            address: 'phone.local',
            port: '37123',
          ).location,
        );
        final added = await _submit(tester, backend);
        expect(added['transport'], expected);
        expect(added['deviceId'], 'known-device');
      },
    );
  }

  testWidgets('pairing fallback preserves its device and modern wireless type', (
    tester,
  ) async {
    final backend = _Backend(
      record: {
        'id': 'paired-device',
        'transport': 'tls',
        'guid': 'paired-guid',
        'status': 'offline',
      },
    );
    final router = await _mount(
      tester,
      backend,
      const ConnectionFormRoute(
        pairing: true,
        address: 'phone.local',
        port: '37123',
      ).location,
    );
    await tester.enterText(find.byType(TextFormField).at(2), '123456');
    await tester.ensureVisible(find.text('配对并检查连接'));
    await tester.tap(find.text('配对并检查连接'));
    await tester.pumpAndSettle();
    final paired = backend.calls.singleWhere((call) => call.$1 == 'devices.pair');
    expect(paired.$2['code'], '123456');
    expect(paired.$2.containsKey('transport'), isFalse);
    await Scrollable.ensureVisible(
      tester.element(find.text('填写连接端口')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('填写连接端口'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['transport'],
      'tls',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '5555');
    final added = await _submit(tester, backend);
    expect(added['deviceId'], 'paired-device');
    expect(added['transport'], 'tls');
  });
}
