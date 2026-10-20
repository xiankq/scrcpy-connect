import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/connection_policy.dart';
import 'package:interop_bridge/src/connection_setup_coordinator.dart';
import 'package:interop_bridge/src/interop_exception.dart';

Future<void> settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.value();
  }
}

Matcher code(String expected) =>
    isA<InteropException>().having((e) => e.code, 'code', expected);

class Host {
  final calls = <(String, SetupJson)>[];
  final events = <SetupJson>[];
  final delays = <Duration>[];
  var now = DateTime.utc(2026);
  List<SetupJson> devices = [
    {'id': 'phone', 'connectionId': 'c1', 'serial': 'serial'},
  ];
  Future<SetupJson> Function(String, SetupJson)? respond;
  Future<void> Function(Duration)? waiting;
  Future<SetupJson> request(String command, SetupJson params) async {
    calls.add((command, Map.of(params)));
    if (command == 'devices.list') return {'devices': devices};
    return await respond?.call(command, params) ?? {};
  }

  ConnectionSetupCoordinator owner({
    ConnectionPolicy policy = const ConnectionPolicy(),
    Future<SetupJson> Function(SetupJson)? authorize,
    Future<void> Function(SetupJson)? release,
    Future<void> Function(SetupJson)? cancel,
    Future<void> Function() Function(String)? hold,
  }) => ConnectionSetupCoordinator(
    request: request,
    policy: policy,
    emit: events.add,
    authorizeUsb: authorize,
    releaseUsb: release,
    cancelUsb: cancel,
    holdDevice: hold,
    now: () => now,
    delay: (duration) async {
      delays.add(duration);
      now = now.add(duration);
      await waiting?.call(duration);
    },
  );
}

void main() {
  test('pairing continuation is held before explicit discovery execution and only caller retries changed epochs', () async {
    final host = Host();
    var connected = 0, held = false, released = false;
    host.respond = (command, params) async {
      if (command == 'adb.pair') {
        return {
          'operationId': 'pair-op',
          'paired': true,
          'deviceId': 'phone',
          'connected': false,
        };
      }
      if (command == 'devices.connect') {
        expect(held, true);
        expect(params['parentOperationId'], 'pair-op');
        expect(params['candidateSource'], 'discovery');
        if (connected++ == 0) {
          throw const InteropException('discovery_pending', 'no DNS');
        }
        if (connected == 2) {
          throw const InteropException('discovery_changed', 'new epoch');
        }
        return {'connected': true, 'deviceId': 'phone'};
      }
      return {};
    };
    final owner = host.owner(
      hold: (id) {
        held = true;
        return () async {
          released = true;
        };
      },
    );
    addTearDown(owner.dispose);
    final result = await owner.request('devices.pair', {
      'address': 'phone.local',
      'port': 37001,
      'code': '123456',
    });
    expect(result['paired'], true);
    expect(result['connected'], true);
    expect(connected, 3);
    expect(released, true);
    expect(
      host.calls
          .where((c) => c.$1 == 'adb.operation.release')
          .single
          .$2['operationId'],
      'pair-op',
    );
    expect(host.calls.where((c) => c.$1 == 'adb.pair').length, 1);
  });

  test('stop while unknown-device pairing is in flight prevents connection when its device ID is learned', () async {
    final host = Host();
    final pair = Completer<SetupJson>();
    host.respond = (command, params) async =>
        command == 'adb.pair' ? pair.future : {};
    final owner = host.owner();
    addTearDown(owner.dispose);
    final result = owner.request('devices.pair', {
      'attemptId': 'form',
      'address': 'phone.local',
      'port': 1,
      'code': '123456',
    });
    await settle();
    owner.beforeRequest('devices.disconnect', {'deviceId': 'phone'});
    pair.complete({
      'operationId': 'pair-op',
      'deviceId': 'phone',
      'paired': true,
      'connected': false,
    });
    await expectLater(result, throwsA(code('cancelled')));
    expect(host.calls.where((call) => call.$1 == 'devices.connect'), isEmpty);
    expect(host.calls.any((call) => call.$1 == 'adb.operation.release'), true);
  });

  test('lost QR completion event is recovered by querying the operation rather than pairing again', () async {
    final host = Host();
    var checked = 0;
    host.respond = (command, params) async {
      if (command == 'adb.pair.qr') {
        return {
          'operationId': 'qr-op',
          'attemptId': params['attemptId'],
          'payload': 'WIFI:T:ADB;',
        };
      }
      if (command == 'adb.operation.get') {
        return {
          'outcome': checked++ == 0
              ? {'status': 'waiting'}
              : {
                  'status': 'completed',
                  'result': {
                    'paired': true,
                    'deviceId': 'phone',
                    'connected': true,
                  },
                },
        };
      }
      return {};
    };
    final owner = host.owner();
    addTearDown(owner.dispose);
    final receipt = await owner.request('devices.pair.qr', {
      'attemptId': 'qr-form',
    });
    expect(receipt['payload'], 'WIFI:T:ADB;');
    await settle();
    expect(host.events.single['data']['status'], 'paired');
    expect(host.events.single['data']['attemptId'], 'qr-form');
    expect(host.calls.where((call) => call.$1 == 'adb.pair.qr').length, 1);
    expect(checked, 2);
  });

  test('TCPIP default, exact restart response, retry timing and one native execution per retry belong to Dart', () async {
    final host = Host();
    var attempts = 0;
    host.respond = (command, params) async {
      if (command == 'adb.tcpip.begin') {
        expect(params['port'], 5555);
        expect(params['connectionId'], 'c1');
        return {
          'operationId': 'tcp-op',
          'responseBytes': 'restarting in TCP mode port: 5555\n'.codeUnits,
        };
      }
      if (command == 'adb.tcpip.connect') {
        if (attempts++ == 0) {
          throw const InteropException('unreachable', 'not yet listening');
        }
        return {'connected': true, 'deviceId': 'phone'};
      }
      return {};
    };
    final owner = host.owner();
    addTearDown(owner.dispose);
    final result = await owner.request('devices.wireless', {
      'deviceId': 'phone',
      'address': 'phone.local',
    });
    expect(result['enabled'], true);
    expect(result['encrypted'], false);
    expect(attempts, 2);
    expect(host.delays, [const Duration(milliseconds: 300)]);
    expect(host.calls.where((call) => call.$1 == 'adb.tcpip.begin').length, 1);
  });

  test(
    'wrong-port or rejected TCPIP receipt never starts target connection',
    () async {
      for (final response in [
        'restarting in TCP mode port: 5556',
        'error: restarting in TCP mode port: 5555',
      ]) {
        final host = Host();
        host.respond = (command, params) async => command == 'adb.tcpip.begin'
            ? {'operationId': 'tcp-op', 'responseBytes': response.codeUnits}
            : {};
        final owner = host.owner();
        await expectLater(
          owner.request('devices.wireless', {
            'deviceId': 'phone',
            'address': 'phone.local',
          }),
          throwsA(code('wireless_setup_failed')),
        );
        expect(
          host.calls.where((call) => call.$1 == 'adb.tcpip.connect'),
          isEmpty,
        );
        await owner.dispose();
      }
    },
  );

  test('disconnect during caller TCPIP backoff cancels the lease and cannot submit another native connect', () async {
    final host = Host();
    final delay = Completer<void>();
    host.waiting = (_) => delay.future;
    host.respond = (command, params) async {
      if (command == 'adb.tcpip.begin') {
        return {
          'operationId': 'tcp-op',
          'responseBytes': 'restarting in TCP mode port: 5555'.codeUnits,
        };
      }
      if (command == 'adb.tcpip.connect') {
        throw const InteropException('unreachable', 'not yet');
      }
      return {};
    };
    final owner = host.owner();
    addTearDown(owner.dispose);
    final result = owner.request('devices.wireless', {
      'deviceId': 'phone',
      'address': 'phone.local',
    });
    await settle();
    owner.beforeRequest('activities.stop', {
      'activityId': 'audio:phone',
      'deviceId': 'phone',
    });
    await settle();
    expect(host.calls.where((call) => call.$1 == 'devices.cancel'), isEmpty);
    owner.beforeRequest('devices.disconnect', {'deviceId': 'phone'});
    delay.complete();
    await expectLater(result, throwsA(code('cancelled')));
    expect(
      host.calls.where((call) => call.$1 == 'adb.tcpip.connect').length,
      1,
    );
  });

  test('desktop USB without platform authorization opens and admits the native selection', () async {
    final host = Host();
    host.respond = (command, params) async => switch (command) {
      'adb.usb.open' => {
        'operationId': 'desktop-usb',
        'metadata': {'serial': 'serial'},
      },
      'adb.usb.attach' => {'connected': true, 'deviceId': 'phone'},
      _ => {},
    };
    final owner = host.owner();
    addTearDown(owner.dispose);
    final result = await owner.request('devices.usb', {
      'attemptId': 'desktop',
      'usbDeviceId': 'attached-device',
    });
    expect(result['connected'], true);
    final opened = host.calls
        .where((call) => call.$1 == 'adb.usb.open')
        .single
        .$2;
    expect(opened.containsKey('fd'), false);
    expect(opened['usbDeviceId'], 'attached-device');
    expect(host.calls.where((call) => call.$1 == 'adb.usb.attach').single.$2, {
      'operationId': 'desktop-usb',
      'deviceId': 'phone',
    });
    expect(host.calls.last.$1, 'adb.operation.release');
    expect(host.calls.last.$2, {'operationId': 'desktop-usb'});
  });

  test('desktop USB selection is returned without admitting or releasing a nonexistent operation', () async {
    final host = Host();
    final selection = {
      'selectionRequired': true,
      'devices': [
        {'usbDeviceId': 'first'},
        {'usbDeviceId': 'second'},
      ],
    };
    host.respond = (command, params) async => selection;
    final owner = host.owner();
    addTearDown(owner.dispose);
    expect(await owner.request('devices.usb', {}), selection);
    expect(host.calls.map((call) => call.$1), ['adb.usb.open']);
  });

  test('ambiguous USB record association closes native pending lease and always releases platform handoff', () async {
    final host = Host()
      ..devices = [
        {'id': 'a', 'serial': 'same'},
        {'id': 'b', 'serial': 'same'},
      ];
    final platform = <String>[];
    host.respond = (command, params) async => command == 'adb.usb.open'
        ? {
            'operationId': 'usb-op',
            'metadata': {'serial': 'same'},
          }
        : {};
    final owner = host.owner(
      authorize: (params) async => {'fd': 11, 'usbLeaseId': 'os-lease'},
      release: (params) async {
        platform.add(params['usbLeaseId'] as String);
      },
    );
    addTearDown(owner.dispose);
    await expectLater(
      owner.request('devices.usb', {}),
      throwsA(code('usb_selection_required')),
    );
    expect(platform, ['os-lease']);
    expect(host.calls.where((call) => call.$1 == 'adb.usb.attach'), isEmpty);
    expect(host.calls.any((call) => call.$1 == 'adb.operation.release'), true);
  });

  test('late USB permission after disposal releases system lease without opening native transport', () async {
    final host = Host();
    final permission = Completer<SetupJson>();
    final released = <String>[], cancelled = <String>[];
    final owner = host.owner(
      authorize: (params) => permission.future,
      release: (params) async {
        released.add(params['usbLeaseId'] as String);
      },
      cancel: (params) async {
        cancelled.add(params['attemptId'] as String);
      },
    );
    final result = owner.request('devices.usb', {'attemptId': 'usb-form'});
    await settle();
    await owner.dispose();
    permission.complete({'fd': 11, 'usbLeaseId': 'late-os-lease'});
    await expectLater(result, throwsA(code('cancelled')));
    expect(released, ['late-os-lease']);
    expect(cancelled, ['usb-form']);
    expect(host.calls.where((call) => call.$1 == 'adb.usb.open'), isEmpty);
  });
}
