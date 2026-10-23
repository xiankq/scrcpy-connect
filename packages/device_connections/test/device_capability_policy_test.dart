import 'package:flutter_test/flutter_test.dart';
import 'package:device_connections/device_connections.dart';
import 'package:device_protocol/device_protocol.dart';

class FactsHost {
  final calls = <String>[];
  SetupJson device = {
    'id': 'phone',
    'address': 'phone.local',
    'port': 5555,
    'transport': 'tls',
    'guid': null,
    'apiLevel': null,
  };
  SetupJson observations = {};
  SetupJson identity = {'status': 'ok'};
  List<SetupJson> audio = [], sessions = [];
  bool connected = false;
  String? token;
  Future<SetupJson> request(String command, SetupJson params) async {
    calls.add(command);
    if (command == 'settings.get') return {'adbBurstMode': true};
    if (command == 'devices.list') {
      return {
        'devices': [
          {...device, 'connectionId': token},
        ],
      };
    }
    expect(command, 'adb.device.probe');
    return {
      'deviceId': 'phone',
      'device': Map.of(device),
      'connected': connected,
      'connectionId': token,
      'observations': observations,
      'identity': identity,
      'usbBackendAvailable': true,
      'activities': {'sessions': sessions},
      'audio': {'sources': audio},
      'companion': <String, dynamic>{},
    };
  }

  DeviceCapabilityPolicy policy({Future<SetupJson> Function()? video}) =>
      DeviceCapabilityPolicy(
        request: request,
        policy: const ConnectionPolicy(),
        localVideoCapabilities: video,
      );
}

SetupJson entry(SetupJson result, String id) => (result['capabilities'] as List)
    .cast<SetupJson>()
    .singleWhere((item) => item['id'] == id);

void main() {
  test('offline and unknown observations stay unknown without starting any remote activity', () async {
    final host = FactsHost();
    final result = await host.policy().request('device.capabilities', {
      'deviceId': 'phone',
    });
    for (final name in [
      'screen',
      'audio',
      'notifications',
      'calls',
      'wirelessPairing',
    ]) {
      expect(entry(result, name)['status'], 'unknown');
    }
    expect(host.calls, ['adb.device.probe', 'devices.list']);
  });

  test('verified package observation, SDK constraints, active capture and actual playback remain separate evidence', () async {
    final host = FactsHost()
      ..connected = true
      ..token = 'live-1';
    host.device['apiLevel'] = 29;
    host.observations = {
      'shell': {
        'status': 'ok',
        'stdout': 'interop-capability-check',
        'exitCode': 0,
      },
      'sync': {'status': 'ok'},
      'packages': {
        'status': 'ok',
        'stdout': 'package:android\n',
        'exitCode': 0,
      },
    };
    var result = await host.policy().request('device.capabilities', {
      'deviceId': 'phone',
    });
    expect(entry(result, 'shell')['status'], 'available');
    expect(entry(result, 'apps')['status'], 'available');
    expect(entry(result, 'screen')['status'], 'limited');
    expect(entry(result, 'audio')['status'], 'unavailable');
    host.device['apiLevel'] = 36;
    host.sessions = [
      {'deviceId': 'phone', 'status': 'streaming'},
    ];
    host.audio = [
      {'deviceId': 'phone', 'status': 'playing', 'nativeAttached': false},
    ];
    result = await host.policy().request('device.capabilities', {
      'deviceId': 'phone',
    });
    expect(entry(result, 'screen')['status'], 'available');
    expect(entry(result, 'audio')['status'], 'unknown');
    host.audio.single['nativeAttached'] = true;
    result = await host.policy().request('device.capabilities', {
      'deviceId': 'phone',
    });
    expect(entry(result, 'audio')['status'], 'available');
  });

  test('missing selected private key and network permission denial are not reported as identity ready or unreachable', () async {
    final host = FactsHost()
      ..identity = {'status': 'error', 'code': 'identity_unavailable'};
    host.observations = {
      'tcp': {'status': 'error', 'code': 'permission_denied'},
    };
    final result = await host.policy().request('device.diagnose', {
      'deviceId': 'phone',
    });
    expect(result['identityPresent'], false);
    expect(result['identityError'], 'identity_unavailable');
    expect(result['tcpReachable'], null);
    expect(result['networkError'], 'permission_denied');
    expect(
      (result['notes'] as List).any((note) => '$note'.contains('主控网络权限')),
      true,
    );
    expect(result['adbBurstRequested'], true);
  });

  test(
    'an address can be reachable while current authorization is absent',
    () async {
      final host = FactsHost()..identity = {'status': 'ok'};
      host.device['status'] = 'unauthorized';
      host.observations = {
        'tcp': {'status': 'ok'},
      };
      final result = await host.policy().request('device.diagnose', {
        'deviceId': 'phone',
      });
      expect(result['tcpReachable'], true);
      expect(result['connected'], false);
      expect(result['identityPresent'], true);
      expect((result['device'] as Map)['status'], 'unauthorized');
    },
  );

  test('connection replacement while querying host video facts rejects late capability results', () async {
    final host = FactsHost()
      ..connected = true
      ..token = 'old';
    host.device['apiLevel'] = 36;
    final policy = host.policy(
      video: () async {
        host.token = 'new';
        return {};
      },
    );
    await expectLater(
      policy.request('device.capabilities', {'deviceId': 'phone'}),
      throwsA(
        isA<InteropException>().having(
          (error) => error.code,
          'code',
          'stale_connection',
        ),
      ),
    );
  });
}
