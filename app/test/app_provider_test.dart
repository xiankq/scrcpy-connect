import 'package:scrcpy_connect/widgets/remote_views.dart';
import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';
import 'package:scrcpy_connect/models/app_state.dart';

ProviderContainer scope(
  ApplicationRequest request, {
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
  test('类型化调用直接使用执行接口', () async {
    final calls = <ApplicationCommand>[];
    final receipt = Completer<Json>();
    final container = ProviderContainer(
      overrides: [
        appDependenciesProvider.overrideWithValue(
          AppDependencies(
            request: (_, [params = const {}]) =>
                throw StateError('类型化调用不能退回 wire 分派'),
            execute: (command, params) {
              calls.add(command);
              expect(params, {'sessionId': 'session-owned'});
              return receipt.future;
            },
            initialize: false,
          ),
        ),
      ],
    );
    final notifier = container.read(appControllerProvider.notifier);
    final pending = notifier.execute(ApplicationCommand.sessionStop, {
      'sessionId': 'session-owned',
    });
    expect(calls, [ApplicationCommand.sessionStop]);
    receipt.complete({'stopped': true});
    expect(await pending, {'stopped': true});
    container.dispose();
  });

  for (final update in ['state.resynced', 'settings.changed']) {
    test('a late saved setting cannot overwrite $update authority', () async {
      final events = StreamController<Json>.broadcast(sync: true);
      final saving = Completer<Json>();
      final container = scope(
        (command, [params = const {}]) => saving.future,
        events: events.stream,
      );
      final notifier = container.read(appControllerProvider.notifier);
      final pending = notifier.updateSetting('appearance', 'dark');
      await Future<void>.delayed(Duration.zero);
      const authoritative = <String, dynamic>{
        'appearance': 'system',
        'backgroundKeepAlive': true,
      };
      if (update == 'state.resynced') {
        events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
        events.add({
          'type': update,
          'data': {
            'devices': <Json>[],
            'sessions': <Json>[],
            'shares': <Json>[],
            'settings': authoritative,
            'sequence': 9,
          },
        });
      } else {
        events.add({'type': update, 'data': authoritative});
      }
      saving.complete({'appearance': 'dark', 'backgroundKeepAlive': false});
      await pending;
      expect(notifier.snapshot().settings, authoritative);
      container.dispose();
      await events.close();
    });
  }

  test('duplicate verified snapshots cannot forget that a view resumed presentation', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    final commands = <String>[];
    final container = scope((command, [params = const {}]) async {
      commands.add(command);
      return {};
    }, events: events.stream);
    final notifier = container.read(appControllerProvider.notifier);
    final views = RemoteViews(notifier);
    addTearDown(views.dispose);
    final view = views.claimSessionViewLease('live', visible: true);
    final snapshot = <String, dynamic>{
      'devices': <Json>[],
      'settings': <String, dynamic>{},
      'shares': <Json>[],
      'sequence': 1,
      'sessions': [
        {'sessionId': 'live', 'status': 'paused', 'capturePaused': true},
      ],
    };
    events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
    expect(notifier.snapshot().reconciliationPending, isTrue);
    events.add({'type': 'state.resynced', 'data': snapshot});
    expect(notifier.snapshot().reconciliationPending, isFalse);
    await view.resume();
    events.add({'type': 'state.resynced', 'data': snapshot});
    await view.release();
    expect(commands, ['session.resume', 'session.pause']);
    expect(
      () => notifier.snapshot().reconciledSnapshot!['sequence'] = 2,
      throwsUnsupportedError,
    );
    container.dispose();
    await events.close();
  });

  test('dependency replacement invalidates old recovery owners and ignores late snapshots', () async {
    final oldEvents = StreamController<Json>.broadcast(sync: true);
    final newEvents = StreamController<Json>.broadcast(sync: true);
    final commands = <String>[];
    Future<Json> request(String command, [Json params = const {}]) async {
      commands.add(command);
      return {};
    }

    final container = scope(request, events: oldEvents.stream);
    final oldController = container.read(appControllerProvider.notifier);
    final views = RemoteViews(oldController);
    addTearDown(views.dispose);
    final oldView = views.claimSessionViewLease('old', visible: true);
    oldEvents.add({'type': 'state.resync', 'data': <String, dynamic>{}});
    container.updateOverrides([
      appDependenciesProvider.overrideWithValue(
        AppDependencies(
          request: request,
          events: newEvents.stream,
          initialize: false,
          initialState: AppState(
            devices: [
              {'id': 'new'},
            ],
          ),
        ),
      ),
    ]);
    final current = container.read(appControllerProvider.notifier);
    expect(current.snapshot().devices.single['id'], 'new');
    expect(oldView.isCurrent, isFalse);
    oldEvents.add({
      'type': 'state.resynced',
      'data': {
        'devices': [
          {'id': 'stale'},
        ],
        'sessions': <Json>[],
        'sequence': 1,
      },
    });
    await oldView.release();
    expect(current.snapshot().devices.single['id'], 'new');
    expect(commands, isEmpty);
    container.dispose();
    await oldEvents.close();
    await newEvents.close();
  });

  test('resync replaces authoritative projections and fences older reads without replay', () async {
    final events = StreamController<Json>.broadcast(sync: true);
    final oldDevices = Completer<Json>();
    final oldSettings = Completer<Json>();
    final oldShares = Completer<Json>();
    final commands = <String>[];
    final container = scope(
      (command, [params = const {}]) {
        commands.add(command);
        return switch (command) {
          'devices.list' => oldDevices.future,
          'settings.get' => oldSettings.future,
          'sharing.pending' => oldShares.future,
          _ => Future.value(<String, dynamic>{}),
        };
      },
      events: events.stream,
      initialState: AppState(
        pendingShares: [
          {'shareId': 'gone'},
        ],
      ),
    );
    final notifier = container.read(appControllerProvider.notifier);
    final reads = [
      notifier.refreshDevices(),
      notifier.loadSettings(),
      notifier.loadPendingShares(),
    ];
    Json? stateSeenByListener;
    final listener = notifier.eventStream().listen((event) {
      if (event['type'] == 'state.resynced') {
        stateSeenByListener = notifier.snapshot().devices.single;
      }
    });
    events.add({'type': 'state.resync', 'data': <String, dynamic>{}});
    events.add({
      'type': 'state.resynced',
      'data': {
        'devices': [
          {'id': 'verified'},
        ],
        'settings': {'appearance': 'dark'},
        'shares': [
          {'shareId': 'current', 'status': 'ready'},
        ],
        'sessions': <Json>[],
        'sequence': 42,
      },
    });
    oldDevices.complete({
      'devices': [
        {'id': 'stale'},
      ],
    });
    oldSettings.complete({'appearance': 'light'});
    oldShares.complete({
      'shares': [
        {'shareId': 'stale'},
      ],
    });
    await Future.wait(reads);
    final restored = notifier.snapshot();
    expect(restored.devices.single['id'], 'verified');
    expect(stateSeenByListener?['id'], 'verified');
    expect(restored.settings, {'appearance': 'dark'});
    expect(restored.pendingShares.single['shareId'], 'current');
    expect(commands, ['devices.list', 'settings.get', 'sharing.pending']);
    await listener.cancel();
    container.dispose();
    await events.close();
  });

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
      final first = Completer<Json>(), second = Completer<Json>();
      final updates = <Json>[];
      final container = scope((command, [params = const {}]) async {
        if (command == 'settings.get') return oldRead.future;
        updates.add(params);
        return switch (updates.length) {
          1 => first.future,
          2 => second.future,
          _ => params,
        };
      });
      addTearDown(container.dispose);
      final notifier = container.read(appControllerProvider.notifier);
      final reading = notifier.loadSettings();
      final saveFirst = notifier.updateSetting('appearance', 'dark');
      await Future<void>.delayed(Duration.zero);
      final saveSecond = notifier.updateSetting('background', true);
      first.complete({'appearance': 'dark'});
      await saveFirst;
      expect(notifier.snapshot().settings, {'appearance': 'dark'});
      second.complete({'background': true});
      await saveSecond;
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
      await Future.wait([
        notifier.rememberAppOpenMode('phone', 'com.one', 'phone'),
        notifier.rememberAppOpenMode('phone', 'com.two', 'window'),
        notifier.rememberAppOpenMode('tablet', 'com.one', 'window'),
      ]);
      const modes = {
        'phone': {'com.one': 'phone', 'com.two': 'window'},
        'tablet': {'com.one': 'window'},
      };
      expect(
        container.read(appControllerProvider).settings['appOpenModes'],
        modes,
      );
      expect(updates.last['appOpenModes'], modes);
      final releaseFirst = notifier.claimAppOpen('phone', 'com.one')!;
      expect(notifier.claimAppOpen('phone', 'com.one'), isNull);
      final other = notifier.claimAppOpen('phone', 'com.two')!;
      releaseFirst();
      final next = notifier.claimAppOpen('phone', 'com.one')!;
      releaseFirst();
      expect(notifier.claimAppOpen('phone', 'com.one'), isNull);
      next();
      other();
    },
  );
}
