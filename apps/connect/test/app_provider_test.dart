import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_dependencies.dart';
import 'package:scrcpy_connect/services/app_state.dart';

ProviderContainer scope(
  BridgeRequest request, {
  Stream<Json> events = const Stream<Json>.empty(),
  AppState? initialState,
  Future<void> Function()? close,
}) => ProviderContainer(
  overrides: [
    appDependenciesProvider.overrideWithValue(
      AppDependencies(
        request: request,
        events: events,
        initialState: initialState,
        close: close,
        initialize: false,
      ),
    ),
  ],
);

void main() {
  test(
    'generated notifier snapshots deeply freeze transport collections',
    () async {
      final source = <String, dynamic>{
        'devices': <Json>[
          {
            'id': 'phone',
            'metadata': <String, dynamic>{
              'ports': <int>[1, 2],
            },
          },
        ],
      };
      final container = scope((command, [params = const {}]) async => source);
      addTearDown(container.dispose);
      final notifier = container.read(appControllerProvider.notifier);
      await notifier.refreshDevices();
      final snapshot = container.read(appControllerProvider);
      final device = snapshot.devices.single;
      final metadata = jsonObject(device['metadata']);
      final ports = values(metadata['ports']);
      expect(
        () => snapshot.devices.add({'id': 'other'}),
        throwsUnsupportedError,
      );
      expect(() => device['id'] = 'changed', throwsUnsupportedError);
      expect(() => ports.add(3), throwsUnsupportedError);
      (source['devices'] as List<Json>).single['id'] = 'changed outside';
      expect(snapshot.devices.single['id'], 'phone');
    },
  );

  test(
    'older refresh receipts cannot replace the latest device records',
    () async {
      final first = Completer<Json>();
      final second = Completer<Json>();
      var requests = 0;
      final container = scope(
        (command, [params = const {}]) =>
            ++requests == 1 ? first.future : second.future,
      );
      addTearDown(container.dispose);
      final notifier = container.read(appControllerProvider.notifier);
      final old = notifier.refreshDevices();
      final current = notifier.refreshDevices();
      second.complete({
        'devices': <Json>[
          {'id': 'new'},
        ],
      });
      await current;
      first.complete({
        'devices': <Json>[
          {'id': 'stale'},
        ],
      });
      await old;
      expect(container.read(appControllerProvider).devices.single['id'], 'new');
      expect(container.read(appControllerProvider).loading, isFalse);
    },
  );

  test(
    'scope disposal owns the transport subscription and drops late work',
    () async {
      final events = StreamController<Json>.broadcast(sync: true);
      final pending = Completer<Json>();
      var closes = 0;
      final container = scope(
        (command, [params = const {}]) => pending.future,
        events: events.stream,
        close: () async {
          closes++;
        },
      );
      final notifier = container.read(appControllerProvider.notifier);
      final work = notifier.refreshDevices();
      expect(events.hasListener, isTrue);
      container.dispose();
      expect(events.hasListener, isFalse);
      pending.complete({
        'devices': <Json>[
          {'id': 'late'},
        ],
      });
      await work;
      expect(notifier.isDisposed(), isTrue);
      expect(closes, 1);
      await events.close();
    },
  );

  test(
    'native frames reach owned listeners without invalidating app state',
    () async {
      final events = StreamController<Json>.broadcast(sync: true);
      final container = scope(
        (command, [params = const {}]) async => {},
        events: events.stream,
      );
      final notifier = container.read(appControllerProvider.notifier);
      final state = container.read(appControllerProvider);
      final received = <Json>[];
      final session = notifier.eventStream().listen(received.add);
      var changes = 0;
      final subscription = container.listen(appControllerProvider, (_, next) {
        changes++;
      });
      events.add({
        'type': 'session.frame',
        'data': {'sessionId': 'bound', 'framesDecoded': 1},
      });
      expect(received.single['type'], 'session.frame');
      expect(identical(container.read(appControllerProvider), state), isTrue);
      expect(changes, 0);
      events.add({
        'type': 'device.updated',
        'data': {'status': 'offline'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(changes, greaterThan(0));
      subscription.close();
      await session.cancel();
      container.dispose();
      await events.close();
    },
  );

  test(
    'saved settings serialize and stale settings reads cannot undo them',
    () async {
      final oldRead = Completer<Json>();
      final updates = <Json>[];
      final container = scope((command, [params = const {}]) async {
        if (command == 'settings.get') return oldRead.future;
        updates.add(params);
        return params;
      });
      addTearDown(container.dispose);
      final notifier = container.read(appControllerProvider.notifier);
      final reading = notifier.loadSettings();
      await Future.wait([
        notifier.updateSetting('appearance', 'dark'),
        notifier.updateSetting('background', true),
      ]);
      oldRead.complete({'appearance': 'light'});
      await reading;
      expect(updates, [
        {'appearance': 'dark'},
        {'background': true},
      ]);
      expect(container.read(appControllerProvider).settings, {
        'appearance': 'dark',
        'background': true,
      });
    },
  );
}
