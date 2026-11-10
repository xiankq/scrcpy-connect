import 'package:scrcpy_connect/models/application_request.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/pages/connection/form/connection_form_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';

class _Backend {
  _Backend({this.service, this.record, this.connectFailure, this.pairFailure});

  final Json? service;
  final Json? record;
  final RequestFailure? connectFailure;
  final RequestFailure? pairFailure;
  final calls = <(String, Json)>[];
  late final controller = createTestController(request)..loading = false;

  Future<Json> request(String command, [Json params = const {}]) async {
    calls.add((command, Map<String, dynamic>.from(params)));
    if ((command == 'devices.connect' || command == 'devices.configure') &&
        connectFailure != null) {
      throw connectFailure!;
    }
    if (command == 'devices.pair' && pairFailure != null) {
      throw pairFailure!;
    }
    return switch (command) {
      'devices.discover' => {
        'devices': [if (service != null) service],
      },
      'device.info' => record ?? {},
      'devices.configure' => {
        'deviceId': params['deviceId'],
        'connected': true,
        'device': {'id': params['deviceId'], 'status': 'connected'},
      },
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

Future<void> _confirmConfiguration(WidgetTester tester) async {
  final action = find.widgetWithText(FilledButton, '应用并连接');
  if (action.evaluate().isNotEmpty) {
    await tester.tap(action);
    await tester.pumpAndSettle();
  }
}

Future<Json> _submit(WidgetTester tester, _Backend backend) async {
  final editing = tester
      .widget<ConnectionFormPage>(find.byType(ConnectionFormPage))
      .reauthorizing;
  await Scrollable.ensureVisible(
    tester.element(find.text('连接设备')),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('连接设备'));
  await tester.pumpAndSettle();
  await _confirmConfiguration(tester);
  final added = backend.calls.singleWhere(
    (call) => call.$1 == (editing ? 'devices.configure' : 'devices.add'),
  );
  if (editing) {
    expect(
      backend.calls.where((c) => c.$1 == 'devices.connect'),
      isEmpty,
      reason: 'configuration already verifies and connects the candidate transactionally',
    );
  } else {
    final connected = backend.calls.singleWhere(
      (call) => call.$1 == 'devices.connect',
    );
    expect(connected.$2['attemptId'], added.$2['attemptId']);
    expect(connected.$2['deviceId'], backend.record?['id'] ?? 'new-device');
  }
  return added.$2;
}

void main() {
  for (final kind in ['tcp', 'tls']) {
    testWidgets('reauthorization keeps identity and $kind in the IP mode', (
      tester,
    ) async {
      final backend = _Backend(
        record: {
          'id': 'known-device',
          'name': '手机',
          'address': 'phone.local',
          'transport': kind,
          'status': 'offline',
        },
      );
      await _mount(
        tester,
        backend,
        const AddDeviceRoute(deviceId: 'known-device').location,
      );
      await tester.tap(find.text('IP 连接'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '37123');
      final added = await _submit(tester, backend);
      expect(added['address'], 'phone.local');
      expect(added['deviceId'], 'known-device');
      expect(added['transport'], kind);
    });
  }

  testWidgets('retrying a rejected connection reuses the added device', (
    tester,
  ) async {
    final backend = _Backend(
      connectFailure: const RequestFailure(
        'device_error',
        'ADB I/O: received fatal alert: CertificateUnknown',
      ),
    );
    await _mount(
      tester,
      backend,
      const ConnectionFormRoute(address: 'phone.local', port: '37123').location,
    );
    await _submit(tester, backend);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    final additions = backend.calls.where((call) => call.$1 == 'devices.add');
    expect(additions, hasLength(2));
    expect(additions.last.$2['deviceId'], 'new-device');
  });

  testWidgets('a failed pairing requires a fresh code before another request', (
    tester,
  ) async {
    final backend = _Backend(
      pairFailure: const RequestFailure(
        'device_error',
        'ADB I/O: unexpected EOF',
      ),
    );
    await _mount(
      tester,
      backend,
      const ConnectionFormRoute(
        pairing: true,
        address: 'phone.local',
        port: '37123',
      ).location,
    );
    await tester.enterText(find.byType(TextFormField).at(2), '123456');
    await Scrollable.ensureVisible(
      tester.element(find.text('配对并连接')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('配对并连接'));
    await tester.pumpAndSettle();
    await _confirmConfiguration(tester);
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('配对并连接'));
    await tester.pumpAndSettle();
    await _confirmConfiguration(tester);
    expect(
      backend.calls.where((call) => call.$1 == 'devices.pair'),
      hasLength(1),
    );
  });

  testWidgets(
    'network failure keeps the ordinary pairing option and its device',
    (tester) async {
      const raw = 'Connection refused (os error 111)';
      final backend = _Backend(
        record: {'id': 'known-device', 'transport': 'tls', 'status': 'offline'},
        connectFailure: const RequestFailure('io_error', raw),
      );
      final router = await _mount(
        tester,
        backend,
        const ConnectionFormRoute(
          deviceId: 'known-device',
          address: 'phone.local',
          port: '37123',
        ).location,
      );
      await _submit(tester, backend);
      expect(find.text(raw), findsOneWidget);
      expect(find.text('重新配对'), findsNothing);
      expect(find.textContaining('未信任'), findsNothing);
      await tester.tap(find.text('返回修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('配对码'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['device-id'],
        'known-device',
      );
      expect(find.text('配对码'), findsNWidgets(2));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(2))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '38123');
      await tester.enterText(find.byType(TextFormField).at(2), '234567');
      await Scrollable.ensureVisible(
        tester.element(find.text('配对并连接')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('配对并连接'));
      await tester.pumpAndSettle();
      await _confirmConfiguration(tester);
      final paired = backend.calls.singleWhere(
        (call) => call.$1 == 'devices.pair',
      );
      expect(paired.$2['deviceId'], 'known-device');
      expect(paired.$2['port'], 38123);
      expect(paired.$2['code'], '234567');
    },
  );

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
          router
              .routeInformationProvider
              .value
              .uri
              .queryParameters['transport'],
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

  testWidgets('a paired legacy TCP record keeps TLS on manual update', (
    tester,
  ) async {
    final backend = _Backend(
      record: const {
        'id': 'known-device',
        'transport': 'tcp',
        'guid': 'paired-guid',
        'status': 'offline',
      },
    );
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
    expect(added['transport'], 'tls');
    expect(added['deviceId'], 'known-device');
  });
}
