import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/src/connection_policy.dart';
import 'package:interop_bridge/src/device_screen_coordinator.dart';
import 'package:interop_bridge/src/interop_exception.dart';
import 'package:interop_bridge/src/reconnection_coordinator.dart';
import 'package:interop_bridge/src/state_recovery.dart';

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
  test('startup baseline precedes automatic connect, even without UI listeners', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final scheduled = <void Function()>[];
    late DeviceScreenCoordinator screens;
    late ReconnectionCoordinator reconnect;
    Future<Map<String, dynamic>> request(
      String command,
      Map<String, dynamic> params,
    ) async {
      calls.add((command, params));
      if (command == 'state.snapshot') return snapshot(1, null);
      if (command == 'devices.connect') {
        final event = changed(2, 'startup-connection');
        screens.handleEvent(event);
        reconnect.handleEvent(event);
      }
      return {};
    }

    screens = DeviceScreenCoordinator(request: request, emit: (_) {});
    reconnect = ReconnectionCoordinator(
      request: request,
      policy: const ConnectionPolicy(),
      schedule: (_, run) {
        final timer = Timer(const Duration(days: 1), run);
        scheduled.add(() {
          timer.cancel();
          run();
        });
        return timer;
      },
    );
    final recovery = StateRecovery(
      read: (_) => request('state.snapshot', {}),
      emit: (event) {
        screens.handleEvent(event);
        reconnect.handleEvent(event);
      },
      isDisposed: () => false,
    );
    addTearDown(() async {
      screens.dispose();
      recovery.dispose();
      await reconnect.dispose();
    });
    // This is the production initialization order, before AppController exists.
    await recovery.refresh();
    await reconnect.start();
    await Future<void>.delayed(Duration.zero);
    expect(scheduled, hasLength(1));
    scheduled.single();
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.where((call) => call.$1 == 'devices.wake').map((call) => call.$2),
      [
        {'deviceId': 'phone', 'connectionId': 'startup-connection'},
      ],
    );
    expect(
      calls.indexWhere((call) => call.$1 == 'state.snapshot'),
      lessThan(calls.indexWhere((call) => call.$1 == 'devices.connect')),
    );
  });

  test('existing transport is quiet; each later token wakes once without offline snapshots', () async {
    final tokens = <Object?>[];
    final owner = DeviceScreenCoordinator(
      request: (_, params) async {
        tokens.add(params['connectionId']);
        return {};
      },
      emit: (_) {},
    );
    addTearDown(owner.dispose);
    baseline(owner, 1, 'old');
    owner.handleEvent(changed(2, 'old'));
    owner.handleEvent(changed(3, 'new'));
    owner.handleEvent(changed(4, 'new'));
    owner.handleEvent(changed(5, 'newer'));
    owner.handleEvent(changed(2, 'old'));
    await Future<void>.delayed(Duration.zero);
    expect(tokens, ['new', 'newer']);
  });

  test(
    'unknown result is consumed before request and recovery never replays it',
    () async {
      final failure = Completer<Map<String, dynamic>>();
      final calls = <Object?>[];
      final errors = <Map<String, dynamic>>[];
      final owner = DeviceScreenCoordinator(
        request: (_, params) {
          calls.add(params['connectionId']);
          return failure.future;
        },
        emit: errors.add,
      );
      addTearDown(owner.dispose);
      baseline(owner, 1, null);
      owner.handleEvent(changed(2, 'one'));
      owner.handleEvent(changed(3, 'one'));
      failure.completeError(
        const InteropException('result_unknown', 'unknown'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(errors.single['type'], 'device.screen.failed');
      owner.handleEvent({'type': 'state.resync'});
      owner.handleEvent(changed(4, 'unverified'));
      baseline(owner, 5, 'one');
      owner.handleEvent(changed(6, 'one'));
      expect(calls, ['one']);
    },
  );

  test(
    'settings toggles and missing tokens never manufacture a connection wake',
    () async {
      final calls = <Object?>[];
      final owner = DeviceScreenCoordinator(
        request: (_, params) async {
          calls.add(params['connectionId']);
          return {};
        },
        emit: (_) {},
      );
      addTearDown(owner.dispose);
      final initial = snapshot(1, null);
      initial['settings'] = <String, dynamic>{};
      owner.handleEvent({'type': 'state.resynced', 'data': initial});
      owner.handleEvent(changed(2, 'one'));
      owner.handleEvent({
        'type': 'settings.changed',
        'sequence': 3,
        'data': snapshot(3, null)['settings'],
      });
      owner.handleEvent(changed(4, 'one'));
      owner.handleEvent(changed(5, null));
      owner.handleEvent(changed(6, 'one'));
      owner.handleEvent(changed(7, 'two'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['two']);
    },
  );

  test(
    'late stale transport errors and disposed owners never show failure',
    () async {
      final pending = <Completer<Map<String, dynamic>>>[];
      final errors = <Map<String, dynamic>>[];
      final owner = DeviceScreenCoordinator(
        request: (_, _) {
          final result = Completer<Map<String, dynamic>>();
          pending.add(result);
          return result.future;
        },
        emit: errors.add,
      );
      baseline(owner, 1, null);
      owner.handleEvent(changed(2, 'one'));
      owner.handleEvent(changed(3, 'two'));
      pending[0].completeError(StateError('old failure'));
      pending[1].completeError(
        const InteropException('stale_connection', 'stale'),
      );
      await Future<void>.delayed(Duration.zero);
      owner.handleEvent(changed(4, 'three'));
      owner.dispose();
      pending[2].completeError(StateError('disposed failure'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
    },
  );
}
