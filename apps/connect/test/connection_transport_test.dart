import 'support/test_controller.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/pages/connection_form/connection_form_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

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
    if (command == 'devices.connect' && connectFailure != null) {
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
  testWidgets('pairing authentication failure explains current-window retry', (
    tester,
  ) async {
    const failure = RequestFailure(
      'device_error',
      'invalid ADB protocol: pairing authentication failed (incorrect code or channel)',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: const Scaffold(
          body: ConnectionFailureNote(
            failure: failure,
            pairing: true,
            legacyTcp: false,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<ConnectionFailureNote>(find.byType(ConnectionFailureNote))
          .failure,
      same(failure),
    );
    expect(
      find.text('配对验证未通过。请确认正在使用被控手机当前配对窗口的端口和配对码，重新打开配对窗口后重试。'),
      findsOneWidget,
    );
    expect(find.text(failure.message), findsNothing);
    expect(find.textContaining('完成前中断'), findsNothing);
    expect(find.textContaining('码错误'), findsNothing);
  });

  testWidgets('certificate rejection explains how to pair again', (
    tester,
  ) async {
    const raw = 'ADB I/O: received fatal alert: CertificateUnknown';
    final backend = _Backend(
      connectFailure: const RequestFailure('device_error', raw),
    );
    await _mount(
      tester,
      backend,
      const ConnectionFormRoute(address: 'phone.local', port: '37123').location,
    );
    await _submit(tester, backend);
    expect(find.text(raw), findsNothing);
    expect(find.textContaining('被控设备未信任此主控的授权身份'), findsOneWidget);
    expect(find.textContaining('使用配对码'), findsWidgets);
    expect(find.text('重新配对'), findsOneWidget);
  });

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
    await tester.ensureVisible(find.text('连接设备'));
    await tester.tap(find.text('连接设备'));
    await tester.pumpAndSettle();
    final additions = backend.calls.where((call) => call.$1 == 'devices.add');
    expect(additions, hasLength(2));
    expect(additions.last.$2['deviceId'], 'new-device');
  });

  testWidgets('pairing EOF explains interruption without blaming the code', (
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
    await tester.ensureVisible(find.text('配对并检查连接'));
    await tester.tap(find.text('配对并检查连接'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ConnectionFailureNote>(find.byType(ConnectionFailureNote))
          .failure,
      same(backend.pairFailure),
    );
    expect(find.textContaining('配对连接在完成前中断，暂时无法确认原因'), findsOneWidget);
    expect(find.textContaining('重新打开配对窗口'), findsWidgets);
    expect(find.textContaining('码错误'), findsNothing);
    expect(find.textContaining('未信任'), findsNothing);
    expect(find.text('已配对，正在确认连接'), findsNothing);
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
    await tester.ensureVisible(find.text('配对并检查连接'));
    await tester.tap(find.text('配对并检查连接'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('配对并检查连接'));
    await tester.pumpAndSettle();
    expect(
      backend.calls.where((call) => call.$1 == 'devices.pair'),
      hasLength(1),
    );
  });

  testWidgets(
    'connection timeout offers reachability checks rather than pairing',
    (tester) async {
      final backend = _Backend(
        connectFailure: const RequestFailure(
          'timeout',
          'ADB operation timed out',
        ),
      );
      await _mount(
        tester,
        backend,
        const ConnectionFormRoute(
          address: 'phone.local',
          port: '37123',
        ).location,
      );
      await _submit(tester, backend);
      expect(find.textContaining('连接超时'), findsOneWidget);
      expect(find.textContaining('地址、连接端口和网络'), findsOneWidget);
      expect(find.text('重新配对'), findsNothing);
      expect(find.textContaining('未信任'), findsNothing);
      expect(find.text('尚未配对？使用配对码'), findsOneWidget);
    },
  );

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
      await tester.ensureVisible(find.text('尚未配对？使用配对码'));
      await tester.tap(find.text('尚未配对？使用配对码'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['device-id'],
        'known-device',
      );
      expect(find.text('使用配对码'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(2))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '38123');
      await tester.enterText(find.byType(TextFormField).at(2), '234567');
      await tester.ensureVisible(find.text('配对并检查连接'));
      await tester.tap(find.text('配对并检查连接'));
      await tester.pumpAndSettle();
      final paired = backend.calls.singleWhere(
        (call) => call.$1 == 'devices.pair',
      );
      expect(paired.$2['deviceId'], 'known-device');
      expect(paired.$2['port'], 38123);
      expect(paired.$2['code'], '234567');
    },
  );

  testWidgets(
    'repairing certificate rejection retains the newly added device',
    (tester) async {
      final backend = _Backend(
        record: {
          'id': 'new-device',
          'transport': 'tls',
          'status': 'unauthorized',
        },
        connectFailure: const RequestFailure(
          'device_error',
          'ADB I/O: received fatal alert: CertificateUnknown',
        ),
      );
      final router = await _mount(
        tester,
        backend,
        const ConnectionFormRoute(
          address: 'phone.local',
          port: '37123',
        ).location,
      );
      await _submit(tester, backend);
      await tester.ensureVisible(find.text('重新配对'));
      await tester.tap(find.text('重新配对'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['device-id'],
        'new-device',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(2))
            .controller!
            .text,
        isEmpty,
      );
      expect(backend.calls.where((call) => call.$1 == 'devices.pair'), isEmpty);
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

  testWidgets(
    'pairing fallback preserves its device and modern wireless type',
    (tester) async {
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
      final paired = backend.calls.singleWhere(
        (call) => call.$1 == 'devices.pair',
      );
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
    },
  );
}
