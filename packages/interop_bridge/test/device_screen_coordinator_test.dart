import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/device_screen_coordinator.dart';

Map<String, dynamic> device(String? token) => {
  'id': 'phone',
  'status': token == null ? 'offline' : 'connected',
  'connectionId': token,
  'autoReconnect': true,
};

Map<String, dynamic> snapshot(int sequence, String? token) => {
  'sequence': sequence,
  'devices': [device(token)],
  'settings': {
    'backgroundConnection': true,
    'deviceSettings': {
      'phone': {'wakeOnConnect': true},
    },
  },
  for (final key in [
    'sessions',
    'sources',
    'transfers',
    'activities',
    'shares',
    'companions',
  ])
    key: <Object>[],
};

Map<String, dynamic> changed(int sequence, String? token) => {
  'sequence': sequence,
  'type': 'devices.changed',
  'data': {
    'devices': [device(token)],
  },
};

void baseline(DeviceScreenCoordinator owner, int sequence, String? token) =>
    owner.handleEvent({
      'type': 'state.resynced',
      'data': snapshot(sequence, token),
    });

void main() {
  test('ADB baseline, connect, reconnect and settings never perform screen actions', () async {
    final calls = <String>[];
    final errors = <Map<String, dynamic>>[];
    final owner = DeviceScreenCoordinator(
      request: (command, _) async {
        calls.add(command);
        return {};
      },
      emit: errors.add,
    );
    addTearDown(owner.dispose);
    baseline(owner, 1, null);
    owner.handleEvent(changed(2, 'one'));
    owner.handleEvent(changed(3, null));
    owner.handleEvent(changed(4, 'two'));
    owner.handleEvent({
      'type': 'settings.changed',
      'sequence': 5,
      'data': snapshot(5, null)['settings'],
    });
    owner.handleEvent({'type': 'state.resync'});
    owner.handleEvent(changed(6, 'unverified'));
    baseline(owner, 7, 'restored');
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    expect(errors, isEmpty);
    expect(owner.isConnectionCurrent('phone', 'restored'), isTrue);
    expect(owner.isConnectionCurrent('phone', 'one'), isFalse);
  });

  test('stale snapshots and out of order connection events cannot restore old identity', () {
    final owner = DeviceScreenCoordinator(
      request: (_, _) async => {},
      emit: (_) {},
    );
    baseline(owner, 3, 'first');
    owner.handleEvent(changed(4, 'new'));
    owner.handleEvent(changed(2, 'old'));
    baseline(owner, 1, 'older');
    expect(owner.isConnectionCurrent('phone', 'new'), isTrue);
    owner.handleEvent({
      'type': 'devices.changed',
      'sequence': 5,
      'data': {'devices': <Object>[]},
    });
    expect(owner.isConnectionCurrent('phone', 'new'), isFalse);
    owner.dispose();
  });
}
